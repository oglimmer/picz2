import SwiftUI
import UIKit

/// A URL to hand to the system share sheet, made `Identifiable` so it can drive `.sheet(item:)`.
struct ShareableLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// The system share sheet, wrapped by hand.
///
/// SwiftUI's `ShareLink` is the obvious choice, but inside a `Menu` — which is where both album
/// share entries live — it presents a sheet with nothing in it. Presenting
/// `UIActivityViewController` from a `.sheet(item:)` on the screen itself works because the sheet
/// no longer belongs to a menu that has already gone away.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
