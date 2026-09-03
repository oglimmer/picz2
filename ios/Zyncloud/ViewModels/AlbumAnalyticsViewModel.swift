import Combine
import Foundation

/// Drives the album's analytics screen: load the counts, pause or resume the counting, reset.
///
/// Holds no album of its own — the screen passes the id in. Nothing here is cached between
/// openings: the figures move while the owner is not looking, so a stale set shown instantly
/// would be worse than a short spinner.
@MainActor
class AlbumAnalyticsViewModel: ViewModelProtocol {
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?

    /// The counts, or nil until the first load lands.
    @Published private(set) var stats: AlbumAnalytics?

    /// True while a pause or a reset is in flight, so those two buttons go quiet without
    /// blanking the figures the way ``isLoading`` does.
    @Published private(set) var isSaving: Bool = false

    /// Set when the load failed and there is nothing to show. Held separately from
    /// ``alertState`` because a failed *load* is the whole screen, not a passing alert.
    @Published private(set) var loadError: String?

    /// True while the album is counting visits.
    var isCounting: Bool {
        guard let stats else { return false }
        return !stats.analyticsPaused
    }

    private let albumId: Int
    private let apiClient: APIClient?

    init(albumId: Int, apiClient: APIClient? = APIClientProvider.shared.current) {
        self.albumId = albumId
        self.apiClient = apiClient
    }

    func load() {
        guard let apiClient else {
            loadError = "Not authenticated. Please log in again."
            return
        }

        isLoading = true
        loadError = nil

        apiClient.fetchAlbumAnalytics(albumId: albumId) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case let .success(stats):
                    self.stats = stats
                    self.loadError = nil

                case let .failure(error):
                    // Only when there is nothing on screen yet. A failed refresh over figures
                    // that are already up would replace them with an error, which loses the
                    // numbers over a dropped connection.
                    if self.stats == nil {
                        self.loadError = (error as? AppError)?.errorDescription ?? error.localizedDescription
                    } else {
                        self.handleError(error)
                    }
                }
            }
        }
    }

    /// Stops the counting, or starts it again.
    ///
    /// The new state is written locally from what was sent, not read back: the endpoint answers
    /// with a message, not with the album, so there is nothing to read.
    func togglePaused() {
        guard let apiClient, let stats else { return }

        let nextPaused = !stats.analyticsPaused
        isSaving = true

        apiClient.setAnalyticsPaused(albumId: albumId, paused: nextPaused) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isSaving = false

                switch result {
                case .success:
                    self.stats?.analyticsPaused = nextPaused

                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }

    func showResetConfirmation() {
        alertState = .confirmation(
            title: "Reset analytics?",
            message: "Every recorded visit, page view, filter change and audio play for this "
                + "album is deleted. Your photos are not affected.\n\nThis cannot be undone.",
            confirmTitle: "Reset",
            confirmAction: { [weak self] in
                Task { @MainActor in self?.reset() }
            },
        )
    }

    /// Throws the counts away and reloads, so the zeros on screen are the server's and not
    /// this app's guess at what a reset did.
    func reset() {
        guard let apiClient else { return }

        isSaving = true

        apiClient.resetAlbumAnalytics(albumId: albumId) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isSaving = false

                switch result {
                case .success:
                    self.load()

                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }
}
