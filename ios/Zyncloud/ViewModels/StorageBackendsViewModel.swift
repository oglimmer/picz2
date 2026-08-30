import Combine
import Foundation

/// Drives the "bring your own storage" screen and the storage picker on the new-album form.
///
/// The list always contains the site's own storage first (`systemDefault`), so a picker can bind
/// straight to `backends` without inserting a synthetic row.
@MainActor
class StorageBackendsViewModel: ViewModelProtocol {
    @Published var backends: [StorageBackend] = []
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?

    /// Result of the last "Test connection", or nil when none has run since the form last changed.
    @Published var testResult: StorageBackendTestResult?

    private let apiClient: APIClient?

    /// - Parameter apiClient: the client to talk to the server with. Defaults to the signed-in
    ///   account's; a test passes one pointed at a stub server instead.
    init(apiClient: APIClient? = APIClientProvider.shared.current) {
        self.apiClient = apiClient
    }

    /// The site's own storage — the option an album gets when the user picks nothing.
    var systemDefault: StorageBackend? {
        backends.first { $0.systemDefault }
    }

    /// Whether the picker is worth showing. With only the site's storage there is no choice to
    /// make, and a one-option picker is just noise.
    var hasChoice: Bool {
        backends.count > 1
    }

    func fetchBackends() {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            return
        }

        isLoading = true
        alertState = nil

        apiClient.fetchStorageBackends { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case let .success(backends):
                    self.backends = backends
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }

    func create(_ body: StorageBackendBody, completion: @escaping @Sendable @MainActor (Bool) -> Void) {
        guard let apiClient else {
            completion(false)
            return
        }

        isLoading = true
        alertState = nil
        testResult = nil

        apiClient.createStorageBackend(body) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case let .success(backend):
                    self.backends.append(backend)
                    self.showSuccess(message: "Storage '\(backend.name)' added")
                    completion(true)
                case let .failure(error):
                    // The server only saves settings it has proved work, so the message here is
                    // the actual reason the bucket refused us.
                    self.handleError(error)
                    completion(false)
                }
            }
        }
    }

    func update(id: Int, body: StorageBackendBody, completion: @escaping @Sendable @MainActor (Bool) -> Void) {
        guard let apiClient else {
            completion(false)
            return
        }

        isLoading = true
        alertState = nil
        testResult = nil

        apiClient.updateStorageBackend(id: id, body: body) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case let .success(backend):
                    if let index = self.backends.firstIndex(where: { $0.id == id }) {
                        self.backends[index] = backend
                    }
                    self.showSuccess(message: "Storage updated")
                    completion(true)
                case let .failure(error):
                    self.handleError(error)
                    completion(false)
                }
            }
        }
    }

    func delete(_ backend: StorageBackend) {
        guard let apiClient else { return }

        // The server refuses this too; checking here keeps the user from watching a spinner just
        // to be told what the row already says.
        guard backend.albumCount == 0 else {
            alertState = AlertState(
                title: "Still in use",
                message: "Albums are still stored here. Delete or move them first.",
            )
            return
        }

        isLoading = true
        alertState = nil

        apiClient.deleteStorageBackend(id: backend.id) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case .success:
                    self.backends.removeAll { $0.id == backend.id }
                    self.showSuccess(message: "Storage removed")
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }

    /// Try settings without saving. A refused bucket comes back as `ok: false` rather than an
    /// error, so the form can show which step failed next to the fields that caused it.
    func test(id: Int?, body: StorageBackendBody) {
        guard let apiClient else { return }

        isLoading = true
        testResult = nil

        apiClient.testStorageBackend(id: id, body: body) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case let .success(outcome):
                    self.testResult = outcome
                case let .failure(error):
                    self.testResult = StorageBackendTestResult(
                        ok: false,
                        failedStep: "connect",
                        message: error.localizedDescription,
                    )
                }
            }
        }
    }
}
