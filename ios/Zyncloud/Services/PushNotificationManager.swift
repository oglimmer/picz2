import Combine
import UIKit
// `@preconcurrency`: `UNNotificationSettings` is not `Sendable`, and `getNotificationSettings`
// hands one to a `@Sendable` completion. Apple's shape, not ours.
@preconcurrency import UserNotifications
import os

/// - Note: `@MainActor` — the two `@Published` properties drive the settings screen, and every
///   entry point is already either a UIKit callback on main or hops to main by hand. Saying so
///   lets the compiler check it instead of the comments.
@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var deviceToken: String?

    /// Cached and invalidated on sign-out inside ``APIClientProvider``. This class used to keep
    /// its own copy of that cache; there were nine such copies.
    private var apiClient: APIClient { APIClientProvider.shared.clientOrAnonymous }

    override private init() {
        super.init()
        checkAuthorizationStatus()
    }

    /// Both of these use `await` rather than the completion-handler spellings, deliberately.
    ///
    /// `UserNotifications` is imported `@preconcurrency` (see the top of the file), which strips
    /// `@Sendable` off its completion handlers. Combined with `SWIFT_APPROACHABLE_CONCURRENCY`,
    /// that means a handler written inline inside this `@MainActor` class inherits main-actor
    /// isolation — and the framework then calls it on its own queue, which trips a main-actor
    /// check and crashes. The `async` spellings hop properly and have no such trap.
    func checkAuthorizationStatus() {
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorizationStatus = settings.authorizationStatus
        }
    }

    func requestPermission(completion: @escaping @Sendable @MainActor (Bool) -> Void) {
        AppLog.app.info("Requesting notification permission")
        Task { @MainActor in
            let granted: Bool
            do {
                granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                AppLog.app.error("Permission request failed: \(error.localizedDescription, privacy: .public)")
                authorizationStatus = .denied
                completion(false)
                return
            }

            authorizationStatus = granted ? .authorized : .denied
            AppLog.app.info("Notification permission granted: \(granted, privacy: .public)")

            if granted {
                AppLog.app.info("Registering for remote notifications")
                UIApplication.shared.registerForRemoteNotifications()
            } else {
                AppLog.app.notice("Notifications denied — not registering for remote notifications")
            }

            completion(granted)
        }
    }

    func registerDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        deviceToken = token
        // The token prefix and the account e-mail used to be printed unconditionally, so both
        // sat in the device console of every release build for anyone with the phone plugged in
        // (§5.10). A device token is a push address; an e-mail identifies the person. Neither
        // belongs in a shipping log. `Logger` enforces that without a `#if DEBUG` around a
        // second, quieter line: the prefix is readable with a debugger attached and shows as
        // `<private>` in a shipped build.
        AppLog.app.info("Device token received: \(String(token.prefix(8)))…")

        // Send to backend
        guard let credentials = KeychainHelper.shared.load() else {
            AppLog.app.error("No credentials — cannot register the device token")
            return
        }

        AppLog.app.info("Sending the device token to the server")
        sendTokenToBackend(token: token, email: credentials.username)
    }

    private func sendTokenToBackend(token: String, email: String) {
        let deviceModel = UIDevice.current.model
        let osVersion = UIDevice.current.systemVersion
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        let body = DeviceTokenBody(
            deviceToken: token,
            email: email,
            appVersion: appVersion,
            deviceModel: deviceModel,
            osVersion: osVersion,
        )

        apiClient.registerDeviceToken(body) { result in
            switch result {
            case .success:
                AppLog.app.info("Device token registered with the server")
            case let .failure(error):
                AppLog.app.error("Could not register the device token: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func unregisterDeviceToken() {
        guard let token = deviceToken else { return }

        apiClient.unregisterDeviceToken(token: token) { [weak self] result in
            switch result {
            case .success:
                AppLog.app.info("Device token unregistered")
                // The completion arrives on a URLSession thread, and `deviceToken` is a
                // `@Published` the settings screen observes. It was being written straight from
                // here — a real data race that only the actor annotation made visible.
                Task { @MainActor in self?.deviceToken = nil }
            case let .failure(error):
                AppLog.app.error("Could not unregister the device token: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
