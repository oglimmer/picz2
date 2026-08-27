import Foundation

/// Where an asset's bytes live on the server.
///
/// The public token is the credential for `/api/i/{token}` — `SecurityConfig` declares it
/// `permitAll` — so these carry no auth and can be handed straight to an image loader or an
/// `AVPlayer`.
enum AssetURLs {
    /// The grid-sized rendition.
    static func thumbnail(for photo: Photo) -> URL? {
        var components = URLComponents(
            url: AppConfiguration.apiBaseURL.appendingPathComponent("api/i/\(photo.publicToken)"),
            resolvingAgainstBaseURL: false,
        )
        components?.queryItems = [URLQueryItem(name: "size", value: "thumbnail")]
        return components?.url
    }

    /// A rendition sized for a full screen.
    static func image(for photo: Photo) -> URL? {
        var components = URLComponents(
            url: AppConfiguration.apiBaseURL.appendingPathComponent("api/i/\(photo.publicToken)"),
            resolvingAgainstBaseURL: false,
        )
        components?.queryItems = [URLQueryItem(name: "size", value: "large")]
        return components?.url
    }

    /// Playback URL for a video.
    ///
    /// No `size` parameter, deliberately: with none the server hands back the transcoded H.264
    /// rendition when it has one and the untouched original otherwise. Any size value asks for
    /// an image derivative a video does not have, which is what renders as a failure.
    static func video(for photo: Photo) -> URL? {
        URLComponents(
            url: AppConfiguration.apiBaseURL.appendingPathComponent("api/i/\(photo.publicToken)"),
            resolvingAgainstBaseURL: false,
        )?.url
    }
}
