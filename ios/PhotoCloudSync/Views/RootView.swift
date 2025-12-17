import SwiftUI
import UserNotifications

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var sync: SyncCoordinator
    @State private var isLoggedIn: Bool = false

    var body: some View {
        Group {
            if isLoggedIn {
                MainTabView(isLoggedIn: $isLoggedIn)
            } else {
                LoginView(isLoggedIn: $isLoggedIn)
            }
        }
        .onAppear {
            checkLoginStatus()
            clearBadge()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                clearBadge()
                if isLoggedIn {
                    // Trigger sync when app becomes active
                    sync.start()
                }
            }
        }
    }

    private func checkLoginStatus() {
        let credentials = KeychainHelper.shared.load()
        isLoggedIn = credentials != nil
    }

    private func clearBadge() {
        Task { @MainActor in
            // Clear the badge number
            UIApplication.shared.applicationIconBadgeNumber = 0

            // Remove all delivered notifications from notification center
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()

            // Also remove all pending notifications
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

            print("RootView: Cleared badge, delivered notifications, and pending requests")
        }
    }
}
