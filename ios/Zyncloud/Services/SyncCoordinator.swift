import Combine
import Foundation
import Photos
import os

/// - Note: `@unchecked Sendable` — every stored property below says in its own comment which
///   queue owns it: the `@Published` metrics are main-queue only, the queue/retry/override state
///   is `syncQueue` only, and the capabilities pair is behind ``capabilitiesLock``. That
///   discipline is what makes this safe; the compiler cannot check it, so it is asserted here.
final class SyncCoordinator: ObservableObject, @unchecked Sendable {
    static let shared = SyncCoordinator()

    @Published var metrics = Metrics()
    @Published var settings = Settings.shared

    private let photo = PhotoLibraryManager.shared
    /// Tells us whether uploads may run at all. Consulted in ``drainQueue()`` rather than
    /// anywhere else: that is the single door every export and every byte goes through, so
    /// gating it there is enough to stop the work — and to stop the -1009 errors that Wi‑Fi
    /// Only used to produce on cellular.
    private let network = NetworkMonitor.shared
    private let uploader = Uploader.shared
    // Phase 5 — TUS resumable uploads. Lives behind the server-advertised capability
    // (cachedCapabilities.tus.enabled). When that is false, drainQueue falls back to the
    // multipart `uploader`. Both uploaders share the same onTaskFinished
    // callback shape (adapted in init() below) so handleUploadFinished is path-agnostic.
    private let tusUploader = TusUploader.shared
    /// Guarded, for the same reason ``cachedApi`` is: this pair is written on the URLSession
    /// callback thread by `ensureCapabilitiesLoaded`, read on `syncQueue` by `drainQueue` and
    /// `enqueue`, and read on the main queue by `refreshSkippedTooLargeMetric`. Three threads,
    /// no synchronisation. The two fields are also read together — a TTL check that saw a fresh
    /// timestamp beside a nil payload would refetch on every batch — so they move under one lock
    /// rather than two.
    private let capabilitiesLock = NSLock()
    private var storedCapabilities: Capabilities?
    private var capabilitiesFetchedAt: Date?
    private let capabilitiesTTL: TimeInterval = 3600  // 1 hour

    /// The last capabilities we were told about, whether or not they are still fresh. Path
    /// selection and the size cap both want "the best answer we have", not "a fresh answer".
    private var cachedCapabilities: Capabilities? {
        capabilitiesLock.lock()
        defer { capabilitiesLock.unlock() }
        return storedCapabilities
    }

    /// The cached value only while it is inside the TTL — nil means "go and ask".
    private func freshCapabilities(now: Date = Date()) -> Capabilities? {
        capabilitiesLock.lock()
        defer { capabilitiesLock.unlock() }
        guard let capabilities = storedCapabilities,
              let fetchedAt = capabilitiesFetchedAt,
              now.timeIntervalSince(fetchedAt) < capabilitiesTTL
        else { return nil }
        return capabilities
    }

    private func storeCapabilities(_ capabilities: Capabilities, at date: Date = Date()) {
        capabilitiesLock.lock()
        storedCapabilities = capabilities
        capabilitiesFetchedAt = date
        capabilitiesLock.unlock()
    }

    /// The client to talk to the server with.
    ///
    /// Cached and invalidated on sign-out inside ``APIClientProvider`` — this class used to
    /// keep its own copy of that cache, as did the TUS uploader and six view models.
    ///
    /// Anonymous rather than nil when signed out: sync runs with no screen in front of it, so
    /// there is nobody to ask to sign in, and a logged 401 says more than doing nothing.
    private var api: APIClient { APIClientProvider.shared.clientOrAnonymous }

    struct Metrics {
        var queued: Int = 0
        var uploading: Int = 0
        var uploaded: Int = 0
        var inScope: Int = 0
        var lastSync: Date?
        /// Assets held back because they exceed the server's cap. Shown on the Sync tab: a
        /// backup with a silent hole in it is worse than one that says which files are missing.
        var skippedTooLarge: Int = 0
        /// Why uploads are not running, or nil when they are. Shown on the Status tab so a
        /// queue that is deliberately standing still does not read as a stuck one.
        var uploadPause: UploadPause?
    }

    private var syncQueue = DispatchQueue(label: "com.oglimmer.photosync.sync", qos: .utility)

