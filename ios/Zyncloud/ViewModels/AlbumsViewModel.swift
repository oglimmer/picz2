import Combine
import Foundation

@MainActor
class AlbumsViewModel: ViewModelProtocol {
    @Published var albums: [Album] = []
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?
    @Published var isRefreshing: Bool = false

    private let apiClient: APIClient?

    /// - Parameter apiClient: the client to talk to the server with. Defaults to the signed-in
    ///   account's; a test passes one pointed at a stub server instead.
    init(apiClient: APIClient? = APIClientProvider.shared.current) {
        self.apiClient = apiClient
    }

    func fetchAlbums() {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            return
        }

        isLoading = true
        alertState = nil

        apiClient.fetchAlbums { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isLoading = false
                self.isRefreshing = false

                switch result {
                case let .success(albums):
                    self.albums = albums
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }

    func refreshAlbums() async {
        guard let apiClient else { return }

        isRefreshing = true

        await withCheckedContinuation { continuation in
            apiClient.fetchAlbums { [weak self] result in
                guard let self else {
                    continuation.resume()
                    return
                }

                Task { @MainActor in
                    self.isRefreshing = false

                    switch result {
                    case let .success(albums):
                        self.albums = albums
                    case let .failure(error):
                        self.handleError(error)
                    }

                    continuation.resume()
                }
            }
        }
    }

    func createAlbum(name: String, description: String?, completion: @escaping @Sendable @MainActor (Bool) -> Void) {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            completion(false)
            return
        }

        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            alertState = AlertState(
                title: "Invalid Input",
                message: "Album name cannot be empty",
            )
            completion(false)
            return
        }

        isLoading = true
        alertState = nil

        apiClient.createAlbum(name: name, description: description) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case let .success(album):
                    self.albums.append(album)
                    self.showSuccess(message: "Album '\(album.name)' created successfully")
                    completion(true)

                case let .failure(error):
                    self.handleError(error)
                    completion(false)
                }
            }
        }
    }

    func updateAlbum(id: Int, name: String, description: String?, completion: @escaping @Sendable @MainActor (Bool) -> Void) {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            completion(false)
            return
        }

        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            alertState = AlertState(
                title: "Invalid Input",
                message: "Album name cannot be empty",
            )
            completion(false)
            return
        }

        isLoading = true
        alertState = nil

        apiClient.updateAlbum(id: id, name: name, description: description) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case let .success(album):
                    if let index = self.albums.firstIndex(where: { $0.id == id }) {
                        self.albums[index] = album
                    }
                    self.showSuccess(message: "Album updated successfully")
                    completion(true)

                case let .failure(error):
                    self.handleError(error)
                    completion(false)
                }
            }
        }
    }

    func deleteAlbum(id: Int, completion: @escaping @Sendable @MainActor (Bool) -> Void) {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            completion(false)
            return
        }

        isLoading = true
        alertState = nil

        apiClient.deleteAlbum(id: id) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case .success:
                    self.albums.removeAll { $0.id == id }
                    self.showSuccess(message: "Album deleted successfully")
                    completion(true)

                case let .failure(error):
                    self.handleError(error)
                    completion(false)
                }
            }
        }
    }

    func showDeleteConfirmation(for album: Album, onConfirm: @escaping @Sendable @MainActor () -> Void) {
        alertState = .confirmation(
            title: "Delete Album",
            message: "Are you sure you want to delete '\(album.name)'? This action cannot be undone.",
            confirmTitle: "Delete",
            confirmAction: onConfirm,
        )
    }
}
