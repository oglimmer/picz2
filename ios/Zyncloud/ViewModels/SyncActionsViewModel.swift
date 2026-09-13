import Combine
import Foundation

/// The two one-shot sync commands at the top of the Status tab: run a sync now, and forget what
/// this phone has uploaded so everything in scope goes up again.
///
/// They used to sit at the bottom of the Options tab. They are commands, not settings, so they
/// moved next to the readouts that show whether they did anything.
@MainActor
class SyncActionsViewModel: ViewModelProtocol {
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?

    private let syncCoordinator: SyncCoordinator

    init(syncCoordinator: SyncCoordinator = .shared) {
        self.syncCoordinator = syncCoordinator
    }

    func syncNow() {
        // The local setting, not a picker value: this tab never loads the album list. It is the
        // same check `performSync` makes, and the same field a pause from here or the web clears.
        guard syncCoordinator.settings.selectedAlbumName != nil else {
            alertState = AlertState(
                title: "No Album Selected",
                message: "Please select a target album in Options before syncing.",
            )
            return
        }

        // Without this the run would start, hit the switch inside `performSync` and stop, while
        // the alert below said "Checking for new photos" — a sync that reports itself started
        // and does nothing is worse than one that says why it will not.
        guard syncCoordinator.settings.syncEnabled else {
            alertState = AlertState(
                title: "Syncing Is Off",
                message: "Syncing is turned off for this phone. Turn it on in Options under Sync Settings first.",
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
}
