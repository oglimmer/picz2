import Combine
import Foundation

@MainActor
class AlbumDetailViewModel: ViewModelProtocol {
    @Published var photos: [Photo] = []
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?
    @Published var isLoadingMore: Bool = false

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

    func loadMorePhotos() {
        // No-op: Server doesn't support pagination
        // All files are loaded in initial fetch
    }

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

    func fullImageURL(for photo: Photo) -> URL? {
        // Use public token to access original/large image via /api/i/{token}
        let baseURL = AppConfiguration.apiBaseURL
        var components = URLComponents(url: baseURL.appendingPathComponent("api/i/\(photo.publicToken)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "size", value: "large")]
        return components?.url
    }
}
