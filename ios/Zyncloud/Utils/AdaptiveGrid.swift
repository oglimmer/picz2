import SwiftUI

/// Grid column counts that grow with the width the app is actually given, and shrink or grow
/// again with the size the reader picked.
///
/// `GridItem(.adaptive(minimum:))` cannot express "three photos on a phone, six on an iPad": one
/// minimum width has to serve both, and any minimum wide enough to keep an iPad from looking
/// like a contact sheet drops the phone to two columns. So the count comes from the horizontal
/// size class instead and the columns stay `.flexible()`, exactly as they were before iPad
/// support. The size class — not the device — is the input on purpose: an iPad in Slide Over or
/// a narrow split is `.compact`, and there the phone counts are the right ones.
///
/// ``GridSizeMode`` then shifts that count up or down a step. It defaults to `.medium` in both
/// calls, which is the count each grid drew before the control existed, so a caller that does
/// not care is unchanged.
enum AdaptiveGrid {
    /// Photo thumbnails, packed edge to edge.
    static func photoColumns(
        _ sizeClass: UserInterfaceSizeClass?,
        size: GridSizeMode = .medium,
        spacing: CGFloat = 2,
    ) -> [GridItem] {
        let count = sizeClass == .regular
            ? pick(size, small: 9, medium: 6, large: 3)
            : pick(size, small: 5, medium: 3, large: 2)
        return columns(count: count, spacing: spacing)
    }

    /// Album cards, which carry a title and a subtitle and so need more room than a thumbnail.
    static func cardColumns(
        _ sizeClass: UserInterfaceSizeClass?,
        size: GridSizeMode = .medium,
        spacing: CGFloat = 16,
    ) -> [GridItem] {
        let count = sizeClass == .regular
            ? pick(size, small: 6, medium: 4, large: 2)
            : pick(size, small: 3, medium: 2, large: 1)
        return columns(count: count, spacing: spacing)
    }

    private static func pick(_ size: GridSizeMode, small: Int, medium: Int, large: Int) -> Int {
        switch size {
        case .small: small
        case .medium: medium
        case .large: large
        }
    }

    private static func columns(count: Int, spacing: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }
}
