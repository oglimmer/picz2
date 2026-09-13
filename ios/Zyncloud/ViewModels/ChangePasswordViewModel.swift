import Combine
import Foundation

@MainActor
class ChangePasswordViewModel: ViewModelProtocol {
    @Published var currentPassword: String = ""
    @Published var newPassword: String = ""
    @Published var confirmPassword: String = ""
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?
    /// The server took the new password and this phone stored it.
    @Published var didChange: Bool = false
    /// The server took the new password but the keychain refused it. The old one is dead on the
    /// server, so this phone can no longer sign in by itself; the screen sends the user back to
    /// the sign-in page.
    @Published var mustSignInAgain: Bool = false

    /// The server's rule (`UserService.validatePassword`), checked here too so the button stays
    /// off until the form can succeed.
    static let minimumLength = 8

    private let syncCoordinator: SyncCoordinator
    private let apiClient: APIClient?
    private let storeCredentials: (Credentials) -> Bool

    init(syncCoordinator: SyncCoordinator = .shared,
         apiClient: APIClient? = APIClientProvider.shared.current,
         storeCredentials: @escaping (Credentials) -> Bool = CredentialsManager.save)
    {
        self.syncCoordinator = syncCoordinator
        self.apiClient = apiClient
        self.storeCredentials = storeCredentials
    }

    var isFormValid: Bool {
        !currentPassword.isEmpty
            && newPassword.count >= Self.minimumLength
            && newPassword == confirmPassword
    }

    /// What is wrong with the new password, in words, or nil. Stays quiet about a field nobody
    /// has typed in yet, so the screen does not open with a complaint.
    var validationHint: String? {
        if !newPassword.isEmpty, newPassword.count < Self.minimumLength {
            return "The new password needs at least \(Self.minimumLength) characters."
        }
        if !confirmPassword.isEmpty, newPassword != confirmPassword {
            return "The new passwords do not match."
        }
        return nil
    }

    func submit() {
        guard isFormValid else { return }
        guard let apiClient, let email = apiClient.username else {
            alertState = AlertState(title: "Error", message: "Not authenticated. Please log in again.")
            return
        }

        let newPassword = newPassword
        isLoading = true
        alertState = nil

        apiClient.changePassword(currentPassword: currentPassword, newPassword: newPassword) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false

                switch result {
                case .success:
                    // Straight away: the server refuses the old password from this moment, and
                    // every client this app holds reads its password from the keychain.
                    if self.storeCredentials(Credentials(email: email, password: newPassword)) {
                        self.didChange = true
                    } else {
                        LocalSession.end(syncCoordinator: self.syncCoordinator)
                        self.mustSignInAgain = true
                    }
                    self.currentPassword = ""
                    self.newPassword = ""
                    self.confirmPassword = ""

                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }
}
