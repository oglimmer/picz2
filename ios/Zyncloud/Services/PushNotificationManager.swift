import UIKit
import UserNotifications

class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var deviceToken: String?

    /// Cached, and dropped when the stored credentials change — same reasoning as
    /// ``SyncCoordinator``: a keychain read is a synchronous IPC to securityd, and this was
    /// doing one per access for a value that changes twice in a session (§5.10).
    private var cachedApiClient: APIClient?
    private var credentialsObserver: NSObjectProtocol?
    private var apiClient: APIClient {
        if let cachedApiClient { return cachedApiClient }
        let credentials = KeychainHelper.shared.load()
        let client = APIClient(
            username: credentials?.username,
            password: credentials?.password,
        )
        cachedApiClient = client
        return client
    }

    override private init() {
        super.init()
        credentialsObserver = NotificationCenter.default.addObserver(
            forName: KeychainHelper.credentialsDidChange, object: nil, queue: .main,
        ) { [weak self] _ in
            self?.cachedApiClient = nil
        }
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
        // The token prefix and the account e-mail used to be printed unconditionally, so both
        // sat in the device console of every release build for anyone with the phone plugged in
        // (§5.10). A device token is a push address; an e-mail identifies the person. Neither
        // belongs in a shipping log, and neither is needed to debug this path — "did we get one"
        // and "did we have credentials" are the only questions it answers.
        #if DEBUG
            print("PushNotificationManager: Device token received: \(String(token.prefix(8)))…")
        #else
            print("PushNotificationManager: Device token received")
        #endif

        // Send to backend
        guard let credentials = KeychainHelper.shared.load() else {
            print("PushNotificationManager: ERROR - No credentials, cannot register token")
            return
        }

        print("PushNotificationManager: Sending token to backend…")
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
