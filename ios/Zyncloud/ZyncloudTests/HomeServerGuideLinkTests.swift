import Foundation
import Testing
@testable import Zyncloud

/// The sign-up form opens the web app's home-server guide in the app. A wrong path would show
/// the web app's "not found" page inside a sheet, which looks like a broken app.
struct HomeServerGuideLinkTests {
    @Test func theGuideLivesUnderHelpOnTheSameSite() {
        #expect(AppConfiguration.homeServerGuideURL.absoluteString
            == AppConfiguration.baseURL + "/help/home-server")
    }
}
