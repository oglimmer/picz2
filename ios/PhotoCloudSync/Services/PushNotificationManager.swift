import UIKit
import UserNotifications

class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var deviceToken: String?

    private var apiClient: APIClient {
        let credentials = KeychainHelper.shared.load()
        return APIClient(
            username: credentials?.username,
            password: credentials?.password,
        )
    }

    override private init() {
        super.init()
        checkAuthorizationStatus()
    }

    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        print("PushNotificationManager: Requesting notification permission...")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.authorizationStatus = granted ? .authorized : .denied
                completion(granted)
            }

            if let error {
                print("PushNotificationManager: Permission request error: \(error)")
            }

            print("PushNotificationManager: Permission granted: \(granted)")

            if granted {
                print("PushNotificationManager: Registering for remote notifications...")
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                print("PushNotificationManager: Permission denied, not registering for remote notifications")
            }
        }
    }

    func registerDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        deviceToken = token
        print("PushNotificationManager: Device token received: \(String(token.prefix(32)))...")

        // Send to backend
        guard let credentials = KeychainHelper.shared.load() else {
            print("PushNotificationManager: ERROR - No credentials, cannot register token")
            return
        }

        print("PushNotificationManager: Credentials found for: \(credentials.username)")
        print("PushNotificationManager: Sending token to backend...")
        sendTokenToBackend(token: token, email: credentials.username)
    }

    private func sendTokenToBackend(token: String, email: String) {
        let deviceModel = UIDevice.current.model
        let osVersion = UIDevice.current.systemVersion
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        let body: [String: Any] = [
            "deviceToken": token,
            "email": email,
            "appVersion": appVersion,
            "deviceModel": deviceModel,
            "osVersion": osVersion,
        ]

        print("PushNotificationManager: Calling API to register token...")
        apiClient.registerDeviceToken(body: body) { result in
            switch result {
            case .success:
                print("PushNotificationManager: ✅ Device token registered successfully with backend")
            case let .failure(error):
                print("PushNotificationManager: ❌ Failed to register token with backend: \(error)")
            }
        }
    }

    func unregisterDeviceToken() {
        guard let token = deviceToken else { return }

        apiClient.unregisterDeviceToken(token: token) { result in
            switch result {
            case .success:
                print("PushNotificationManager: Device token unregistered")
                self.deviceToken = nil
            case let .failure(error):
                print("PushNotificationManager: Failed to unregister: \(error)")
            }
        }
    }
}