    /// What is waiting, what is in flight, and the cap on how much may be in flight at once.
    /// Lives in ``UploadQueue`` rather than in three fields here so the rules — the cap itself,
    /// the 503 re-queue, the export-failure re-queue — can be tested without a photo library.
    /// Touched only on `syncQueue`.
    private var queue = UploadQueue<PHAsset>(maxInFlight: 3)

    // An asset whose original cannot be produced at all (iCloud copy unavailable, corrupt
    // resource) used to be re-appended every 10 s for as long as the app ran, burning the
    // queue slot forever. The give-up rule lives in ExportRetryPolicy so it can be tested
    // without standing up a coordinator. Touched only on syncQueue.
    private var exportRetryPolicy = ExportRetryPolicy()

    /// Whether ``drainQueue()`` is currently holding the queue back for the network. Kept so
    /// the pause is logged once per pause instead of once per drain — drainQueue is called on
    /// every enqueue and every finished upload. Touched only on syncQueue.
    private var pausedForNetwork = false

    /// Destination album for assets the user picked by hand on an album screen, keyed by local
    /// identifier. Everything absent from this map goes wherever the server's target-album
    /// setting says, which is what background sync has always done. Touched only on syncQueue.
    private var albumOverrides: [String: Int] = [:]

    /// How many hand-picked uploads are still outstanding per album. The album screen shows it
    /// and refreshes itself when its own count falls back to zero. Main queue only.
    @Published private(set) var albumUploadsInFlight: [Int: Int] = [:]

    /// Which of the current batch the server refused as duplicates, per album, as contentIds.
    ///
    /// The server dedupes by contentId across the whole account and a photo can belong to only
    /// one album, so picking one it already holds stores nothing and adds nothing here. Kept as
    /// ids rather than a count so the album screen can ask where each one actually lives, and
    /// tell "it is already in this album" apart from "it is in a different one". Silently
    /// reporting success and then showing an unchanged album is the worst of both. Reset when a
    /// new batch starts. Main queue only.
    @Published private(set) var albumUploadsRejectedAsDuplicate: [Int: [String]] = [:]

    /// Holds the ``Settings/wifiOnly`` subscription below. Set up in `init`, not `start()`,
    /// which runs again on every foreground and would stack duplicate subscriptions.
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Watch the link, and drain again the moment it becomes usable. Without this the queue
        // would sit paused until the next enqueue or the next background slot, which on a phone
        // that just walked into Wi-Fi range can be a long time.
        //
        // In `init` rather than in ``start()`` because a background launch never calls
        // ``start()`` — see the note in `AppDelegate` — and background runs are exactly where
        // the Wi-Fi-Only-on-cellular failures were logged.
        network.onChange = { [weak self] _ in
            guard let self else { return }
            self.syncQueue.async { self.drainQueue() }
        }
        network.start()

