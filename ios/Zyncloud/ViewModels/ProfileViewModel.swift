import Combine
import Foundation

/// Everything that belongs to the account rather than to this phone: who is signed in, the
/// password, signing out and deleting the account. The same things the web app's Profile page
/// holds.
@MainActor
class ProfileViewModel: ViewModelProtocol {
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?
    @Published var isDeletingAccount: Bool = false

    private let syncCoordinator: SyncCoordinator
    private let apiClient: APIClient?

    init(syncCoordinator: SyncCoordinator = .shared,
         apiClient: APIClient? = APIClientProvider.shared.current)
    {
        self.syncCoordinator = syncCoordinator
        self.apiClient = apiClient
    }

    /// The address the phone signs in with. Read from the keychain rather than asked of the
    /// server: it is the value the Basic header carries, so it is the one that matters here.
    var email: String {
        apiClient?.username ?? ""
    }

    func logout(completion: @escaping @Sendable @MainActor () -> Void) {
        alertState = .confirmation(
            title: "Logout",
            message: "Are you sure you want to logout? This will clear all sync data.",
            confirmTitle: "Logout",
            confirmAction: {
                LocalSession.end(syncCoordinator: self.syncCoordinator)
                completion()
            },
        )
    }

    /// Delete the account on the server, then tear down every local trace of it.
    ///
    /// The teardown is the one ``logout(completion:)`` does, because leaving any of it behind
    /// after the account is gone would let the next screen try to sync against a user the server
    /// no longer knows. It only runs on a confirmed server-side delete; a failed request leaves
    /// the signed-in session intact so the user can retry.
    func deleteAccount(completion: @escaping @Sendable @MainActor () -> Void) {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            return
        }

        isDeletingAccount = true

        apiClient.deleteAccount { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isDeletingAccount = false

                switch result {
                case .success:
                    LocalSession.end(syncCoordinator: self.syncCoordinator)
                    completion()

                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }
}

/// What "this phone is no longer signed in" means locally. One place, because sign-out, account
/// delete and a password change the keychain could not store all have to leave the same state.
enum LocalSession {
    @MainActor
    static func end(syncCoordinator: SyncCoordinator) {
        // Via CredentialsManager so the share extension is signed out too — it used to keep its
        // own item.
        CredentialsManager.clear()
        UploadStore.shared.clear()
        syncCoordinator.settings.clear()
        syncCoordinator.clearQueue()
        syncCoordinator.metrics = SyncCoordinator.Metrics()
    }
}
