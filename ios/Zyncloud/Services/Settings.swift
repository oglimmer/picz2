import Combine
import Foundation
import os

/// The user's sync preferences, and the app's memory of what the server last said.
///
/// ## Reading these from a background thread
///
/// The `@Published` properties are **main-queue only**, like any `ObservableObject`. Every write
/// in the app already happens on main; the reads did not, and that was a real data race — the
/// scan queue reads ``syncLastDays`` and ``lastSyncDate`` while the main queue may be writing
/// them, with nothing in between.
///
/// ``snapshot`` is the fix. It is a plain value holding the same seven settings, kept in step by
/// every `didSet` and guarded by a lock, so a background reader gets one coherent set of values
/// rather than a torn read of a property mid-write. **Off the main queue, read ``snapshot``.**
///
/// - Note: `@unchecked Sendable` — the `@Published` storage is main-queue-confined by
///   convention, and the only cross-thread door, ``snapshot``, is behind ``snapshotLock``.
final class Settings: ObservableObject, @unchecked Sendable {
    static let shared = Settings()

    /// Every setting, as one value that can be read from any thread.
    ///
    /// A struct rather than seven individually-locked properties, so a reader that wants two of
    /// them cannot catch the pair mid-change and act on half an update.
    struct Snapshot: Sendable, Equatable {
        var wifiOnly: Bool
        var lastSyncDate: Date?
        var albumId: Int
        var selectedAlbumName: String?
        var syncLastDays: Int
        var useTus: Bool
        var tusMaxUploadBytes: Int64
    }

    private let snapshotLock = NSLock()
    private var storedSnapshot = Snapshot(
        wifiOnly: true, lastSyncDate: nil, albumId: 1, selectedAlbumName: nil,
        syncLastDays: 3, useTus: true, tusMaxUploadBytes: 0,
    )

    /// The settings as they stood a moment ago. Safe from any thread.
    var snapshot: Snapshot {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return storedSnapshot
    }

    /// Copies the published values into ``storedSnapshot``. Called from every `didSet`, and once
    /// at the end of `init` — a `didSet` does not run during initialisation, so without that
    /// last call the snapshot would hold the defaults above instead of what was on disk.
    private func refreshSnapshot() {
        snapshotLock.lock()
        storedSnapshot = Snapshot(
            wifiOnly: wifiOnly,
            lastSyncDate: lastSyncDate,
            albumId: albumId,
            selectedAlbumName: selectedAlbumName,
            syncLastDays: syncLastDays,
            useTus: useTus,
            tusMaxUploadBytes: tusMaxUploadBytes,
        )
        snapshotLock.unlock()
    }

    @Published var wifiOnly: Bool {
        didSet {
            defaults.set(wifiOnly, forKey: Keys.wifiOnly)
            refreshSnapshot()
        }
    }

    @Published var lastSyncDate: Date? {
        didSet {
            defaults.set(lastSyncDate, forKey: Keys.lastSyncDate)
            refreshSnapshot()
        }
    }

    @Published var albumId: Int {
        didSet {
            defaults.set(albumId, forKey: Keys.albumId)
            refreshSnapshot()
        }
    }

    @Published var selectedAlbumName: String? {
        didSet {
            defaults.set(selectedAlbumName, forKey: Keys.selectedAlbumName)
            refreshSnapshot()
        }
    }

    @Published var syncLastDays: Int {
        didSet {
            defaults.set(syncLastDays, forKey: Keys.syncLastDays)
            refreshSnapshot()
        }
    }

    // Phase 5 — TUS resumable uploads. Hidden TestFlight toggle. SyncCoordinator picks the
    // upload path by combining this flag with /api/capabilities.tus.enabled returned from the
    // server. R2 lights up server-side capabilities; flipping this flag opts a build into TUS.
    @Published var useTus: Bool {
        didSet {
            defaults.set(useTus, forKey: Keys.useTus)
            refreshSnapshot()
        }
    }

    /// Last `tus.maxSize` the server advertised, in bytes; 0 means "never asked yet".
    ///
    /// Persisted rather than kept only in ``SyncCoordinator/cachedCapabilities`` because the
    /// scan that decides what to enqueue runs on a cold launch, before capabilities come back.
    /// Without a remembered limit the first scan after every launch re-exports a file we
    /// already know the server will refuse — for a 1.6 GB video that is minutes of work and
    /// battery for a guaranteed failure.
    @Published var tusMaxUploadBytes: Int64 {
        didSet {
            defaults.set(tusMaxUploadBytes, forKey: Keys.tusMaxUploadBytes)
            refreshSnapshot()
        }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let wifiOnly = "settings.wifiOnly"
        static let tusMaxUploadBytes = "settings.tusMaxUploadBytes"
        static let lastSyncDate = "settings.lastSyncDate"
        static let albumId = "settings.albumId"
        static let selectedAlbumName = "settings.selectedAlbumName"
        static let syncLastDays = "settings.syncLastDays"
        static let useTus = "settings.useTus"
    }

