import SwiftUI
import UserNotifications
import os

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var sync: SyncCoordinator
    /// Whether the account's storage on the site is full — drives the banner below.
    @ObservedObject private var storageUsage = StorageUsageMonitor.shared
    @State private var isLoggedIn: Bool = false

    var body: some View {
        Group {
            if isLoggedIn {
                VStack(spacing: 0) {
                    // Not dismissable, not remembered: up exactly while uploads are refused.
                    if storageUsage.isFull {
                        StorageFullBanner(usage: storageUsage.usage)
                    }
                    MainTabView(isLoggedIn: $isLoggedIn)
                }
            } else {
                NavigationStack {
                    WelcomeView(isLoggedIn: $isLoggedIn)
                }
            }
        }
        .onAppear {
            checkLoginStatus()
            clearBadge()
            if isLoggedIn {
                storageUsage.start()
            }
        }
        .onChange(of: isLoggedIn) { _, loggedIn in
            // The banner follows the session: a fresh sign-in asks straight away, a sign-out
            // takes it down rather than carrying one account's warning over to the next.
            if loggedIn {
                storageUsage.start()
            } else {
                storageUsage.stop()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                clearBadge()
                if isLoggedIn {
                    // Trigger sync when app becomes active
                    sync.start()
                    // Space may have been freed from the web app, or the quota raised, while
                    // the phone was in a pocket.
                    storageUsage.refresh()
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
            try? await UNUserNotificationCenter.current().setBadgeCount(0)

            // Remove all delivered notifications from notification center
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()

            // Also remove all pending notifications
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

            AppLog.app.debug("Cleared the badge, delivered notifications and pending requests")
        }
    }
}
