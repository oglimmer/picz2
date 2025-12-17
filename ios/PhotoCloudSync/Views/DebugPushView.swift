import SwiftUI
import UserNotifications

struct DebugPushView: View {
    @StateObject private var pushManager = PushNotificationManager.shared
    @State private var statusMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Push Notification Debug")
                .font(.headline)

            Text("Status: \(statusText)")
            Text("Device Token: \(pushManager.deviceToken ?? "None")")
                .font(.caption)

            Button("Request Permission") {
                pushManager.requestPermission { granted in
                    statusMessage = granted ? "Permission granted" : "Permission denied"
                }
            }

            Button("Re-register Device Token") {
                if let credentials = KeychainHelper.shared.load() {
                    statusMessage = "User: \(credentials.username)"
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    statusMessage = "Not logged in"
                }
            }

            Text(statusMessage)
                .foregroundColor(.blue)
        }
        .padding()
        .onAppear {
            pushManager.checkAuthorizationStatus()
        }
    }

    private var statusText: String {
        switch pushManager.authorizationStatus {
        case .notDetermined: return "Not Requested"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
}
