import Combine
import Foundation

@MainActor
class RegisterViewModel: ViewModelProtocol {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var acceptTerms: Bool = false
    @Published var acceptPrivacy: Bool = false
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?
    @Published var didRegister: Bool = false

    init() {}

    var isFormValid: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        return !trimmedEmail.isEmpty &&
            password.count >= 8 &&
            password == confirmPassword &&
            acceptTerms &&
            acceptPrivacy
    }

    func register() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        if trimmedEmail.isEmpty || password.isEmpty {
            alertState = AlertState(title: "Invalid Input", message: "Email and password are required")
            return
        }
        if password.count < 8 {
            alertState = AlertState(title: "Invalid Input", message: "Password must be at least 8 characters long")
            return
        }
        if password != confirmPassword {
            alertState = AlertState(title: "Invalid Input", message: "Passwords do not match")
            return
        }
        if !acceptTerms || !acceptPrivacy {
            alertState = AlertState(title: "Consent required", message: "You must accept the Terms and Conditions and Privacy Policy")
            return
        }

        isLoading = true
        alertState = nil

        APIClient.register(email: trimmedEmail, password: password) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success:
                    self.didRegister = true
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }
}
