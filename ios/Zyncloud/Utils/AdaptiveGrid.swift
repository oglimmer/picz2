import SwiftUI

/// Grid column counts that grow with the width the app is actually given.
///
/// `GridItem(.adaptive(minimum:))` cannot express "three photos on a phone, six on an iPad": one
/// minimum width has to serve both, and any minimum wide enough to keep an iPad from looking
/// like a contact sheet drops the phone to two columns. So the count comes from the horizontal
/// size class instead and the columns stay `.flexible()`, exactly as they were before iPad
/// support. The size class — not the device — is the input on purpose: an iPad in Slide Over or
/// a narrow split is `.compact`, and there the phone counts are the right ones.
enum AdaptiveGrid {
    /// Photo thumbnails, packed edge to edge.
    static func photoColumns(_ sizeClass: UserInterfaceSizeClass?, spacing: CGFloat = 2) -> [GridItem] {
        columns(count: sizeClass == .regular ? 6 : 3, spacing: spacing)
    }

    /// Album cards, which carry a title and a subtitle and so need more room than a thumbnail.
    static func cardColumns(_ sizeClass: UserInterfaceSizeClass?, spacing: CGFloat = 16) -> [GridItem] {
        columns(count: sizeClass == .regular ? 4 : 2, spacing: spacing)
    }

    private static func columns(count: Int, spacing: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }
}
