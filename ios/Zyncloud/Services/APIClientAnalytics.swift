import Foundation

/// The owner's view of a shared album's visitor counts — `/api/albums/{id}/analytics`.
///
/// Reading, pausing and resetting only. The events themselves are recorded on the public
/// share-token routes when a visitor opens the album in a browser, and this app never posts
/// one: a phone looking at its owner's own album is not a visit.
extension APIClient {
    func fetchAlbumAnalytics(albumId: Int, completion: @escaping @Sendable (Result<AlbumAnalytics, Error>) -> Void) {
        send(.get, "api/albums/\(albumId)/analytics", expecting: AlbumAnalytics.self, completion: completion)
    }

    /// Stops or restarts the counting. Pausing keeps every figure already collected — it is the
    /// switch for "do not count me testing my own album", not a way to clear the numbers.
    func setAnalyticsPaused(albumId: Int, paused: Bool, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(
            .put,
            "api/albums/\(albumId)/analytics/paused",
            query: [URLQueryItem(name: "paused", value: paused ? "true" : "false")],
            completion: completion,
        )
    }

    /// Deletes every recorded event for the album. Irreversible, and the photos are untouched.
    func resetAlbumAnalytics(albumId: Int, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(.delete, "api/albums/\(albumId)/analytics", completion: completion)
    }
}
