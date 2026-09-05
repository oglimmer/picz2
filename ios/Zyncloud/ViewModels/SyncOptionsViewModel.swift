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
    /// Whether this account may change instance-wide settings — today, the two narration language
    /// names (server D75). Read from `/api/auth/check` on appearance; false until it answers, so
    /// the row appears rather than disappears, and never for a plain account.
    @Published var isAdmin: Bool = false

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

    /// Refreshes `isAdmin`. Silent on failure: this only decides whether an operator row is shown,
    /// and a transient error should not put up an alert on a screen that is otherwise fine.
    func loadAccountRole() {
        guard let apiClient else { return }

        apiClient.checkAuth { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if case let .success(response) = result {
                    self.isAdmin = response.isAdmin
                }
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

                        switch targetResult {
                        // The server has a target album — it wins over the local setting.
                        case let .success(.some(targetId)):
                            self.selectedAlbum = fetchedAlbums.first { $0.id == targetId }
                            if let album = self.selectedAlbum {
                                self.syncCoordinator.settings.albumId = album.id
                                self.syncCoordinator.settings.selectedAlbumName = album.name
                            }

                        // The server answered "no target album" — uploads are paused, from here
                        // or from the web app. Clear the local selection so the picker shows
                        // "Paused" instead of falling back to the last album: that fallback used
                        // to fire the picker's `onChange`, which re-PUT the album and silently
                        // resumed a sync the user had just paused in the web UI.
                        case .success(.none):
                            self.selectedAlbum = nil
                            self.syncCoordinator.settings.selectedAlbumName = nil

                        // Only a failed target-album call falls back to what this device knows.
                        case .failure:
                            if let savedAlbumName = self.syncCoordinator.settings.selectedAlbumName {
                                self.selectedAlbum = fetchedAlbums.first { $0.name == savedAlbumName }
                            }
                        }

                    case let .failure(error):
                        self.handleError(error)
                    }
                }
            }
        }
    }

    /// The one entry point the picker writes to: an album resumes uploads into it, `nil` is the
    /// "Paused" row.
    ///
    /// The picker is bound through an explicit `Binding` whose setter is this method, so it runs
    /// only on a real tap. Binding `$viewModel.selectedAlbum` with an `onChange` instead made
    /// every programmatic assignment — the one `fetchAlbums` does, the one ``pauseUploads()``
    /// does — look like a user choice and fire a second server write.
    func chooseAlbum(_ album: Album?) {
        if let album {
            selectAlbum(album)
        } else {
            pauseUploads()
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

    /// Pause phone uploads, the same way the web app's "Pause uploads" does.
    ///
    /// Server first: the cleared target album is the shared switch, so a local-only pause would
    /// be undone by the next ``SyncCoordinator/syncTargetAlbumFromServer``. Only once the server
    /// has accepted it are the local selection and the pending queue dropped.
    func pauseUploads() {
        guard let apiClient else { return }

        let previousAlbum = selectedAlbum
        selectedAlbum = nil

        apiClient.clearTargetAlbum { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                switch result {
                case .success:
                    AppLog.sync.info("Phone uploads paused — target album cleared on the server")
                    self.syncCoordinator.settings.selectedAlbumName = nil
                    self.syncCoordinator.clearQueue()

                case let .failure(error):
                    AppLog.sync.error("Could not pause uploads: \(error.localizedDescription, privacy: .public)")
                    // The server still holds the old album, so put the picker back on it rather
                    // than showing a pause that is not in effect.
                    self.selectedAlbum = previousAlbum
                    self.alertState = AlertState(
                        title: "Could Not Pause",
                        message: "Uploads are still running. Please try again.",
                    )
                }
            }
        }
    }

    /// The device switch. Everything it does lives on ``SyncCoordinator/setSyncEnabled(_:)`` —
    /// this only forwards, so the toggle and any other caller cannot drift apart.
    var syncEnabled: Bool { syncCoordinator.settings.syncEnabled }

    func setSyncEnabled(_ enabled: Bool) {
        syncCoordinator.setSyncEnabled(enabled)
    }

    func syncNow() {
        guard selectedAlbum != nil else {
            alertState = AlertState(
                title: "No Album Selected",
                message: "Please select a target album before syncing.",
            )
            return
        }

        // Without this the run would start, hit the switch inside `performSync` and stop, while
        // the alert below said "Checking for new photos" — a sync that reports itself started
        // and does nothing is worse than one that says why it will not.
        guard syncEnabled else {
            alertState = AlertState(
                title: "Syncing Is Off",
                message: "Syncing is turned off for this phone. Turn it on under Sync Settings first.",
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