    /// `defaults` is injectable purely so tests can drive a scratch suite instead of the
    /// user's real preferences. Production uses ``shared``.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        wifiOnly = defaults.object(forKey: Keys.wifiOnly) as? Bool ?? true
        lastSyncDate = defaults.object(forKey: Keys.lastSyncDate) as? Date
        albumId = defaults.object(forKey: Keys.albumId) as? Int ?? 1
        selectedAlbumName = defaults.object(forKey: Keys.selectedAlbumName) as? String
        syncLastDays = defaults.object(forKey: Keys.syncLastDays) as? Int ?? 3
        // R3 — TUS resumable uploads are the default for new installs (and any existing user
        // who never touched the toggle). UserDefaults.object returns nil iff the key was never
        // written, so a user who explicitly toggled OFF still gets `false` and is respected.
        useTus = defaults.object(forKey: Keys.useTus) as? Bool ?? true
        tusMaxUploadBytes = (defaults.object(forKey: Keys.tusMaxUploadBytes) as? NSNumber)?.int64Value ?? 0
        refreshSnapshot()
    }

    func clear() {
        defaults.removeObject(forKey: Keys.wifiOnly)
        defaults.removeObject(forKey: Keys.lastSyncDate)
        defaults.removeObject(forKey: Keys.albumId)
        defaults.removeObject(forKey: Keys.selectedAlbumName)
        defaults.removeObject(forKey: Keys.syncLastDays)
        defaults.removeObject(forKey: Keys.useTus)
        defaults.removeObject(forKey: Keys.tusMaxUploadBytes)

        // Reset to default values
        wifiOnly = true
        lastSyncDate = nil
        albumId = 1
        selectedAlbumName = nil
        syncLastDays = 3
        useTus = true  // R3 default
        tusMaxUploadBytes = 0  // unknown until the next /api/capabilities
    }
}

// MARK: - Network policy

extension URLRequest {
    /// Applies the "Wi‑Fi Only" setting to this request.
    ///
    /// This lives on the request rather than on the background ``URLSessionConfiguration``:
    /// a background session's configuration is frozen when the session is created, and
    /// creating a second session under the same identifier to pick up a toggle change is
    /// unsupported by URLSession. Per-request flags are honoured by background tasks and
    /// take effect immediately.
    mutating func applyNetworkPolicy() {
        // `snapshot`, not the published property: this runs on whichever thread is building
        // the request, which for an upload is never the main queue.
        let allowsCellular = !Settings.shared.snapshot.wifiOnly
        allowsCellularAccess = allowsCellular
        allowsExpensiveNetworkAccess = allowsCellular
        allowsConstrainedNetworkAccess = allowsCellular
    }
}

/// Everything `UploadStore` remembers, in one Codable value.
///
/// Kept as a single struct so the whole thing is one atomic file write. A half-written store —
/// completed ids saved but the checksum map not — would silently re-upload or silently skip.
struct UploadStoreState: Codable {
    var completed: Set<String> = []
    var uploading: Set<String> = []
    var checksumToLocalId: [String: String] = [:]
    /// localIdentifier -> the server byte limit that refused it (D43).
    var skippedTooLarge: [String: Int64] = [:]
}

/// What the user has already uploaded, so a scan does not send it twice.
///
/// **Storage (§5.7).** This used to live in `UserDefaults`, which is the wrong shape for it. The
/// completed-id set grows with the photo library — tens of thousands of entries for a real one —
/// and `UserDefaults` is a property list that is loaded whole at launch and re-serialised on
/// every write. So marking a single upload complete rewrote the entire history, several times
/// per asset once the checksum map is counted, and every launch paid to parse all of it before
/// the app could do anything.
///
/// Two changes fix that without a database. The state moves to one JSON file in Application
/// Support, off the launch path entirely; and writes are **coalesced** — a mutation marks the
/// state dirty and schedules a single write `saveDelay` later, so a burst of fifty completions
/// costs one serialisation instead of fifty. The data still grows with the library, because it
/// has to: "have I uploaded this?" cannot be answered without remembering.
///
/// Durability is therefore best-effort by design. ``flushPendingWrites()`` forces the write, and
/// the app calls it when it goes to the background; a hard kill inside the delay window can lose
/// the last second of bookkeeping, which costs a re-upload that server-side dedupe absorbs.
/// - Note: `@unchecked Sendable` — `state` and `dirty` are only touched inside ``queue``, and
///   every write goes through a `.barrier` block.
final class UploadStore: @unchecked Sendable {
    static let shared = UploadStore()

