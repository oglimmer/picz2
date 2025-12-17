import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @StateObject private var pushManager = PushNotificationManager.shared
    @State private var showingPermissionAlert = false

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Push Notifications")
                    Spacer()
                    Text(statusText)
                        .foregroundColor(.secondary)
                }

                if pushManager.authorizationStatus == .notDetermined {
                    Button("Enable Notifications") {
                        pushManager.requestPermission { granted in
                            if !granted {
                                showingPermissionAlert = true
                            }
                        }
                    }
                } else if pushManager.authorizationStatus == .denied {
                    Text("Notifications are disabled. Enable them in Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Album Update Notifications")
            } footer: {
                Text("Get notified when new photos are added to albums you've subscribed to.")
            }

            if let token = pushManager.deviceToken {
                Section("Device Info") {
                    Text("Token: \(String(token.prefix(16)))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Notifications")
        .alert("Permission Denied", isPresented: $showingPermissionAlert) {
            Button("OK", role: .cancel) {}
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Please enable notifications in Settings to receive album updates.")
        }
    }

    private var statusText: String {
        switch pushManager.authorizationStatus {
        case .notDetermined: return "Not Requested"
        case .denied: return "Disabled"
        case .authorized: return "Enabled"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
}
