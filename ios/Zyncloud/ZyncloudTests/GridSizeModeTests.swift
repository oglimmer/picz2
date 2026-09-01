import Testing
@testable import Zyncloud

/// The pinch gesture on the two grid screens moves one step per pinch, and it reads that step
/// off ``GridSizeMode/next(zoomingIn:)``. Two things have to hold: pinching apart makes tiles
/// bigger, and the range has ends — otherwise the gesture would wrap from large back to small
/// and a reader who kept pinching would watch the grid flip inside out.
struct GridSizeModeTests {
    @Test func `zooming in walks towards bigger tiles`() {
        #expect(GridSizeMode.small.next(zoomingIn: true) == .medium)
        #expect(GridSizeMode.medium.next(zoomingIn: true) == .large)
    }

    @Test func `zooming out walks towards smaller tiles`() {
        #expect(GridSizeMode.large.next(zoomingIn: false) == .medium)
        #expect(GridSizeMode.medium.next(zoomingIn: false) == .small)
    }

    /// `nil`, not a wrap and not `self`: the gesture uses it to tell "nothing moved", which is
    /// what stops it latching and firing feedback for a pinch that changed nothing.
    @Test func `the range does not wrap at either end`() {
        #expect(GridSizeMode.large.next(zoomingIn: true) == nil)
        #expect(GridSizeMode.small.next(zoomingIn: false) == nil)
    }

    /// The stored value is the raw string, so renaming a case would silently reset everyone's
    /// choice on the next launch.
    @Test func `the stored raw values are stable`() {
        #expect(GridSizeMode.allCases.map(\.rawValue) == ["small", "medium", "large"])
    }
}