        // Turning Wi‑Fi Only off is the user saying "send it over cellular, now". Nothing else
        // would call drainQueue until the next enqueue or background slot, so the toggle would
        // appear to do nothing for minutes. `dropFirst` skips the value Combine replays on
        // subscribe, which is not a change.
        Settings.shared.$wifiOnly
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.syncQueue.async { self.drainQueue() }
            }
            .store(in: &cancellables)

        // Route actual upload completions through the coordinator so we can
        // free a slot, drain the next upload, and re-enqueue 503s with backoff.
        uploader.onTaskFinished = { [weak self] assetId, outcome in
            self?.handleUploadFinished(assetId: assetId, outcome: outcome)
        }
        // Phase 5 — TUS path uses a parallel UploadOutcome enum on TusUploader (structurally
        // identical to Uploader.UploadOutcome). Adapt to the shared shape so handleUploadFinished
        // doesn't need to know which path produced it.
        //
        // Special case: TUS PATCH responses don't carry the server asset id, so we get
        // .success(serverAssetId: nil). Resolve via contentId lookup with retry (handles the
        // post-finish hook race) before calling handleUploadFinished, otherwise
        // ProcessingStatusPoller would never start for TUS uploads.
        tusUploader.onTaskFinished = { [weak self] assetId, tusOutcome in
            guard let self else { return }
            switch tusOutcome {
            case let .success(serverAssetId):
                if let serverAssetId {
                    self.handleUploadFinished(
                        assetId: assetId,
                        outcome: .success(serverAssetId: serverAssetId),
                    )
                } else {
                    // albumOverrides is syncQueue-only. Snapshot it here so a hand-picked
                    // album-screen upload is looked up in the album it was sent to, not the
                    // background-sync target (default 1) — that 404s all 4 retries and
                    // ProcessingStatusPoller never starts.
                    self.syncQueue.async {
                        let albumId = UploadRouting.lookupAlbumId(
                            override: self.albumOverrides[assetId],
                            fallback: self.settings.snapshot.albumId,
                        )
                        // Not `[weak self]`: the `guard let self` above already made this whole
                        // chain hold a strong reference, so a weak capture here would read as a
                        // promise the surrounding block does not keep.
                        self.resolveTusUploadServerId(
                            contentId: assetId, albumId: albumId,
                        ) { resolved in
                            self.handleUploadFinished(
                                assetId: assetId,
                                outcome: .success(serverAssetId: resolved),
                            )
                        }
                    }
                }
            case .deduped:
                self.handleUploadFinished(assetId: assetId, outcome: .deduped)
            case .clientError:
                self.handleUploadFinished(assetId: assetId, outcome: .clientError)
            case .transport:
                self.handleUploadFinished(assetId: assetId, outcome: .transport)
            case let .backpressure(delay):
                self.handleUploadFinished(assetId: assetId, outcome: .backpressure(delay))
            }
        }
    }

    // MARK: - Public controls

    func start() {
        uploader.configureSession()
        tusUploader.configureSession()

        // Kick off capabilities fetch in the background. Doesn't block sync — drainQueue
        // falls back to the multipart path until the cache fills (or if the fetch fails).
        ensureCapabilitiesLoaded()

        // Clean up stale uploading entries from previous app sessions, preserving entries that
        // still have a live URLSession task (otherwise they would be uploaded twice) across
        // BOTH background sessions — multipart and TUS each have their own.
        //
        // The scan runs *inside* the completion rather than after it. Enumerating the sessions
        // is now asynchronous (§5.2), and the order still matters: a scan that starts before the
        // cleanup lands sees leftover "uploading" entries from the last launch and skips exactly
        // the assets that need retrying.
        activeUploadTaskAssetIds { [weak self] activeTasks in
            guard let self else { return }
            UploadStore.shared.cleanupStaleUploading(activeTasks: activeTasks)

            photo.requestAuthorization { status in
                guard status == .authorized || status == .limited else { return }

                // Check target album from server first
                self.syncTargetAlbumFromServer { _ in
                    // Only start sync if an album has been selected
                    guard self.settings.snapshot.selectedAlbumName != nil else { return }

                    // Reconcile with server before scanning
                    self.reconcileWithServer {
                        self.scheduleInitialScan()
                    }
                }
            }
        }
    }

    /// Union of the assets still in flight on either background session.
    ///
    /// Nested rather than parallel: there are exactly two sessions, both answers are needed
    /// before the cleanup can run, and a nested pair of callbacks is easier to read than a
    /// DispatchGroup for two items.
    private func activeUploadTaskAssetIds(completion: @escaping @Sendable (Set<String>) -> Void) {
        uploader.getActiveUploadAssetIds { [weak self] multipartTasks in
            guard let self else {
                completion(multipartTasks)
                return
            }
            tusUploader.getActiveUploadAssetIds { tusTasks in
                completion(multipartTasks.union(tusTasks))
            }
        }
    }

    func clearQueue() {
        syncQueue.async {
            self.queue.removeAll()
            self.exportRetryPolicy.reset()
            self.albumOverrides.removeAll()
            DispatchQueue.main.async {
                self.metrics.queued = 0
                self.metrics.uploading = 0
                self.albumUploadsInFlight.removeAll()
                self.albumUploadsRejectedAsDuplicate.removeAll()
            }
        }
    }

    func handlePhotoLibraryDidChange() {
        // Only sync if an album has been selected
        guard settings.snapshot.selectedAlbumName != nil else { return }

        // New items may exist — schedule incremental scan
        scheduleIncrementalScan()
    }

    /// What kicked a sync off. The two runs are the same work reported under different
    /// headings — the sync log separates manual from background so the user can tell "I asked
    /// for this" from "the system woke us up".
    enum SyncTrigger {
        case manual
        case background

        /// Human-readable name for the diagnostic log.
        var label: String {
            switch self {
            case .manual: "Manual sync"
            case .background: "Background sync"
            }
        }

        /// True for the entries the sync log renders as user-initiated.
        var isManual: Bool { self == .manual }
    }

    func performManualSync(completion: @escaping @Sendable () -> Void) {
        performSync(trigger: .manual, completion: completion)
    }

    func performBackgroundSync(completion: @escaping @Sendable () -> Void) {
        performSync(trigger: .background, completion: completion)
    }

    /// The one sync run, told what to call itself.
    ///
    /// Manual and background used to be two copies of this function that differed only in the
    /// word "Manual"/"Background" — so a fix to one silently skipped the other.
    private func performSync(trigger: SyncTrigger, completion: @escaping @Sendable () -> Void) {
        AppLog.sync.info("\(trigger.label, privacy: .public) started")
        SyncLogger.shared.logSync(trigger: trigger, success: true, message: "Started")

        // Check if target album changed on server
        syncTargetAlbumFromServer { targetAlbumChanged in
            // If target album is now null on server, stop sync
            guard self.settings.snapshot.selectedAlbumName != nil else {
                AppLog.sync.notice("\(trigger.label, privacy: .public) skipped — no target album selected")
                SyncLogger.shared.logSync(trigger: trigger, success: false, message: "No album selected")
                completion()
                return
            }

            // If target album changed, log it
            if targetAlbumChanged {
                AppLog.sync.info("Target album updated from server during \(trigger.label, privacy: .public)")
            }

            // Check photo library authorization
            let authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard authStatus == .authorized || authStatus == .limited else {
                AppLog.sync.error(
                    "\(trigger.label, privacy: .public) stopped — photo library access not authorized (\(authStatus.rawValue, privacy: .public))")
                SyncLogger.shared.logSync(trigger: trigger, success: false, message: "Photo access denied")
                completion()
                return
            }

            // Reconcile with server before scanning
            self.reconcileWithServer {
                self.scheduleIncrementalScan {
                    AppLog.sync.info("\(trigger.label, privacy: .public) completed successfully")
                    SyncLogger.shared.logSync(trigger: trigger, success: true, message: "Completed")
                    completion()
                }
            }
        }
    }

    // MARK: - Target Album Synchronization

    private func syncTargetAlbumFromServer(completion: @escaping @Sendable (Bool) -> Void) {
        api.getTargetAlbum { [weak self] result in
            guard let self else {
                completion(false)
                return
            }

            switch result {
            case let .success(serverAlbumId):
                // Check if server has a target album set
                guard let albumId = serverAlbumId else {
                    // Server has no target album - clear local selection. Completion must
                    // fire AFTER the main-queue clear so the caller's
                    // `guard settings.selectedAlbumName != nil` reads the updated value.
                    // Otherwise it observes the stale non-nil value and proceeds with a
                    // scan that produces a batch of doomed-to-400 uploads (the server
                    // rejects them with "sync is paused").
                    if settings.snapshot.selectedAlbumName != nil {
                        DispatchQueue.main.async {
                            self.settings.selectedAlbumName = nil
                            self.settings.albumId = 1
                            self.clearQueue()
                            AppLog.sync.notice("Target album cleared on the server — stopping sync")
                            completion(true)
                        }
                    } else {
                        completion(false)
                    }
                    return
                }

                // Check if target album changed
                if albumId != settings.snapshot.albumId {
                    // Fetch album details to get the name
                    api.fetchAlbums { [weak self] albumsResult in
                        guard let self else {
                            completion(false)
                            return
                        }

                        switch albumsResult {
                        case let .success(albums):
                            if let album = albums.first(where: { $0.id == albumId }) {
                                // Update local settings with server's target album
                                DispatchQueue.main.async {
                                    self.settings.albumId = album.id
                                    self.settings.selectedAlbumName = album.name
                                    AppLog.sync.info("Target album synced from server: \(album.name)")
                                }
                                completion(true)
                            } else {
                                AppLog.sync.error("Server target album \(albumId, privacy: .public) is not in the albums list")
                                completion(false)
                            }

                        case let .failure(error):
                            AppLog.sync.error("Could not fetch albums: \(error.localizedDescription, privacy: .public)")
                            completion(false)
                        }
                    }
                } else {
                    // Album ID matches - no change needed
                    completion(false)
                }

            case let .failure(error):
                AppLog.sync.error("Could not fetch the target album: \(error.localizedDescription, privacy: .public)")
                // Continue with existing settings on error
                completion(false)
            }
        }
    }

    func onUploadedOne(assetId _: String) {
        DispatchQueue.main.async {
            self.metrics.uploaded += 1
        }
    }

    // MARK: - Sync Reconciliation

    /// Marks everything the server already has, so the scan does not upload it a second time.
    ///
    /// Two sources, run in sequence, because neither covers the other (§5.8):
    ///
    /// * **contentIds** — `PHAsset.localIdentifier` values, matched directly. These belong to the
    ///   photo library rather than to this app, so they still mean something after a reinstall.
    ///   This is the one that works on a fresh install, where the local checksum map is empty.
    /// * **checksums** — matched through the local checksum→asset map. Useless on a fresh
    ///   install, but it is the only thing that recognises rows uploaded before the client
    ///   started sending a contentId, so it stays.
    ///
    /// Either request failing is non-fatal: reconciliation is an optimisation, and server-side
    /// dedupe is what actually prevents duplicate rows.
    func reconcileWithServer(completion: (@Sendable () -> Void)? = nil) {
        syncQueue.async {
            // N+1 days: the scan window plus a day of slack, so an asset taken just before the
            // boundary is not re-uploaded because the two windows disagree about "today".
            let days = self.settings.snapshot.syncLastDays + 1
            self.api.fetchUploadedContentIds(days: days) { contentIdResult in
                switch contentIdResult {
                case let .success(contentIds):
                    AppLog.sync.info("Reconciled: server holds \(contentIds.count, privacy: .public) contentIds")
                    UploadStore.shared.reconcileWithServerContentIds(contentIds)
                case let .failure(error):
                    // An older server has no such endpoint; the checksum pass below still runs.
                    AppLog.sync.notice("contentId reconciliation unavailable: \(error.localizedDescription, privacy: .public)")
                }

                self.api.fetchUploadedChecksums(days: days) { checksumResult in
                    switch checksumResult {
                    case let .success(checksums):
                        AppLog.sync.info("Reconciled: server holds \(checksums.count, privacy: .public) checksums")
                        UploadStore.shared.reconcileWithServerChecksums(checksums)
                    case let .failure(error):
                        AppLog.sync.error("Could not reconcile with the server: \(error.localizedDescription, privacy: .public)")
                    }
                    completion?()
                }
            }
        }
    }

    // MARK: - Hand-picked album uploads

    /// Uploads assets the user chose on an album screen straight into that album.
    ///
    /// Deliberately routed through the same queue as background sync rather than uploading
    /// directly: that is where the concurrency cap, the export-retry policy, the size refusal
    /// and the post-upload status polling live, and a second path would have none of them. The
    /// only difference is ``albumOverrides``, which names the destination per asset.
    ///
    /// Unlike a scan this does **not** skip assets already marked uploaded — the user asked for
    /// these files by hand. The server still dedupes by contentId, so an asset it already holds
    /// stays where it is instead of being copied into this album; see the caller's message.
    func uploadToAlbum(assets: [PHAsset], albumId: Int) {
        guard !assets.isEmpty else { return }

        uploader.configureSession()
        tusUploader.configureSession()
        ensureCapabilitiesLoaded()

        syncQueue.async {
            for asset in assets {
                self.albumOverrides[asset.localIdentifier] = albumId
            }

            let accepted = self.enqueue(assets: assets)

            // Count what was actually taken, not what was offered: an asset already in flight
            // is filtered out by enqueue, and counting it here would leave the album screen
            // waiting for an upload that is never going to report back.
            let acceptedIds = Set(accepted.map(\.localIdentifier))
            for asset in assets where !acceptedIds.contains(asset.localIdentifier) {
                self.albumOverrides.removeValue(forKey: asset.localIdentifier)
            }

            guard !accepted.isEmpty else { return }
            DispatchQueue.main.async {
                self.albumUploadsRejectedAsDuplicate.removeValue(forKey: albumId)
                self.albumUploadsInFlight[albumId, default: 0] += accepted.count
            }
        }
    }

    /// Drops one outstanding upload from the per-album counter. Called on every terminal
    /// outcome so the album screen cannot be left showing an upload that has finished.
    ///
    /// The duplicate tally is raised *before* the in-flight count falls, because the album
    /// screen reads it the moment that count reaches zero.
    private func finishAlbumUpload(assetId: String, wasDuplicate: Bool = false) {
        guard let albumId = albumOverrides.removeValue(forKey: assetId) else { return }
        DispatchQueue.main.async {
            if wasDuplicate {
                self.albumUploadsRejectedAsDuplicate[albumId, default: []].append(assetId)
            }
            let remaining = (self.albumUploadsInFlight[albumId] ?? 1) - 1
            if remaining > 0 {
                self.albumUploadsInFlight[albumId] = remaining
            } else {
                self.albumUploadsInFlight.removeValue(forKey: albumId)
            }
        }
    }

    // MARK: - Scanning

    private func scheduleInitialScan() {
        syncQueue.async {
            let days = self.settings.snapshot.syncLastDays
            let assets = self.photo.fetchAssets(lastDays: days)
            let filtered = assets.filter { !UploadStore.shared.isUploaded($0.localIdentifier) }
            AppLog.sync.info("""
            Initial scan: \(assets.count, privacy: .public) assets in the last \
            \(days, privacy: .public) days, \
            \(filtered.count, privacy: .public) not yet uploaded
            """)

            DispatchQueue.main.async {
                self.metrics.inScope = assets.count
            }

            self.enqueue(assets: filtered)
        }
    }

    private func scheduleIncrementalScan(onDone: (@Sendable () -> Void)? = nil) {
        syncQueue.async {
            // Calculate cutoff date based on syncLastDays
            let calendar = Calendar.current
            let now = Date()
            let settings = self.settings.snapshot
            let cutoffDate = calendar.date(byAdding: .day, value: -settings.syncLastDays, to: now) ?? .distantPast

            // Update in-scope count with all photos in the date range
            let allInScope = self.photo.fetchAssets(lastDays: settings.syncLastDays)
            DispatchQueue.main.async {
                self.metrics.inScope = allInScope.count
            }

            // Use the more recent of lastSyncDate or cutoffDate
            let since = max(settings.lastSyncDate ?? .distantPast, cutoffDate)
            let assets = self.photo.fetchAssets(since: since)
            let filtered = assets.filter { !UploadStore.shared.isUploaded($0.localIdentifier) }
            AppLog.sync.info("""
            Incremental scan: \(assets.count, privacy: .public) assets since \(since, privacy: .public), \
            \(filtered.count, privacy: .public) not yet uploaded
            """)
            self.enqueue(assets: filtered)
            onDone?()
        }
    }

    /// - Returns: the assets that actually joined the queue, so a caller that is tracking its
    ///   own batch knows how many completions to expect.
    @discardableResult
    private func enqueue(assets: [PHAsset]) -> [PHAsset] {
        guard !assets.isEmpty else { return [] }

        // Drop anything the server has already refused for size under a cap that has not since
        // been raised — re-exporting a 1.6 GB video on every scan to earn the same 413 helps
        // nobody. Assets already queued or uploading are the queue's own business.
        let sizeLimit = currentUploadSizeLimit()
        let admissible = assets.filter {
            !UploadStore.shared.shouldSkipForSize($0.localIdentifier, currentLimit: sizeLimit)
        }
        let newAssets = queue.enqueue(admissible)

        guard !newAssets.isEmpty else {
            AppLog.sync.debug("All \(assets.count, privacy: .public) assets are already queued or uploading — skipping")
            return []
        }

        AppLog.sync.info("Enqueuing \(newAssets.count, privacy: .public) of \(assets.count, privacy: .public) assets")
        publishQueuedCount()
        drainQueue()
        return newAssets
    }

    /// Copies the queue depth over to the metrics.
    ///
    /// The count is read here, on `syncQueue`, and only the number crosses to the main queue —
    /// reading the queue itself from inside the `main.async` block would be a second thread
    /// touching it while this one mutates it.
    private func publishQueuedCount() {
        let queued = queue.pendingCount
        DispatchQueue.main.async { self.metrics.queued = queued }
    }

    /// Whether uploads may start, and the bookkeeping that goes with the answer.
    ///
    /// Returns false to hold the queue as it is — nothing is dequeued, nothing is exported and
    /// nothing is marked failed, so the whole batch simply resumes later. The log line is
    /// written once per pause, and only while something is actually waiting: "paused" on an
    /// empty queue describes no held-back work and is pure noise.
    ///
    /// syncQueue only, like ``pausedForNetwork`` and ``queue``.
    private func networkGateIsOpen() -> Bool {
        let pause = network.pause(wifiOnly: settings.snapshot.wifiOnly)
        // Only on a real change: drainQueue runs on every enqueue and every finished upload,
        // and an unconditional write here would re-render the Status tab each time.
        DispatchQueue.main.async {
            if self.metrics.uploadPause != pause { self.metrics.uploadPause = pause }
        }

        guard let pause else {
            if pausedForNetwork {
                pausedForNetwork = false
                SyncLogger.shared.logUploadsResumed()
            }
            return true
        }

        if !pausedForNetwork, queue.pendingCount > 0 {
            pausedForNetwork = true
            SyncLogger.shared.logUploadsPaused(pause)
        }
        return false
    }

    private func drainQueue() {
        guard networkGateIsOpen() else { return }

        // Only launch enough uploads to fill the concurrency cap. New uploads
        // are handed off one-per-completion (see handleUploadFinished) so the
        // server never sees more than the queue's maxInFlight at once.
        let batch = queue.startNext()
        guard !batch.isEmpty else { return }

        let queued = queue.pendingCount
        DispatchQueue.main.async {
            self.metrics.queued = queued
            self.metrics.uploading += batch.count
        }

        // Phase 5 — pick the upload path once per batch, from the server-advertised
        // tus.enabled in /api/capabilities.
        // Decision is made per-batch (not per-asset) so a mid-batch capability flip can't
        // produce a half-multipart-half-TUS batch with race-prone state.
        let useTus = shouldUseTus()
        let uploadSizeLimit = currentUploadSizeLimit()
        for asset in batch {
            let completion: (@Sendable (Result<Void, Error>) -> Void) = { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    // Handoff succeeded; actual upload completion comes through
                    // {Uploader,TusUploader}.onTaskFinished -> handleUploadFinished.
                    // Clear any earlier export failures so a transient one (iCloud copy that
                    // arrives on the second try) doesn't count toward a later give-up.
                    self.syncQueue.async {
                        self.exportRetryPolicy.recordSuccess(for: asset.localIdentifier)
                    }
                case let .failure(error):
                    // Export / body-write failed — free the slot and try a replacement.
                    self.syncQueue.async {
                        let id = asset.localIdentifier
                        self.queue.finish(id)
                        DispatchQueue.main.async {
                            self.metrics.uploading = max(0, self.metrics.uploading - 1)
                        }

                        if case let .giveUp(attempts) = self.exportRetryPolicy.recordFailure(for: id) {
                            // Give up rather than re-queueing forever. Not marked uploaded, so
                            // a later scan retries it — this only ends the current spin.
                            SyncLogger.shared.logUploadFailure(
                                assetId: id,
                                error: "Export failed \(attempts)× — giving up: \(error.localizedDescription)"
                            )
                            self.finishAlbumUpload(assetId: id)
                            self.drainQueue()
                            return
                        }

                        self.syncQueue.asyncAfter(deadline: .now() + 10) {
                            self.queue.requeueBack(asset)
                            self.publishQueuedCount()
                            self.drainQueue()
                        }
                    }
                }
            }
            let albumId = albumOverrides[asset.localIdentifier]
            if useTus {
                tusUploader.queueUpload(asset: asset, api: api,
                                        maxUploadBytes: uploadSizeLimit, albumId: albumId,
                                        completion: completion)
            } else {
                uploader.queueUpload(asset: asset, api: api, albumId: albumId,
                                     completion: completion)
            }
        }
    }

    // MARK: - Phase 5 — Capabilities cache + path selection

    /// Returns true iff the server advertises tus.enabled (cached
    /// /api/capabilities). When capabilities haven't loaded yet — the
    /// first drainQueue after a fresh launch — this returns false, and the batch goes via
    /// the multipart path. The next refresh after ensureCapabilitiesLoaded completes flips
    /// the answer; subsequent batches use TUS.
    /// The cap to judge file sizes against: the live capabilities response when we have one,
    /// otherwise the last one we persisted, otherwise nil for "unknown, let the server decide".
    private func currentUploadSizeLimit() -> Int64? {
        if let advertised = cachedCapabilities?.tus.maxSize, advertised > 0 { return advertised }
        let remembered = Settings.shared.snapshot.tusMaxUploadBytes
        return remembered > 0 ? remembered : nil
    }

    private func refreshSkippedTooLargeMetric() {
        let limit = currentUploadSizeLimit()
        let count = UploadStore.shared.skippedTooLargeCount(currentLimit: limit)
        DispatchQueue.main.async { self.metrics.skippedTooLarge = count }
    }

    private func shouldUseTus() -> Bool {
        UploadRouting.selectPath(capabilities: cachedCapabilities) == .tus
    }

    /// Resolve the server-side asset id for a TUS upload, given the client's contentId
    /// (PHAsset.localIdentifier). Retries up to 4 times with backoff to ride out the
    /// post-finish hook race window (~200 ms typical; 1 s worst case observed in production
    /// — see Phase 5b bug-fix #4 in the plan). Calls completion with the resolved id, or
    /// nil if the row never appears (deleted? hook crashed?). nil disables status polling
    /// for that asset; the upload itself is still recorded as success.
    private func resolveTusUploadServerId(
        contentId: String,
        albumId: Int,
        attempt: Int = 0,
        completion: @escaping @Sendable (Int?) -> Void,
    ) {
        let maxAttempts = 4
        api.lookupAssetByContentId(albumId: albumId, contentId: contentId) { [weak self] result in
            switch result {
            case let .success(id):
                completion(id)
            case .failure where attempt < maxAttempts - 1:
                // 200ms, 400ms, 800ms — covers the typical race + a comfortable safety margin.
                let delay = 0.2 * pow(2.0, Double(attempt))
                // Resolved to a strong reference here rather than writing `self?` inside the
                // delayed block: `weak self` is a mutable variable, and reading it from a second,
                // concurrently-running closure is the race the compiler is pointing at.
                guard let self else { return }
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.resolveTusUploadServerId(
                        contentId: contentId,
                        albumId: albumId,
                        attempt: attempt + 1,
                        completion: completion,
                    )
                }
            case .failure:
                AppLog.sync.error("""
                Gave up resolving the server asset id after \(maxAttempts, privacy: .public) attempts — \
                status polling is off for this upload
                """)
                SyncLogger.shared.logProcessingStatusUnavailable(assetId: contentId)
                completion(nil)
            }
        }
    }

    /// Lazy fetch + 1-hour cache. Called from start() and refreshed implicitly here when the
    /// cache has expired. Failure is non-fatal — we just leave the cache empty and fall back
    /// to the multipart path until the next attempt.
    private func ensureCapabilitiesLoaded(completion: (@Sendable (Capabilities?) -> Void)? = nil) {
        if let cached = freshCapabilities() {
            completion?(cached)
            return
        }
        api.fetchCapabilities { [weak self] result in
            guard let self else { completion?(nil); return }
            switch result {
            case let .success(caps):
                self.storeCapabilities(caps)
                // Persist the cap so the next cold-launch scan can filter known-too-big assets
                // before exporting them, and so a raised cap un-skips what it now admits.
                DispatchQueue.main.async {
                    Settings.shared.tusMaxUploadBytes = caps.tus.maxSize
                    self.refreshSkippedTooLargeMetric()
                }
                completion?(caps)
            case let .failure(err):
                AppLog.sync.notice("Capabilities fetch failed (\(err.localizedDescription, privacy: .public)) — staying on the multipart path")
                completion?(nil)
            }
        }
    }

    private func handleUploadFinished(assetId: String, outcome: Uploader.UploadOutcome) {
        syncQueue.async {
            let asset = self.queue.finish(assetId)

            DispatchQueue.main.async {
                self.metrics.uploading = max(0, self.metrics.uploading - 1)
                self.metrics.lastSync = Date()
                self.settings.lastSyncDate = self.metrics.lastSync
            }

            switch outcome {
            case let .success(serverAssetId):
                self.finishAlbumUpload(assetId: assetId)
                // Bytes landed; the worker pod still has thumbnail/transcode
                // work to do. Poll /api/assets/{id}/status so we surface
                // post-upload pipeline failures (FAILED / DEAD_LETTER) instead
                // of silently treating "2xx" as the end of the story.
                if let serverAssetId {
                    ProcessingStatusPoller.shared.poll(serverAssetId: serverAssetId, contentId: assetId, api: self.api)
                }
                self.drainQueue()
            case .deduped:
                // The server already had this photo, so nothing was stored. Nothing to poll and
                // nothing to retry — but the album screen has to hear about it.
                self.finishAlbumUpload(assetId: assetId, wasDuplicate: true)
                self.drainQueue()
            case .clientError, .transport:
                // clientError: permanent failure; transport: system-retried.
                self.finishAlbumUpload(assetId: assetId)
                self.refreshSkippedTooLargeMetric()
                self.drainQueue()
            case let .backpressure(retryAfter):
                // Server asked us to back off. Re-enqueue this asset and pause
                // draining for retryAfter seconds so we don't hammer the server.
                if let asset {
                    AppLog.sync.notice("Server asked us to back off — re-queueing after \(Int(retryAfter), privacy: .public)s")
                    self.queue.requeueFront(asset)
                    self.publishQueuedCount()
                }
                self.syncQueue.asyncAfter(deadline: .now() + retryAfter) {
                    self.drainQueue()
                }
            }
        }
    }
}
