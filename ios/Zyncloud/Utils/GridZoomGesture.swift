import SwiftUI

extension View {
    /// Lets a pinch move this grid between the three ``GridSizeMode`` steps.
    func gridZoom(_ size: Binding<GridSizeMode>) -> some View {
        modifier(GridZoomModifier(size: size))
    }
}

/// Pinch to resize — the gesture Photos has trained every iPhone user to try on a grid of
/// pictures. The menu picker is the discoverable way to the same three sizes; this is the fast
/// one, and the two write the same stored value.
///
/// There is no continuous zoom on offer, because the layout underneath is a fixed column count
/// and not a scale factor. So the pinch is read as a ratchet: the first move past the threshold
/// steps once, and nothing more happens until the fingers lift. Without that latch one slow
/// pinch would run all the way from small to large.
private struct GridZoomModifier: ViewModifier {
    @Binding var size: GridSizeMode

    /// Set once this pinch has already moved a step, cleared when the fingers lift.
    @State private var hasStepped = false

    /// Far enough that a wobble while starting a two-finger scroll cannot trip it.
    private let threshold: CGFloat = 0.35

    func body(content: Content) -> some View {
        content
            .gesture(
                // A plain `.gesture`, not `.simultaneousGesture`: scrolling is one finger and
                // this is two, so they do not compete, and leaving the scroll view first claim
                // keeps the list feeling normal.
                MagnifyGesture(minimumScaleDelta: 0.1)
                    .onChanged { value in
                        guard !hasStepped else { return }
                        if value.magnification > 1 + threshold {
                            step(zoomingIn: true)
                        } else if value.magnification < 1 - threshold {
                            step(zoomingIn: false)
                        }
                    }
                    .onEnded { _ in hasStepped = false },
            )
            // Sized by touch, so the tick that says "it moved" has to come from the phone.
            .sensoryFeedback(.selection, trigger: size)
    }

    private func step(zoomingIn: Bool) {
        // Latched only on a real move, so a pinch that is already at the end of the range does
        // not block a pinch back the other way in the same gesture.
        guard let next = size.next(zoomingIn: zoomingIn) else { return }
        hasStepped = true
        withAnimation(.snappy) {
            size = next
        }
    }
}
