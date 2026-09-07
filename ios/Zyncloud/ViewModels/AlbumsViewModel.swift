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

    /// The shelf with one album moved onto another album's place, or nil when the move is not a
    /// move at all.
    ///
    /// Dropping a tile onto another tile means "take its place": everything from there on shifts
    /// along. An id that is not on the shelf answers nil — the album was deleted on another device
    /// while the drag was in flight, or the payload came from somewhere else entirely.
    static func shelf(_ albums: [Album], moving draggedId: Int, onto targetId: Int) -> [Album]? {
        guard draggedId != targetId,
              let from = albums.firstIndex(where: { $0.id == draggedId }),
              let to = albums.firstIndex(where: { $0.id == targetId })
        else { return nil }

        var moved = albums
        let dragged = moved.remove(at: from)
        moved.insert(dragged, at: to)
        return moved
    }

    /// Moves one album onto another album's place and saves the whole order.
    ///
    /// The new order is shown at once and then sent. A refused save puts the old order back, so
    /// the shelf never keeps an order the server did not take.
    func moveAlbum(draggedId: Int, onto targetId: Int) {
        guard let next = Self.shelf(albums, moving: draggedId, onto: targetId) else { return }

        let previous = albums
        albums = next

        guard let apiClient else { return }

        apiClient.reorderAlbums(albumIds: next.map(\.id)) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                switch result {
                case let .success(albums):
                    // The server appends any album this device had not heard of, so its answer is
                    // the only complete picture of the new order.
                    self.albums = albums
                case let .failure(error):
                    self.albums = previous
                    self.handleError(error)
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

    /// Copies an album and its photos into a new album, and puts the copy in the list.
    ///
    /// The server copies metadata only — the photos themselves are not re-uploaded — and always
    /// hands back an unpublished copy, so the new card shows the PRIVATE badge even when the
    /// source is public.
    func duplicateAlbum(id: Int, completion: @escaping @Sendable @MainActor (Bool) -> Void = { _ in }) {
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

        apiClient.duplicateAlbum(id: id) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case let .success(album):
                    self.albums.append(album)
                    self.showSuccess(message: "Album '\(album.name)' created. The copy is not published.")
                    completion(true)

                case let .failure(error):
                    self.handleError(error)
                    completion(false)
                }
            }
        }
    }

    /// Asks before copying, and says what the copy will and will not carry.
    func showDuplicateConfirmation(for album: Album, onConfirm: @escaping @Sendable @MainActor () -> Void) {
        let photoCount = album.imageCount ?? 0
        var message = photoCount > 0
            ? "The copy gets the same \(photoCount) photo\(photoCount == 1 ? "" : "s") and the same tags."
            : "The album is empty, so the copy starts empty too."
        // Say it here, or the missing share link on the new card reads as a bug.
        message += "\n\nThe copy is not published."

        alertState = .confirmation(
            title: "Duplicate '\(album.name)'?",
            message: message,
            confirmTitle: "Duplicate Album",
            destructive: false,
            confirmAction: onConfirm,
        )
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
