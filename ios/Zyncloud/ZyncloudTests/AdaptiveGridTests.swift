import SwiftUI
import Testing
@testable import Zyncloud

/// The grids used to be a fixed `private let` of two or three `.flexible()` columns, which is
/// right for a phone and wrong for an iPad — three photos across a 13-inch screen is three
/// posters. `AdaptiveGrid` picks the count from the horizontal size class, so the thing under
/// test is the mapping: regular gets more columns, compact keeps the phone counts, and an iPad
/// squeezed into Slide Over reports compact and so is treated as a phone.
///
/// A second input arrived with the size switch: ``GridSizeMode`` steps that count up or down.
/// The default has to stay on the old count, or every install would silently re-lay-out.
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
            for size in GridSizeMode.allCases {
                #expect(
                    AdaptiveGrid.cardColumns(sizeClass, size: size).count
                        < AdaptiveGrid.photoColumns(sizeClass, size: size).count,
                )
            }
        }
    }

    // MARK: - Size steps

    /// The whole point of the default: an install that never touches the switch keeps the layout
    /// it has always had.
    @Test func `the default size draws the counts the grids had before the switch existed`() {
        #expect(AdaptiveGrid.photoColumns(.compact, size: .medium).count == 3)
        #expect(AdaptiveGrid.photoColumns(.regular, size: .medium).count == 6)
        #expect(AdaptiveGrid.cardColumns(.compact, size: .medium).count == 2)
        #expect(AdaptiveGrid.cardColumns(.regular, size: .medium).count == 4)
    }

    /// Small means more tiles across, large means fewer. Getting this backwards would put the
    /// contact sheet behind the "Large" row.
    @Test func `smaller tiles mean more columns at every size class`() {
        for sizeClass: UserInterfaceSizeClass? in [.regular, .compact, nil] {
            #expect(AdaptiveGrid.photoColumns(sizeClass, size: .small).count > AdaptiveGrid.photoColumns(sizeClass, size: .medium).count)
            #expect(AdaptiveGrid.photoColumns(sizeClass, size: .medium).count > AdaptiveGrid.photoColumns(sizeClass, size: .large).count)
            #expect(AdaptiveGrid.cardColumns(sizeClass, size: .small).count > AdaptiveGrid.cardColumns(sizeClass, size: .medium).count)
            #expect(AdaptiveGrid.cardColumns(sizeClass, size: .medium).count > AdaptiveGrid.cardColumns(sizeClass, size: .large).count)
        }
    }

    /// A zero-column grid draws nothing, and a one-column photo grid on an iPad is a poster.
    @Test func `every combination leaves at least one column`() {
        for sizeClass: UserInterfaceSizeClass? in [.regular, .compact, nil] {
            for size in GridSizeMode.allCases {
                #expect(AdaptiveGrid.photoColumns(sizeClass, size: size).count >= 1)
                #expect(AdaptiveGrid.cardColumns(sizeClass, size: size).count >= 1)
            }
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
