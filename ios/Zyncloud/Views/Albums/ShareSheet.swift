import SwiftUI
import UIKit

/// A URL to hand to the system share sheet, made `Identifiable` so it can drive `.sheet(item:)`.
struct ShareableLink: Identifiable {
    let url: URL
    var id: String {
        url.absoluteString
    }
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

    /// On an iPad this controller is popover-backed. It is presented as the content of a sheet
    /// here rather than as a popover of its own, so it never crashes for want of an anchor — but
    /// an activity that opens its own popover reads the anchor back, and an unset one lands in the
    /// top-left corner. Point it at the middle of the sheet, with no arrow to point at nothing.
    func updateUIViewController(_ controller: UIActivityViewController, context _: Context) {
        guard let popover = controller.popoverPresentationController else { return }
        popover.sourceView = controller.view
        popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
    }
}
