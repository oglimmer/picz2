import Combine
import Foundation
import os
import Photos

@MainActor
class SyncOptionsViewModel: ViewModelProtocol {
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?
    @Published var authStatus: PHAuthorizationStatus = .notDetermined
    @Published var albums: [Album] = []
    @Published var selectedAlbum: Album?
    @Published var isLoadingAlbums: Bool = false
    @Published var isDeletingAccount: Bool = false

    private let syncCoordinator: SyncCoordinator
    private let apiClient: APIClient?

    init(syncCoordinator: SyncCoordinator = .shared,
         apiClient: APIClient? = APIClientProvider.shared.current)
    {
        self.syncCoordinator = syncCoordinator
        self.apiClient = apiClient
        checkPhotoAccess()
    }

    /// Re-read the live status. Called from `init` and again whenever the options screen
    /// appears or the app returns to the foreground: the user can change this in iOS Settings
    /// without the app running, and a status read once at init goes stale the moment they do.
    func checkPhotoAccess() {
        authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestPhotoAccess() {
        // `@Sendable` for the reason spelled out in ``AlbumDetailViewModel/requestUpload()``:
        // Photos answers on a background queue and its block is not `Sendable`.
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { @Sendable [weak self] status in
            Task { @MainActor in
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

                Task { @MainActor in
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

            Task { @MainActor in
                switch result {
                case .success:
                    AppLog.sync.info("Target album updated on the server: \(album.id, privacy: .public)")
                    // Start syncing now that an album has been selected and saved
                    self.syncCoordinator.start()

                case let .failure(error):
                    AppLog.sync.error("Could not update the target album: \(error.localizedDescription, privacy: .public)")
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

    func logout(completion: @escaping @Sendable @MainActor () -> Void) {
        alertState = .confirmation(
            title: "Logout",
            message: "Are you sure you want to logout? This will clear all sync data.",
            confirmTitle: "Logout",
            confirmAction: {
                // Clear keychain credentials. Via CredentialsManager so the share
                // extension is signed out too — it used to keep its own item.
                CredentialsManager.clear()

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

    /// Delete the account on the server, then tear down every local trace of it.
    ///
    /// The teardown is deliberately identical to ``logout(completion:)`` — credentials, upload
    /// store, settings, queue and metrics — because leaving any of it behind after the account is
    /// gone would let the next screen try to sync against a user the server no longer knows.
    /// The local wipe only runs on a confirmed server-side delete; a failed request leaves the
    /// signed-in session intact so the user can retry.
    func deleteAccount(completion: @escaping @Sendable @MainActor () -> Void) {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            return
        }

        isDeletingAccount = true

        apiClient.deleteAccount { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isDeletingAccount = false

                switch result {
                case .success:
                    // Via CredentialsManager so the share extension is signed out too.
                    CredentialsManager.clear()
                    UploadStore.shared.clear()
                    self.syncCoordinator.settings.clear()
                    self.syncCoordinator.clearQueue()
                    self.syncCoordinator.metrics = SyncCoordinator.Metrics()
                    completion()

                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
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
        case .authorized:
            return "green"
        // Not green. `.limited` means Photos hands us only the assets the user hand-picked,
        // so a background sync quietly skips the rest of the library and looks like it worked.
        case .limited, .notDetermined:
            return "orange"
        case .denied, .restricted:
            return "red"
        @unknown default:
            return "gray"
        }
    }

    /// The whole Permissions section is hidden once access is *full*. Anything else is a state
    /// the user has to act on, including `.limited` — see ``photoAccessColor``.
    var showsPermissionsSection: Bool {
        authStatus != .authorized
    }

    /// What the current state costs the user, in their words. `nil` when the section is hidden.
    var photoAccessHint: String? {
        switch authStatus {
        case .authorized: nil
        case .limited: "Only the photos you picked can sync. Everything else is skipped."
        case .denied: "Picz cannot see your photos, so nothing will sync."
        case .restricted: "Photo access is blocked on this device, so nothing will sync."
        case .notDetermined: "Picz needs access to your photos before it can sync."
        @unknown default: nil
        }
    }

    /// Only `.notDetermined` can still be answered by the system prompt. For every other
    /// non-authorized state `requestAuthorization` returns the same answer without showing
    /// anything — the old button was a no-op for denied users. Those get ``canOpenSettings``.
    var canRequestAccess: Bool {
        authStatus == .notDetermined
    }
}
