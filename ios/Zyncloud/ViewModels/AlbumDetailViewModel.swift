import Combine
import Foundation

@MainActor
class AlbumDetailViewModel: ViewModelProtocol {
    @Published var photos: [Photo] = []
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?
    @Published var isLoadingMore: Bool = false

    /// True while a sort request is in flight, so the Sort menu can disable itself.
    @Published var isReordering: Bool = false

    /// Mirrors the web gallery's "Arrange by hand" mode: while on, the grid is replaced by a
    /// movable list and every move is written straight back to the server.
    @Published var isArrangingByHand: Bool = false

    let album: Album
    private var apiClient: APIClient?
    private var currentPage: Int = 1
    private var hasMorePages: Bool = true

    init(album: Album) {
        self.album = album
        loadCredentials()
    }

    private func loadCredentials() {
        if let credentials = KeychainHelper.shared.load() {
            apiClient = APIClient(
                username: credentials.username,
                password: credentials.password,
            )
        }
    }

    func fetchPhotos() {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            return
        }

        isLoading = true
        alertState = nil

        // Server doesn't use pagination - fetches all files in album
        apiClient.fetchFiles(albumId: album.id) { [weak self] result in
            guard let self else { return }

            DispatchQueue.main.async {
                self.isLoading = false

                switch result {
                case let .success(response):
                    self.photos = response.files
                    self.hasMorePages = false // No pagination on server

                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }

    func refreshPhotos() async {
        guard let apiClient else { return }

        await withCheckedContinuation { continuation in
            apiClient.fetchFiles(albumId: album.id) { [weak self] result in
                guard let self else {
                    continuation.resume()
                    return
                }

                DispatchQueue.main.async {
                    switch result {
                    case let .success(response):
                        self.photos = response.files
                        self.hasMorePages = false
                    case let .failure(error):
                        self.handleError(error)
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Sorting

    /// Runs one of the album-wide sorts on the server, then reloads so the grid shows the new
    /// order. The confirmation prompt lives in the view, same split as the web app.
    func reorder(by action: AlbumSortAction) {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            return
        }

        isReordering = true

        apiClient.reorderAlbum(albumId: album.id, by: action) { [weak self] result in
            guard let self else { return }

            DispatchQueue.main.async {
                switch result {
                case let .success(count):
                    Task { @MainActor in
                        await self.refreshPhotos()
                        self.isReordering = false
                        self.showSuccess(message: "Reordered \(count) files by \(action.title.lowercased()).")
                    }

                case let .failure(error):
                    self.isReordering = false
                    self.handleError(error)
                }
            }
        }
    }

    func toggleArrangeByHand() {
        isArrangingByHand.toggle()
    }

    /// Applies a hand move locally, then persists the whole album order. On failure the photos
    /// are reloaded from the server so the list can never keep an order the server rejected.
    func movePhotos(from source: IndexSet, to destination: Int) {
        guard let apiClient else { return }

        let previous = photos
        photos.move(fromOffsets: source, toOffset: destination)

        let fileIds = photos.map(\.id)
        isReordering = true

        apiClient.reorderFiles(fileIds: fileIds) { [weak self] result in
            guard let self else { return }

            DispatchQueue.main.async {
                self.isReordering = false

                if case let .failure(error) = result {
                    self.photos = previous
                    self.handleError(error)
                }
            }
        }
    }

    // MARK: - Media URLs

    func thumbnailURL(for photo: Photo) -> URL? {
        // Use public token to access image via /api/i/{token}?size=thumbnail
        // This endpoint doesn't require authentication
        let baseURL = AppConfiguration.apiBaseURL
        var components = URLComponents(url: baseURL.appendingPathComponent("api/i/\(photo.publicToken)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "size", value: "thumbnail")]

        if let url = components?.url {
            print("🖼️  Thumbnail URL for \(photo.originalName): \(url.absoluteString)")
            return url
        } else {
            print("❌ Failed to create thumbnail URL for \(photo.originalName)")
            return nil
        }
    }

    /// Playback URL for a video asset.
    ///
    /// Deliberately carries **no** `size` parameter: with no size the server hands back the
    /// transcoded H.264 rendition when one exists and the untouched original otherwise. Any
    /// size value would ask for an image derivative a video does not have — that is what made
    /// tapping a video show "Failed". Mirrors what the web Lightbox does.
    func videoURL(for photo: Photo) -> URL? {
        let baseURL = AppConfiguration.apiBaseURL
        return URLComponents(
            url: baseURL.appendingPathComponent("api/i/\(photo.publicToken)"),
            resolvingAgainstBaseURL: false,
        )?.url
    }

    func fullImageURL(for photo: Photo) -> URL? {
        // Use public token to access original/large image via /api/i/{token}
        let baseURL = AppConfiguration.apiBaseURL
        var components = URLComponents(url: baseURL.appendingPathComponent("api/i/\(photo.publicToken)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "size", value: "large")]
        return components?.url
    }
}
