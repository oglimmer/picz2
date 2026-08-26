import BackgroundTasks
import SwiftUI
import UserNotifications
import os

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
                    AppLog.app.debug("Cleared the badge and delivered notifications on scene phase change")
                }

            case .background:
                // The app is scene-based, so UIApplicationDelegate's
                // applicationDidEnterBackground is never called. Without this, background
                // tasks would only ever be scheduled at launch and from inside a running
                // task handler — one missed handler and scheduling stops until a cold launch.
                AppDelegate.scheduleBackgroundTasks()

                // UploadStore and SyncLogger both coalesce their writes (§5.7), so up to a
                // second of bookkeeping can still be in memory here. Backgrounding is the last
                // moment we are reliably given before the app may be killed outright, so force
                // both to disk now.
                UploadStore.shared.flushPendingWrites()
                SyncLogger.shared.flushPendingWrites()

            default:
                break
            }
        }
    }
}