    private let fileURL: URL
    private let saveDelay: TimeInterval
    private var state: UploadStoreState
    private var dirty = false
    private var saveScheduled = false
    private let queue = DispatchQueue(label: "com.photocloud.uploadstore", attributes: .concurrent)

    /// Production path: `Application Support/UploadStore.json`.
    ///
    /// Application Support rather than Caches — the OS may evict Caches under storage pressure,
    /// and losing this file means re-uploading the entire library.
    static func defaultFileURL() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("UploadStore.json")
    }

    /// - Parameters:
    ///   - fileURL: where the state lives. Injectable so tests get a scratch file instead of the
    ///     user's real upload history.
    ///   - legacyDefaults: the `UserDefaults` to migrate from on first run, or nil to skip.
    ///   - saveDelay: how long to coalesce writes. Tests pass 0 and call
    ///     ``flushPendingWrites()`` when they want the file on disk.
    init(fileURL: URL = UploadStore.defaultFileURL(),
         legacyDefaults: UserDefaults? = .standard,
         saveDelay: TimeInterval = 1)
    {
        self.fileURL = fileURL
        self.saveDelay = saveDelay

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(UploadStoreState.self, from: data)
        {
            state = decoded
        } else if let legacyDefaults, let migrated = UploadStore.migrate(from: legacyDefaults) {
            state = migrated
            // Written immediately, not scheduled: if the app dies before the first coalesced
            // write the UserDefaults keys are already gone and the history would be lost.
            write(state)
            UploadStore.clearLegacyKeys(in: legacyDefaults)
        } else {
            state = UploadStoreState()
        }
    }

    // MARK: - Legacy UserDefaults migration

    private enum LegacyKeys {
        static let completed = "uploads.completed.ids"
        static let checksums = "uploads.checksums"
        static let uploading = "uploads.uploading.ids"
        static let skippedTooLarge = "uploads.skipped.tooLarge"
    }

    /// Reads the pre-§5.7 layout. Returns nil when there is nothing to migrate, so a fresh
    /// install does not write an empty file on first launch.
    private static func migrate(from defaults: UserDefaults) -> UploadStoreState? {
        let completed = defaults.stringArray(forKey: LegacyKeys.completed) ?? []
        let uploading = defaults.stringArray(forKey: LegacyKeys.uploading) ?? []
        let checksums = (defaults.data(forKey: LegacyKeys.checksums))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        let skipped = (defaults.data(forKey: LegacyKeys.skippedTooLarge))
            .flatMap { try? JSONDecoder().decode([String: Int64].self, from: $0) } ?? [:]

        if completed.isEmpty, uploading.isEmpty, checksums.isEmpty, skipped.isEmpty { return nil }
        AppLog.store.info("Migrating \(completed.count, privacy: .public) completed ids out of UserDefaults")
        return UploadStoreState(completed: Set(completed), uploading: Set(uploading),
                                checksumToLocalId: checksums, skippedTooLarge: skipped)
    }

    private static func clearLegacyKeys(in defaults: UserDefaults) {
        defaults.removeObject(forKey: LegacyKeys.completed)
        defaults.removeObject(forKey: LegacyKeys.checksums)
        defaults.removeObject(forKey: LegacyKeys.uploading)
        defaults.removeObject(forKey: LegacyKeys.skippedTooLarge)
    }

    // MARK: - Reads

    func isUploaded(_ localId: String) -> Bool {
        queue.sync {
            state.completed.contains(localId) || state.uploading.contains(localId)
        }
    }

    /// True when this asset was refused for size under a limit no smaller than the current one,
    /// so trying again would fail the same way.
    func shouldSkipForSize(_ localId: String, currentLimit: Int64?) -> Bool {
        queue.sync {
            guard let recorded = state.skippedTooLarge[localId] else { return false }
            return !UploadSizeLimit.shouldRetry(recordedLimit: recorded, currentLimit: currentLimit)
        }
    }

    /// How many assets are currently held back for size. Surfaced on the Sync tab — a count the
    /// user can see is the difference between "my videos are safe" and a silent hole in the backup.
    func skippedTooLargeCount(currentLimit: Int64?) -> Int {
        queue.sync {
            state.skippedTooLarge.values.filter {
                !UploadSizeLimit.shouldRetry(recordedLimit: $0, currentLimit: currentLimit)
            }.count
        }
    }

    // MARK: - Writes

    func markAsUploading(_ localId: String) {
        mutate { $0.uploading.insert(localId) }
    }

    func removeFromUploading(_ localId: String) {
        mutate { $0.uploading.remove(localId) }
    }

    func markUploaded(_ localId: String, checksum: String? = nil) {
        mutate {
            $0.completed.insert(localId)
            $0.uploading.remove(localId)
            if let checksum { $0.checksumToLocalId[checksum] = localId }
        }
    }

    /// Records that the server refused this asset for being larger than `limit` bytes.
    ///
    /// Not the same as uploaded: the bytes are not on the server, and this must never make the
    /// asset look backed up. It only stops the scan from re-exporting a file we know is refused.
    func markSkippedTooLarge(_ localId: String, limit: Int64) {
        mutate {
            $0.skippedTooLarge[localId] = limit
            $0.uploading.remove(localId)
        }
    }

    func reconcileWithServerChecksums(_ serverChecksums: [String]) {
        mutate { state in
            for checksum in serverChecksums {
                if let localId = state.checksumToLocalId[checksum] {
                    state.completed.insert(localId)
                    state.uploading.remove(localId)
                }
            }
        }
    }

    /// Marks assets the server already holds, matched by the contentId the client sent with them.
    ///
    /// This is the reconciliation that survives a reinstall (§5.8).
    /// ``reconcileWithServerChecksums(_:)`` can only mark ids it finds in the local
    /// checksum→localId map, which is empty on a fresh install — so it did nothing in exactly
    /// the situation it existed for. A contentId *is* the `PHAsset.localIdentifier`, which is a
    /// property of the photo library rather than of this app, so it still means something after
    /// the app has been deleted and reinstalled.
    func reconcileWithServerContentIds(_ contentIds: [String]) {
        mutate { state in
            for contentId in contentIds where !contentId.isEmpty {
                state.completed.insert(contentId)
                state.uploading.remove(contentId)
            }
        }
    }

    func storeChecksumMapping(checksum: String, localId: String) {
        mutate { $0.checksumToLocalId[checksum] = localId }
    }

    func clear() {
        mutate { $0 = UploadStoreState() }
    }

    func cleanupStaleUploading(activeTasks: Set<String> = []) {
        mutate { state in
            // Only clear uploading entries that don't have an active URLSession task — dropping
            // one that is still in flight would upload the same asset a second time.
            let stale = state.uploading.subtracting(activeTasks)
            state.uploading.subtract(stale)

            if !stale.isEmpty {
                AppLog.store.info("Cleaned up \(stale.count, privacy: .public) stale uploading entries")
            }
            if !activeTasks.isEmpty {
                AppLog.store.info("Preserved \(activeTasks.count, privacy: .public) active upload tasks")
            }
        }
    }

    // MARK: - Persistence

    /// Writes any pending changes now and waits for them.
    ///
    /// Called when the app goes to the background, and by tests that want to read the file back.
    func flushPendingWrites() {
        queue.sync(flags: .barrier) {
            guard dirty else { return }
            write(state)
            dirty = false
        }
    }

    private func mutate(_ body: @escaping @Sendable (inout UploadStoreState) -> Void) {
        queue.async(flags: .barrier) {
            body(&self.state)
            self.dirty = true
            self.scheduleSave()
        }
    }

    /// Call on the barrier queue only.
    ///
    /// One timer at a time: a burst of completions all set `dirty`, but only the first schedules
    /// a write, and that single write persists everything the burst did. This is the whole point
    /// of the change — the old store paid a full re-serialisation per upload.
    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        queue.asyncAfter(deadline: .now() + saveDelay, flags: .barrier) {
            self.saveScheduled = false
            guard self.dirty else { return }
            self.write(self.state)
            self.dirty = false
        }
    }

    /// Atomic so a crash mid-write leaves the previous state intact rather than a truncated file
    /// that decodes as "nothing has ever been uploaded".
    private func write(_ state: UploadStoreState) {
        guard let data = try? JSONEncoder().encode(state) else {
            AppLog.store.error("Could not encode the upload store")
            return
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.store.error("Could not write the upload store: \(error.localizedDescription, privacy: .public)")
        }
    }
}
