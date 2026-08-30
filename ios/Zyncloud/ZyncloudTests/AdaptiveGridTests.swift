import SwiftUI
import Testing
@testable import Zyncloud

/// The grids used to be a fixed `private let` of two or three `.flexible()` columns, which is
/// right for a phone and wrong for an iPad — three photos across a 13-inch screen is three
/// posters. `AdaptiveGrid` picks the count from the horizontal size class, so the thing under
/// test is the mapping: regular gets more columns, compact keeps the phone counts, and an iPad
/// squeezed into Slide Over reports compact and so is treated as a phone.
struct AdaptiveGridTests {
    // MARK: - Photo thumbnails

    @Test(arguments: [
        (UserInterfaceSizeClass.regular, 6),
        (UserInterfaceSizeClass.compact, 3),
    ])
    func `photo column count follows the size class`(sizeClass: UserInterfaceSizeClass, count: Int) {
        #expect(AdaptiveGrid.photoColumns(sizeClass).count == count)
    }

    /// SwiftUI hands `nil` before the size class is known. A phone layout is the safe answer.
    @Test func `an unknown size class gets the phone count`() {
        #expect(AdaptiveGrid.photoColumns(nil).count == 3)
    }

    // MARK: - Album cards

    @Test(arguments: [
        (UserInterfaceSizeClass.regular, 4),
        (UserInterfaceSizeClass.compact, 2),
    ])
    func `card column count follows the size class`(sizeClass: UserInterfaceSizeClass, count: Int) {
        #expect(AdaptiveGrid.cardColumns(sizeClass).count == count)
    }

    @Test func `cards get fewer columns than photos at every size class`() {
        for sizeClass: UserInterfaceSizeClass? in [.regular, .compact, nil] {
            #expect(AdaptiveGrid.cardColumns(sizeClass).count < AdaptiveGrid.photoColumns(sizeClass).count)
        }
    }

    // MARK: - Spacing

    /// The caller's spacing has to survive: the photo grid is packed at 2 points and the card
    /// grid is airy at 16, and swapping them is immediately visible.
    @Test func `spacing is carried onto every column`() {
        for column in AdaptiveGrid.photoColumns(.regular, spacing: 7) {
            #expect(column.spacing == 7)
        }
    }
}
