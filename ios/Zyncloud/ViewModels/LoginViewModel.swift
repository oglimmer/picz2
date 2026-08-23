import Combine
import Foundation

@MainActor
class LoginViewModel: ViewModelProtocol {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?

    init() {}

    var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
            !password.isEmpty
    }

    func login(completion: @escaping (Bool) -> Void) {
        guard isFormValid else {
            alertState = AlertState(
                title: "Invalid Input",
                message: "Please enter both email and password",
            )
            completion(false)
            return
        }

        isLoading = true
        alertState = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let api = APIClient(username: trimmedEmail, password: password)

        api.checkAuth { [weak self] result in
            guard let self else { return }

            DispatchQueue.main.async {
                self.isLoading = false

                switch result {
                case let .success(authResponse):
                    if KeychainHelper.shared.save(username: trimmedEmail, password: self.password) {
                        print("LoginViewModel: Login successful, credentials saved (verified=\(authResponse.emailVerified))")

                        if !authResponse.emailVerified {
                            self.alertState = AlertState(
                                title: "Email not verified",
                                message: "Please check your inbox for the verification link before using the app.",
                            )
                        }

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
                    self.handleError(error)
                    completion(false)
                }
            }
        }
    }
}
