import SafariServices
import SwiftUI

/// The three legal pages the web app serves, reachable from inside the app.
///
/// App Review expects the terms, the privacy policy and — for a German operator — the imprint
/// to be reachable before an account exists, so these are linked from the landing page itself
/// and not only from the sign-up form.
enum LegalPage: String, CaseIterable, Identifiable {
    case privacy
    case terms
    case imprint

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .privacy: "Privacy"
        case .terms: "Terms"
        case .imprint: "Imprint"
        }
    }

    var url: URL? {
        URL(string: "\(AppConfiguration.baseURL)/\(rawValue)")
    }
}

/// `SFSafariViewController` in a sheet: the page keeps the site's own styling and the reader
/// never leaves the app, which is what Review wants from an in-app legal link.
struct LegalPageSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: configuration)
    }

    func updateUIViewController(_: SFSafariViewController, context _: Context) {}
}
