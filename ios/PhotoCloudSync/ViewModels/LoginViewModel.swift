import Combine
import Foundation

@MainActor
class LoginViewModel: ViewModelProtocol {
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?

    private let apiClient: APIClient

    init(apiClient: APIClient? = nil) {
        // Allow dependency injection for testing
        self.apiClient = apiClient ?? APIClient()
    }

    var isFormValid: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
            !password.isEmpty
    }

    func login(completion: @escaping (Bool) -> Void) {
        guard isFormValid else {
            alertState = AlertState(
                title: "Invalid Input",
                message: "Please enter both username and password",
            )
            completion(false)
            return
        }

        isLoading = true
        alertState = nil

        // Create API client with credentials
        let api = APIClient(username: username, password: password)

        // Test connection by fetching albums
        api.fetchAlbums { [weak self] result in
            guard let self else { return }

            DispatchQueue.main.async {
                self.isLoading = false

                switch result {
                case .success:
                    // Save credentials to keychain
                    if KeychainHelper.shared.save(username: self.username, password: self.password) {
                        print("LoginViewModel: Login successful, credentials saved")

                        // Request notification permissions after first login
                        if PushNotificationManager.shared.authorizationStatus == .notDetermined {
                            PushNotificationManager.shared.requestPermission { _ in }
                        }

                        completion(true)
                    } else {
                        self.alertState = AlertState(
                            title: "Error",
                            message: "Failed to save credentials securely",
                        )
                        completion(false)
                    }

                case let .failure(error):
                    self.handleError(AppError.authentication(error.localizedDescription))
                    completion(false)
                }
            }
        }
    }
}
