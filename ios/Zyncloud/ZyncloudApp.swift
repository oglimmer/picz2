import BackgroundTasks
import SwiftUI
import UserNotifications

@main
struct ZyncloudApp: App {
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
            switch newPhase {
            case .active:
                // Clear badge when app becomes active
                Task { @MainActor in
                    try? await UNUserNotificationCenter.current().setBadgeCount(0)
                    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                    print("ZyncloudApp: Cleared badge and delivered notifications (scenePhase)")
                }

            case .background:
                // The app is scene-based, so UIApplicationDelegate's
                // applicationDidEnterBackground is never called. Without this, background
                // tasks would only ever be scheduled at launch and from inside a running
                // task handler — one missed handler and scheduling stops until a cold launch.
                AppDelegate.scheduleBackgroundTasks()

            default:
                break
            }
        }
    }
}
