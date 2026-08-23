import Combine
import Foundation

@MainActor
class ForgotPasswordViewModel: ViewModelProtocol {
    @Published var email: String = ""
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?
    @Published var didSubmit: Bool = false

    init() {}

    var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty else {
            alertState = AlertState(title: "Invalid Input", message: "Email is required")
            return
        }

        isLoading = true
        alertState = nil

        APIClient.requestPasswordReset(email: trimmedEmail) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success:
                    self.didSubmit = true
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }
}
