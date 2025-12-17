import Foundation
import Photos

final class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()

    @Published var metrics = Metrics()
    @Published var settings = Settings.shared

    private let photo = PhotoLibraryManager.shared
    private let uploader = Uploader.shared
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

    private init() {}

    // MARK: - Public controls

    func start() {
        uploader.configureSession()

        // Clean up stale uploading entries from previous app sessions
        // But preserve entries that have active URLSession tasks (to prevent duplicate uploads)
        let activeTasks = uploader.getActiveUploadAssetIds()
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

    func clearQueue() {
        syncQueue.async {
            self.pendingAssets.removeAll()
            self.uploadingAssets.removeAll()
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
                    // Server has no target album - clear local selection
                    if settings.selectedAlbumName != nil {
                        DispatchQueue.main.async {
                            self.settings.selectedAlbumName = nil
                            self.settings.albumId = 1
                            self.clearQueue()
                            print("SyncCoordinator: Target album cleared from server - stopping sync")
                        }
                        completion(true)
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
        // Push a small batch to the uploader to avoid memory pressure
        let batchSize = 3
        let batch = Array(pendingAssets.prefix(batchSize))
        guard !batch.isEmpty else { return }

        // Remove from pending and mark as uploading
        pendingAssets.removeFirst(min(batchSize, pendingAssets.count))
        for asset in batch {
            uploadingAssets.insert(asset.localIdentifier)
        }

        DispatchQueue.main.async {
            self.metrics.queued = self.pendingAssets.count
            self.metrics.uploading += batch.count
        }

        for asset in batch {
            uploader.queueUpload(asset: asset, api: api) { result in
                // Remove from uploading set
                self.syncQueue.async {
                    self.uploadingAssets.remove(asset.localIdentifier)
                }

                DispatchQueue.main.async {
                    self.metrics.uploading = max(0, self.metrics.uploading - 1)
                    self.metrics.lastSync = Date()
                    self.settings.lastSyncDate = self.metrics.lastSync
                }

                switch result {
                case .success:
                    break
                case .failure:
                    // Re-enqueue on failure (light retry). In production, use retry with backoff.
                    self.syncQueue.asyncAfter(deadline: .now() + 10) {
                        self.pendingAssets.append(asset)
                        DispatchQueue.main.async { self.metrics.queued = self.pendingAssets.count }
                        self.drainQueue()
                    }
                }
            }
        }

        // Continue draining if more remain
        syncQueue.async {
            self.drainQueue()
        }
    }
}
