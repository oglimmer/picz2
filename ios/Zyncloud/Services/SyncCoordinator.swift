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
    /// Cached rather than rebuilt per access (§5.10).
    ///
    /// This was a computed property doing a `KeychainHelper.load()` — a synchronous IPC to
    /// securityd — on every read, and the upload path reads it several times per asset for a
    /// value that changes twice in a whole session. `credentialsDidChange` is what makes the
    /// cache safe: sign-in, sign-out and the legacy-format migration all drop it.
    private var cachedApi: APIClient?
    private let apiLock = NSLock()
    private var api: APIClient {
        apiLock.lock()
        defer { apiLock.unlock() }
        if let cachedApi { return cachedApi }
        let credentials = KeychainHelper.shared.load()
        let client = APIClient(
            username: credentials?.username,
            password: credentials?.password,
        )
        cachedApi = client
        return client
    }

    private func invalidateCachedApi() {
        apiLock.lock()
        cachedApi = nil
        apiLock.unlock()
    }

    struct Metrics {
        var queued: Int = 0
        var uploading: Int = 0
        var uploaded: Int = 0
        var inScope: Int = 0
        var lastSync: Date?
        /// Assets held back because they exceed the server's cap. Shown on the Sync tab: a
        /// backup with a silent hole in it is worse than one that says which files are missing.
        var skippedTooLarge: Int = 0
    }

    private var credentialsObserver: NSObjectProtocol?

    private var syncQueue = DispatchQueue(label: "com.oglimmer.photosync.sync", qos: .utility)
    private var pendingAssets: [PHAsset] = []
    private var uploadingAssets: Set<String> = [] // Track assets currently being uploaded
    private var inFlightAssets: [String: PHAsset] = [:] // localId -> PHAsset, kept for 503 re-queue

    // An asset whose original cannot be produced at all (iCloud copy unavailable, corrupt
    // resource) used to be re-appended every 10 s for as long as the app ran, burning the
    // queue slot forever. The give-up rule lives in ExportRetryPolicy so it can be tested
    // without standing up a coordinator. Touched only on syncQueue.
    private var exportRetryPolicy = ExportRetryPolicy()
    private let maxInFlightUploads = 3

    private init() {
        // Drop the cached APIClient whenever the stored credentials change, so a sign-out
        // cannot leave an authenticated client behind and a sign-in is picked up immediately.
        credentialsObserver = NotificationCenter.default.addObserver(
            forName: KeychainHelper.credentialsDidChange, object: nil, queue: nil,
        ) { [weak self] _ in
            self?.invalidateCachedApi()
        }

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
                    self.resolveTusUploadServerId(contentId: assetId) { [weak self] resolved in
                        self?.handleUploadFinished(
                            assetId: assetId,
                            outcome: .success(serverAssetId: resolved),
                        )
                    }
                }
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
                    guard self.settings.selectedAlbumName != nil else { return }

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
    private func activeUploadTaskAssetIds(completion: @escaping (Set<String>) -> Void) {
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
            self.pendingAssets.removeAll()
            self.uploadingAssets.removeAll()
            self.inFlightAssets.removeAll()
            self.exportRetryPolicy.reset()
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
    func reconcileWithServer(completion: (() -> Void)? = nil) {
        syncQueue.async {
            // N+1 days: the scan window plus a day of slack, so an asset taken just before the
            // boundary is not re-uploaded because the two windows disagree about "today".
            let days = self.settings.syncLastDays + 1
            self.api.fetchUploadedContentIds(days: days) { contentIdResult in
                switch contentIdResult {
                case let .success(contentIds):
                    print("SyncCoordinator: Reconciled with server, found \(contentIds.count) uploaded contentIds")
                    UploadStore.shared.reconcileWithServerContentIds(contentIds)
                case let .failure(error):
                    // An older server has no such endpoint; the checksum pass below still runs.
                    print("SyncCoordinator: contentId reconciliation unavailable: \(error)")
                }

                self.api.fetchUploadedChecksums(days: days) { checksumResult in
                    switch checksumResult {
                    case let .success(checksums):
                        print("SyncCoordinator: Reconciled with server, found \(checksums.count) uploaded checksums")
                        UploadStore.shared.reconcileWithServerChecksums(checksums)
                    case let .failure(error):
                        print("SyncCoordinator: Failed to reconcile with server: \(error)")
                    }
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

        // Filter out assets that are already pending or currently uploading, plus any the
        // server has already refused for size under a cap that has not since been raised —
        // re-exporting a 1.6 GB video on every scan to earn the same 413 helps nobody.
        let sizeLimit = currentUploadSizeLimit()
        let newAssets = assets.filter { asset in
            let isAlreadyQueued = pendingAssets.contains(where: { $0.localIdentifier == asset.localIdentifier })
            let isCurrentlyUploading = uploadingAssets.contains(asset.localIdentifier)
            let isTooLarge = UploadStore.shared.shouldSkipForSize(asset.localIdentifier, currentLimit: sizeLimit)
            return !isAlreadyQueued && !isCurrentlyUploading && !isTooLarge
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
        let uploadSizeLimit = currentUploadSizeLimit()
        for asset in batch {
            let completion: ((Result<Void, Error>) -> Void) = { [weak self] result in
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
                        self.uploadingAssets.remove(id)
                        self.inFlightAssets.removeValue(forKey: id)
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
                            self.drainQueue()
                            return
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
                tusUploader.queueUpload(asset: asset, api: api,
                                        maxUploadBytes: uploadSizeLimit, completion: completion)
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
    /// The cap to judge file sizes against: the live capabilities response when we have one,
    /// otherwise the last one we persisted, otherwise nil for "unknown, let the server decide".
    private func currentUploadSizeLimit() -> Int64? {
        if let advertised = cachedCapabilities?.tus.maxSize, advertised > 0 { return advertised }
        let remembered = Settings.shared.tusMaxUploadBytes
        return remembered > 0 ? remembered : nil
    }

    private func refreshSkippedTooLargeMetric() {
        let limit = currentUploadSizeLimit()
        let count = UploadStore.shared.skippedTooLargeCount(currentLimit: limit)
        DispatchQueue.main.async { self.metrics.skippedTooLarge = count }
    }

    private func shouldUseTus() -> Bool {
        UploadRouting.selectPath(
            userOptedIn: Settings.shared.useTus,
            capabilities: cachedCapabilities
        ) == .tus
    }

    /// Resolve the server-side asset id for a TUS upload, given the client's contentId
    /// (PHAsset.localIdentifier). Retries up to 4 times with backoff to ride out the
    /// post-finish hook race window (~200 ms typical; 1 s worst case observed in production
    /// — see Phase 5b bug-fix #4 in the plan). Calls completion with the resolved id, or
    /// nil if the row never appears (deleted? hook crashed?). nil disables status polling
    /// for that asset; the upload itself is still recorded as success.
    private func resolveTusUploadServerId(
        contentId: String,
        attempt: Int = 0,
        completion: @escaping (Int?) -> Void,
    ) {
        let maxAttempts = 4
        let albumId = settings.albumId
        api.lookupAssetByContentId(albumId: albumId, contentId: contentId) { [weak self] result in
            switch result {
            case let .success(id):
                completion(id)
            case .failure where attempt < maxAttempts - 1:
                // 200ms, 400ms, 800ms — covers the typical race + a comfortable safety margin.
                let delay = 0.2 * pow(2.0, Double(attempt))
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self?.resolveTusUploadServerId(
                        contentId: contentId,
                        attempt: attempt + 1,
                        completion: completion,
                    )
                }
            case .failure:
                print("SyncCoordinator: gave up resolving asset id for contentId=\(contentId) after \(maxAttempts) attempts; status polling disabled for this upload")
                SyncLogger.shared.logProcessingStatusUnavailable(assetId: contentId)
                completion(nil)
            }
        }
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
                // Persist the cap so the next cold-launch scan can filter known-too-big assets
                // before exporting them, and so a raised cap un-skips what it now admits.
                DispatchQueue.main.async {
                    Settings.shared.tusMaxUploadBytes = caps.tus.maxSize
                    self.refreshSkippedTooLargeMetric()
                }
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
                self.refreshSkippedTooLargeMetric()
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
