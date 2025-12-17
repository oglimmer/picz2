import BackgroundTasks
import SwiftUI

@main
struct PhotoCloudSyncApp: App {
    // Bridge to AppDelegate for BackgroundTasks and background URLSession events
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Register background tasks before app finishes launching (required by Apple)
        AppDelegate.registerBackgroundTasksEarly()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(SyncCoordinator.shared)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Clear badge when app becomes active
                Task { @MainActor in
                    UIApplication.shared.applicationIconBadgeNumber = 0
                    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                    print("PhotoCloudSyncApp: Cleared badge and delivered notifications (scenePhase)")
                }
            }
        }
    }
}
