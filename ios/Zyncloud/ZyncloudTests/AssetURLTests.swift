import Foundation
import Testing
@testable import Zyncloud

/// The three URLs every picture on screen is fetched from.
///
/// Each is one `size` parameter away from being wrong, and each wrong one fails as a broken
/// image rather than as an error — a thumbnail asked for at `large` still decodes, a video
/// asked for at any size does not decode at all. Cheap to assert, expensive to notice.
struct AssetURLTests {
    private func photo(token: String = "tok123", mimetype: String = "image/jpeg") -> Photo {
        FileInfo(
            id: 1,
            originalName: "shot.jpg",
            filename: "shot.jpg",
            publicToken: token,
            size: 42,
            mimetype: mimetype,
            path: nil,
            uploadedAt: "2026-05-04T12:00:00Z",
            displayOrder: nil,
            tags: [],
            albumId: 7,
            albumName: "Trip",
        )
    }

    private func query(_ url: URL?) -> [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } }) { _, last in last }
    }

    // MARK: - The route

    /// `/api/i/{token}` and nothing else. The token is the credential — the server declares that
    /// route `permitAll` — so a URL built any other way needs auth the image loader does not send.
    @Test func `every rendition is served from the public token route`() {
        let subject = photo(token: "abc")

        #expect(AssetURLs.thumbnail(for: subject)?.path == "/api/i/abc")
        #expect(AssetURLs.image(for: subject)?.path == "/api/i/abc")
        #expect(AssetURLs.video(for: subject)?.path == "/api/i/abc")
    }

    @Test func `therendition UR ls sit under the configured server`() {
        let url = AssetURLs.thumbnail(for: photo())

        #expect(url?.absoluteString.hasPrefix(AppConfiguration.apiBaseURL.absoluteString) == true)
    }

    // MARK: - The size parameter

    @Test func `thegrid asks for the thumbnail rendition`() {
        #expect(query(AssetURLs.thumbnail(for: photo()))["size"] == "thumbnail")
    }

    @Test func `thefull screen asks for the large rendition`() {
        #expect(query(AssetURLs.image(for: photo()))["size"] == "large")
    }

    /// The load-bearing one. Any `size` value asks for an image derivative a video does not have,
    /// and `AVPlayer` reports that as a silent failure to start rather than as an error. With no
    /// parameter the server hands back the H.264 rendition, or the original when it has none.
    @Test func `video playback sends no size parameter at all`() {
        let url = AssetURLs.video(for: photo(mimetype: "video/quicktime"))

        #expect(query(url).isEmpty)
        #expect(url?.query == nil)
    }

    // MARK: - The token itself

    /// The token goes in verbatim. It is the whole credential, so a URL built from a mangled one
    /// asks for an asset that does not exist and renders as a failure.
    @Test func `thetoken is carried through untouched`() {
        let url = AssetURLs.image(for: photo(token: "Zm9vYmFy-_9"))

        #expect(url?.path == "/api/i/Zm9vYmFy-_9")
    }
}
