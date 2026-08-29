import Foundation

/// The album's publish gate. Owner-scoped: only the account that owns an album can open or close
/// public access to it.
///
/// A new album is created unpublished — the share token exists from the start, but every
/// share-token route answers 404 and the subscription notifier skips the album until this is
/// turned on. That is why the share sheet is gated on ``Album/isPublished`` rather than on the
/// token alone.
extension APIClient {
    /// Opens or closes public access. Publishing an album for the first time also stamps the date
    /// subscribers are notified from, which the server does — the phone never sends it.
    func setAlbumPublished(
        albumId: Int,
        published: Bool,
        completion: @escaping @Sendable (Result<Album, Error>) -> Void,
    ) {
        send(
            .put,
            "api/albums/\(albumId)/published",
            query: [URLQueryItem(name: "published", value: published ? "true" : "false")],
            expecting: AlbumResponse.self,
        ) { result in
            completion(result.map(\.album))
        }
    }
}
