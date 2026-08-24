import Foundation
import Testing
@testable import Zyncloud

/// The public album link the share sheet hands out. It has to match the web app's route
/// (`/public/album/<shareToken>`) exactly — a link that is one path segment off looks like a
/// working share until someone opens it.
struct AlbumShareLinkTests {
    @Test func buildsTheWebAppsPublicAlbumRoute() {
        let url = AppConfiguration.publicAlbumURL(shareToken: "abc123")
        #expect(url?.absoluteString == AppConfiguration.baseURL + "/public/album/abc123")
    }

    /// An album with no token cannot be shared, and no link may be invented on the phone.
    @Test func refusesAnEmptyToken() {
        #expect(AppConfiguration.publicAlbumURL(shareToken: "") == nil)
    }
}
