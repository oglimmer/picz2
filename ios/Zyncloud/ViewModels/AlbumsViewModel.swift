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

    /// - Parameter storageBackendId: which storage to put the photos in, nil for the site's own.
    func createAlbum(
        name: String,
        description: String?,
        storageBackendId: Int? = nil,
        completion: @escaping @Sendable @MainActor (Bool) -> Void,
    ) {
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

        apiClient.createAlbum(
            name: name,
            description: description,
            storageBackendId: storageBackendId,
        ) { [weak self] result in
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

    /// Patches one row with a newer version of the same album.
    ///
    /// Used by the detail screen, which is pushed with a value: a publish made down there is
    /// invisible up here until the row is replaced. A missing id is ignored — the album was
    /// deleted while the detail screen was open.
    func replace(_ album: Album) {
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else { return }
        albums[index] = album
    }

    /// Opens or closes public access to an album.
    ///
    /// A new album is private: its share link 404s and subscribers hear nothing until this is
    /// turned on. The list row is patched from the server's answer rather than from the value we
    /// sent, so `publishedAt` is whatever the server actually stamped.
    func setPublished(id: Int, published: Bool, completion: @escaping @Sendable @MainActor (Bool) -> Void = { _ in }) {
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

        apiClient.setAlbumPublished(albumId: id, published: published) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case let .success(album):
                    self.replace(album)
                    self.showSuccess(message: published
                        ? "Album is public. The share link works now."
                        : "Album is private. The share link no longer opens.")
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
