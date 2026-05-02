import Foundation
import Photos

final class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()

    @Published var metrics = Metrics()
    @Published var settings = Settings.shared

    private let photo = PhotoLibraryManager.shared
    private let uploader = Uploader.shared
    // Phase 5 — TUS resumable uploads. Lives behind the Settings.useTus toggle AND a server-
    // advertised capability (cachedCapabilities.tus.enabled). When either is false, drainQueue
    // falls back to the multipart `uploader`. Both uploaders share the same onTaskFinished
    // callback shape (adapted in init() below) so handleUploadFinished is path-agnostic.
    private let tusUploader = TusUploader.shared
    private var cachedCapabilities: Capabilities?
    private var capabilitiesFetchedAt: Date?
    private let capabilitiesTTL: TimeInterval = 3600  // 1 hour
    private var api: APIClient {
        let credentials = KeychainHelper.shared.load()
        return APIClient(
            username: credentials?.username,
            password: credentials?.password,
        )
    }

    struct Metrics {
        var queued: Int = 0
        var uploading: Int = 0
        var uploaded: Int = 0
        var inScope: Int = 0
        var lastSync: Date?
    }

    private var syncQueue = DispatchQueue(label: "com.oglimmer.photosync.sync", qos: .utility)
    private var pendingAssets: [PHAsset] = []
    private var uploadingAssets: Set<String> = [] // Track assets currently being uploaded
    private var inFlightAssets: [String: PHAsset] = [:] // localId -> PHAsset, kept for 503 re-queue
    private let maxInFlightUploads = 3

    private init() {
        // Route actual upload completions through the coordinator so we can
        // free a slot, drain the next upload, and re-enqueue 503s with backoff.
        uploader.onTaskFinished = { [weak self] assetId, outcome in
            self?.handleUploadFinished(assetId: assetId, outcome: outcome)
        }
        // Phase 5 — TUS path uses a parallel UploadOutcome enum on TusUploader (structurally
        // identical to Uploader.UploadOutcome). Adapt to the shared shape so handleUploadFinished
        // doesn't need to know which path produced it.
        tusUploader.onTaskFinished = { [weak self] assetId, tusOutcome in
            let outcome: Uploader.UploadOutcome
            switch tusOutcome {
            case let .success(serverAssetId): outcome = .success(serverAssetId: serverAssetId)
            case .clientError: outcome = .clientError
            case .transport: outcome = .transport
            case let .backpressure(delay): outcome = .backpressure(delay)
            }
            self?.handleUploadFinished(assetId: assetId, outcome: outcome)
        }
    }

    // MARK: - Public controls

    func start() {
        uploader.configureSession()
        tusUploader.configureSession()

        // Clean up stale uploading entries from previous app sessions
        // But preserve entries that have active URLSession tasks (to prevent duplicate uploads)
        // across BOTH background sessions — multipart and TUS each have their own.
        let activeTasks = uploader.getActiveUploadAssetIds()
            .union(tusUploader.getActiveUploadAssetIds())
        UploadStore.shared.cleanupStaleUploading(activeTasks: activeTasks)

        // Kick off capabilities fetch in the background. Doesn't block sync — drainQueue
        // falls back to the multipart path until the cache fills (or if the fetch fails).
        ensureCapabilitiesLoaded()

        photo.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }

            // Check target album from server first
            self.syncTargetAlbumFromServer { _ in
                // Only start sync if an album has been selected
                guard self.settings.selectedAlbumName != nil else { return }

                // Reconcile with server before scanning
                self.reconcileWithServer {
                    self.scheduleInitialScan()
                }
            }
        }
    }

    func clearQueue() {
        syncQueue.async {
            self.pendingAssets.removeAll()
            self.uploadingAssets.removeAll()
            self.inFlightAssets.removeAll()
            DispatchQueue.main.async {
                self.metrics.queued = 0
                self.metrics.uploading = 0
            }
        }
    }

    func handlePhotoLibraryDidChange() {
        // Only sync if an album has been selected
        guard settings.selectedAlbumName != nil else { return }

        // New items may exist — schedule incremental scan
        scheduleIncrementalScan()
    }

    func performManualSync(completion: @escaping () -> Void) {
        let syncStartTime = Date()
        print("SyncCoordinator: Manual sync started at \(syncStartTime)")
        SyncLogger.shared.logManualSync(success: true, message: "Started")

        // Check if target album changed on server
        syncTargetAlbumFromServer { targetAlbumChanged in
            // If target album is now null on server, stop sync
            guard self.settings.selectedAlbumName != nil else {
                print("SyncCoordinator: Manual sync skipped - no target album selected")
                SyncLogger.shared.logManualSync(success: false, message: "No album selected")
                completion()
                return
            }

            // If target album changed, log it
            if targetAlbumChanged {
                print("SyncCoordinator: Target album updated from server during manual sync")
            }

            // Check photo library authorization
            let authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard authStatus == .authorized || authStatus == .limited else {
                print("SyncCoordinator: Manual sync stopped - Photo library access not authorized (\(authStatus.rawValue))")
                SyncLogger.shared.logManualSync(success: false, message: "Photo access denied")
                completion()
                return
            }

            // Reconcile with server before scanning
            self.reconcileWithServer {
                self.scheduleIncrementalScan {
                    print("SyncCoordinator: Manual sync completed successfully")
                    SyncLogger.shared.logManualSync(success: true, message: "Completed")
                    completion()
                }
            }
        }
    }

    func performBackgroundSync(completion: @escaping () -> Void) {
        let syncStartTime = Date()
        print("SyncCoordinator: Background sync started at \(syncStartTime)")
        SyncLogger.shared.logBackgroundSync(success: true, message: "Started")

        // Check if target album changed on server
        syncTargetAlbumFromServer { targetAlbumChanged in
            // If target album is now null on server, stop sync
            guard self.settings.selectedAlbumName != nil else {
                print("SyncCoordinator: Background sync skipped - no target album selected")
                SyncLogger.shared.logBackgroundSync(success: false, message: "No album selected")
                completion()
                return
            }

            // If target album changed, log it
            if targetAlbumChanged {
                print("SyncCoordinator: Target album updated from server during background sync")
            }

            // Check photo library authorization
            let authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard authStatus == .authorized || authStatus == .limited else {
                print("SyncCoordinator: Background sync stopped - Photo library access not authorized (\(authStatus.rawValue))")
                SyncLogger.shared.logBackgroundSync(success: false, message: "Photo access denied")
                completion()
                return
            }

            // Reconcile with server before scanning
            self.reconcileWithServer {
                self.scheduleIncrementalScan {
                    print("SyncCoordinator: Background sync completed successfully")
                    SyncLogger.shared.logBackgroundSync(success: true, message: "Completed")
                    completion()
                }
            }
        }
    }

    // MARK: - Target Album Synchronization

    private func syncTargetAlbumFromServer(completion: @escaping (Bool) -> Void) {
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
                    if settings.selectedAlbumName != nil {
                        DispatchQueue.main.async {
                            self.settings.selectedAlbumName = nil
                            self.settings.albumId = 1
                            self.clearQueue()
                            print("SyncCoordinator: Target album cleared from server - stopping sync")
                            completion(true)
                        }
                    } else {
                        completion(false)
                    }
                    return
                }

                // Check if target album changed
                if albumId != settings.albumId {
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
                                    print("SyncCoordinator: Target album synced from server: \(album.name)")
                                }
                                completion(true)
                            } else {
                                print("SyncCoordinator: Server target album ID \(albumId) not found in albums list")
                                completion(false)
                            }

                        case let .failure(error):
                            print("SyncCoordinator: Failed to fetch albums: \(error)")
                            completion(false)
                        }
                    }
                } else {
                    // Album ID matches - no change needed
                    completion(false)
                }

            case let .failure(error):
                print("SyncCoordinator: Failed to fetch target album: \(error)")
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

    func reconcileWithServer(completion: (() -> Void)? = nil) {
        syncQueue.async {
            // Fetch checksums from server for last N+1 days
            let days = self.settings.syncLastDays + 1
            self.api.fetchUploadedChecksums(days: days) { result in
                switch result {
                case let .success(checksums):
                    print("SyncCoordinator: Reconciled with server, found \(checksums.count) uploaded checksums")
                    UploadStore.shared.reconcileWithServerChecksums(checksums)
                    completion?()
                case let .failure(error):
                    print("SyncCoordinator: Failed to reconcile with server: \(error)")
                    completion?()
                }
            }
        }
    }

    // MARK: - Scanning

    private func scheduleInitialScan() {
        syncQueue.async {
            let assets = self.photo.fetchAssets(lastDays: self.settings.syncLastDays)
            let filtered = assets.filter { !UploadStore.shared.isUploaded($0.localIdentifier) }
            print("SyncCoordinator: Initial scan found \(assets.count) assets in last \(self.settings.syncLastDays) days, \(filtered.count) not yet uploaded")

            DispatchQueue.main.async {
                self.metrics.inScope = assets.count
            }

            self.enqueue(assets: filtered)
        }
    }

    private func scheduleIncrementalScan(onDone: (() -> Void)? = nil) {
        syncQueue.async {
            // Calculate cutoff date based on syncLastDays
            let calendar = Calendar.current
            let now = Date()
            let cutoffDate = calendar.date(byAdding: .day, value: -self.settings.syncLastDays, to: now) ?? .distantPast

            // Update in-scope count with all photos in the date range
            let allInScope = self.photo.fetchAssets(lastDays: self.settings.syncLastDays)
            DispatchQueue.main.async {
                self.metrics.inScope = allInScope.count
            }

            // Use the more recent of lastSyncDate or cutoffDate
            let since = max(self.settings.lastSyncDate ?? .distantPast, cutoffDate)
            let assets = self.photo.fetchAssets(since: since)
            let filtered = assets.filter { !UploadStore.shared.isUploaded($0.localIdentifier) }
            print("SyncCoordinator: Incremental scan found \(assets.count) assets since \(since), \(filtered.count) not yet uploaded")
            self.enqueue(assets: filtered)
            onDone?()
        }
    }

    private func enqueue(assets: [PHAsset]) {
        guard !assets.isEmpty else { return }

        // Filter out assets that are already pending or currently uploading
        let newAssets = assets.filter { asset in
            let isAlreadyQueued = pendingAssets.contains(where: { $0.localIdentifier == asset.localIdentifier })
            let isCurrentlyUploading = uploadingAssets.contains(asset.localIdentifier)
            return !isAlreadyQueued && !isCurrentlyUploading
        }

        guard !newAssets.isEmpty else {
            print("SyncCoordinator: All \(assets.count) assets already queued or uploading, skipping")
            return
        }

        print("SyncCoordinator: Enqueuing \(newAssets.count) new assets (filtered from \(assets.count))")
        pendingAssets.append(contentsOf: newAssets)
        DispatchQueue.main.async {
            self.metrics.queued = self.pendingAssets.count
        }
        drainQueue()
    }

    private func drainQueue() {
        // Only launch enough uploads to fill the concurrency cap. New uploads
        // are handed off one-per-completion (see handleUploadFinished) so the
        // server never sees more than maxInFlightUploads at once.
        let slotsFree = max(0, maxInFlightUploads - uploadingAssets.count)
        guard slotsFree > 0 else { return }

        let batch = Array(pendingAssets.prefix(slotsFree))
        guard !batch.isEmpty else { return }

        pendingAssets.removeFirst(batch.count)
        for asset in batch {
            uploadingAssets.insert(asset.localIdentifier)
            inFlightAssets[asset.localIdentifier] = asset
        }

        DispatchQueue.main.async {
            self.metrics.queued = self.pendingAssets.count
            self.metrics.uploading += batch.count
        }

        // Phase 5 — pick the upload path once per batch. Both flags must be true: server
        // advertises tus.enabled in /api/capabilities AND user opted in via Settings.useTus.
        // Decision is made per-batch (not per-asset) so a mid-batch capability flip can't
        // produce a half-multipart-half-TUS batch with race-prone state.
        let useTus = shouldUseTus()
        for asset in batch {
            let completion: ((Result<Void, Error>) -> Void) = { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    // Handoff succeeded; actual upload completion comes through
                    // {Uploader,TusUploader}.onTaskFinished -> handleUploadFinished.
                    break
                case .failure:
                    // Export / body-write failed — free the slot and try a replacement.
                    self.syncQueue.async {
                        self.uploadingAssets.remove(asset.localIdentifier)
                        self.inFlightAssets.removeValue(forKey: asset.localIdentifier)
                        DispatchQueue.main.async {
                            self.metrics.uploading = max(0, self.metrics.uploading - 1)
                        }
                        self.syncQueue.asyncAfter(deadline: .now() + 10) {
                            self.pendingAssets.append(asset)
                            DispatchQueue.main.async { self.metrics.queued = self.pendingAssets.count }
                            self.drainQueue()
                        }
                    }
                }
            }
            if useTus {
                tusUploader.queueUpload(asset: asset, api: api, completion: completion)
            } else {
                uploader.queueUpload(asset: asset, api: api, completion: completion)
            }
        }
    }

    // MARK: - Phase 5 — Capabilities cache + path selection

    /// Returns true iff the user has opted in (Settings.useTus) AND the server advertises
    /// tus.enabled (cached /api/capabilities). When capabilities haven't loaded yet — the
    /// first drainQueue after a fresh launch — this returns false, and the batch goes via
    /// the multipart path. The next refresh after ensureCapabilitiesLoaded completes flips
    /// the answer; subsequent batches use TUS.
    private func shouldUseTus() -> Bool {
        guard Settings.shared.useTus else { return false }
        guard let caps = cachedCapabilities else { return false }
        return caps.tus.enabled
    }

    /// Lazy fetch + 1-hour cache. Called from start() and refreshed implicitly here when the
    /// cache has expired. Failure is non-fatal — we just leave the cache empty and fall back
    /// to the multipart path until the next attempt.
    private func ensureCapabilitiesLoaded(completion: ((Capabilities?) -> Void)? = nil) {
        if let fetchedAt = capabilitiesFetchedAt,
           Date().timeIntervalSince(fetchedAt) < capabilitiesTTL,
           let cached = cachedCapabilities {
            completion?(cached)
            return
        }
        api.fetchCapabilities { [weak self] result in
            guard let self else { completion?(nil); return }
            switch result {
            case let .success(caps):
                self.cachedCapabilities = caps
                self.capabilitiesFetchedAt = Date()
                completion?(caps)
            case let .failure(err):
                print("SyncCoordinator: capabilities fetch failed: \(err) — staying on multipart path")
                completion?(nil)
            }
        }
    }

    private func handleUploadFinished(assetId: String, outcome: Uploader.UploadOutcome) {
        syncQueue.async {
            let asset = self.inFlightAssets.removeValue(forKey: assetId)
            self.uploadingAssets.remove(assetId)

            DispatchQueue.main.async {
                self.metrics.uploading = max(0, self.metrics.uploading - 1)
                self.metrics.lastSync = Date()
                self.settings.lastSyncDate = self.metrics.lastSync
            }

            switch outcome {
            case let .success(serverAssetId):
                // Bytes landed; the worker pod still has thumbnail/transcode
                // work to do. Poll /api/assets/{id}/status so we surface
                // post-upload pipeline failures (FAILED / DEAD_LETTER) instead
                // of silently treating "2xx" as the end of the story.
                if let serverAssetId {
                    ProcessingStatusPoller.shared.poll(serverAssetId: serverAssetId, contentId: assetId, api: self.api)
                }
                self.drainQueue()
            case .clientError, .transport:
                // clientError: permanent failure; transport: system-retried.
                self.drainQueue()
            case let .backpressure(retryAfter):
                // Server asked us to back off. Re-enqueue this asset and pause
                // draining for retryAfter seconds so we don't hammer the server.
                if let asset {
                    print("SyncCoordinator: 503/429 on \(assetId), re-queueing after \(Int(retryAfter))s")
                    self.pendingAssets.insert(asset, at: 0)
                    DispatchQueue.main.async { self.metrics.queued = self.pendingAssets.count }
                }
                self.syncQueue.asyncAfter(deadline: .now() + retryAfter) {
                    self.drainQueue()
                }
            }
        }
    }
}
