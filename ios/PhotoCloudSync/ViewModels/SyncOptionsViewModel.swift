import Combine
import Foundation
import Photos

@MainActor
class SyncOptionsViewModel: ViewModelProtocol {
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?
    @Published var authStatus: PHAuthorizationStatus = .notDetermined
    @Published var albums: [Album] = []
    @Published var selectedAlbum: Album?
    @Published var isLoadingAlbums: Bool = false

    private let syncCoordinator: SyncCoordinator
    private var apiClient: APIClient?

    init(syncCoordinator: SyncCoordinator = .shared) {
        self.syncCoordinator = syncCoordinator
        loadCredentials()
        checkPhotoAccess()
    }

    private func loadCredentials() {
        if let credentials = KeychainHelper.shared.load() {
            apiClient = APIClient(
                username: credentials.username,
                password: credentials.password,
            )
        }
    }

    private func checkPhotoAccess() {
        authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestPhotoAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.authStatus = status
            }
        }
    }

    func fetchAlbums() {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            return
        }

        isLoadingAlbums = true

        // Fetch target album from server first
        apiClient.getTargetAlbum { [weak self] targetResult in
            guard let self else { return }

            // Then fetch albums list
            apiClient.fetchAlbums { [weak self] albumsResult in
                guard let self else { return }

                DispatchQueue.main.async {
                    self.isLoadingAlbums = false

                    switch albumsResult {
                    case let .success(fetchedAlbums):
                        self.albums = fetchedAlbums

                        // If server has a target album set, use that (priority)
                        if case let .success(targetAlbumId) = targetResult, let targetId = targetAlbumId {
                            self.selectedAlbum = fetchedAlbums.first { $0.id == targetId }
                            if let album = self.selectedAlbum {
                                self.syncCoordinator.settings.albumId = album.id
                                self.syncCoordinator.settings.selectedAlbumName = album.name
                            }
                        }
                        // Otherwise restore from local settings
                        else if let savedAlbumName = self.syncCoordinator.settings.selectedAlbumName {
                            self.selectedAlbum = fetchedAlbums.first { $0.name == savedAlbumName }
                        }

                    case let .failure(error):
                        self.handleError(error)
                    }
                }
            }
        }
    }

    func selectAlbum(_ album: Album) {
        guard let apiClient else { return }

        selectedAlbum = album
        syncCoordinator.settings.albumId = album.id
        syncCoordinator.settings.selectedAlbumName = album.name

        // Update target album on server
        apiClient.setTargetAlbum(albumId: album.id) { [weak self] result in
            guard let self else { return }

            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("SyncOptionsViewModel: Target album updated on server: \(album.id)")
                    // Start syncing now that an album has been selected and saved
                    self.syncCoordinator.start()

                case let .failure(error):
                    print("SyncOptionsViewModel: Failed to update target album on server: \(error)")
                    // Show error but still start syncing with local setting
                    self.alertState = AlertState(
                        title: "Warning",
                        message: "Album selected locally, but failed to sync with server. Changes may not persist across devices.",
                    )
                    self.syncCoordinator.start()
                }
            }
        }
    }

    func syncNow() {
        guard selectedAlbum != nil else {
            alertState = AlertState(
                title: "No Album Selected",
                message: "Please select a target album before syncing.",
            )
            return
        }

        // Trigger manual sync which will check for new images and upload them
        syncCoordinator.performManualSync {
            // Sync completed - the logging is handled inside performManualSync
        }

        alertState = AlertState(
            title: "Sync Started",
            message: "Checking for new photos and starting sync...",
        )
    }

    func clearLocalCache() {
        alertState = .confirmation(
            title: "Clear Local Cache",
            message: "This will clear all uploaded photo records, allowing you to re-upload photos. Your login credentials and album selection will be preserved.",
            confirmTitle: "Clear Cache",
            confirmAction: {
                // Save current album selection
                let savedAlbumId = self.syncCoordinator.settings.albumId
                let savedAlbumName = self.syncCoordinator.settings.selectedAlbumName
                let savedWifiOnly = self.syncCoordinator.settings.wifiOnly
                let savedSyncLastDays = self.syncCoordinator.settings.syncLastDays

                // Clear all synced images data
                UploadStore.shared.clear()

                // Clear sync queue and reset metrics
                self.syncCoordinator.clearQueue()
                self.syncCoordinator.metrics = SyncCoordinator.Metrics()

                // Reset only lastSyncDate to force a full re-scan
                self.syncCoordinator.settings.lastSyncDate = nil

                // Restore album selection and other settings
                self.syncCoordinator.settings.albumId = savedAlbumId
                self.syncCoordinator.settings.selectedAlbumName = savedAlbumName
                self.syncCoordinator.settings.wifiOnly = savedWifiOnly
                self.syncCoordinator.settings.syncLastDays = savedSyncLastDays

                // Show success message and trigger sync
                self.alertState = .success(
                    title: "Cache Cleared",
                    message: "Local cache has been cleared. Starting re-sync now...",
                )

                // Trigger a new sync to re-upload photos
                if savedAlbumName != nil {
                    self.syncCoordinator.start()
                }
            },
        )
    }

    func logout(completion: @escaping () -> Void) {
        alertState = .confirmation(
            title: "Logout",
            message: "Are you sure you want to logout? This will clear all sync data.",
            confirmTitle: "Logout",
            confirmAction: {
                // Clear keychain credentials
                KeychainHelper.shared.delete()

                // Clear all synced images data
                UploadStore.shared.clear()

                // Clear all settings
                self.syncCoordinator.settings.clear()

                // Clear sync queue and reset metrics
                self.syncCoordinator.clearQueue()
                self.syncCoordinator.metrics = SyncCoordinator.Metrics()

                completion()
            },
        )
    }

    var photoAccessStatusText: String {
        switch authStatus {
        case .authorized: return "Authorized"
        case .limited: return "Limited"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not determined"
        @unknown default: return "Unknown"
        }
    }

    var photoAccessColor: String {
        switch authStatus {
        case .authorized, .limited:
            return "green"
        case .denied, .restricted:
            return "red"
        case .notDetermined:
            return "orange"
        @unknown default:
            return "gray"
        }
    }

    var canRequestAccess: Bool {
        authStatus != .authorized && authStatus != .limited
    }
}
