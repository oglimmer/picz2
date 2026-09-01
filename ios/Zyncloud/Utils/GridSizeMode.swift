import SwiftUI

/// How big the tiles are on a grid screen, as three named steps.
///
/// The web app puts the same three-way switch above the album shelf and above an album's photos.
/// The choice is per screen there, and it is per screen here too: how someone likes to browse a
/// list of albums is not how they like to browse the photos inside one.
///
/// ``medium`` is what both grids have always drawn, so it is the default everywhere and an
/// existing install opens on exactly the layout it had before this control existed.
enum GridSizeMode: String, CaseIterable, Identifiable {
    /// More tiles, each smaller — a contact sheet.
    case small

    /// The long-standing layout.
    case medium

    /// Fewer tiles, each bigger.
    case large

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// A picture of the layout the row chooses, the way the web app's three icons are.
    var systemImage: String {
        switch self {
        case .small: "square.grid.3x3"
        case .medium: "square.grid.2x2"
        case .large: "square"
        }
    }

    /// The next step towards bigger tiles, or towards smaller ones.
    ///
    /// `nil` at either end rather than clamping to `self`: the pinch gesture needs to tell "the
    /// size changed" from "there is nowhere further to go", so that a pinch past the last step
    /// neither latches the gesture nor fires feedback for a move that did not happen.
    func next(zoomingIn: Bool) -> GridSizeMode? {
        switch (self, zoomingIn) {
        case (.small, true): .medium
        case (.medium, true): .large
        case (.large, false): .medium
        case (.medium, false): .small
        default: nil
        }
    }
}

/// The three sizes as menu rows.
///
/// Shipped as an inline `Picker` rather than a segmented control: on both screens this lives
/// inside a toolbar `Menu`, which is where iOS puts view options — Files and Photos both do it
/// this way — and an inline picker there draws the familiar list with a tick on the current row.
struct GridSizePicker: View {
    @Binding var size: GridSizeMode

    var body: some View {
        // `.animation` on the binding, not on the grid: the resize is worth animating wherever
        // it is triggered from, and the grids that read this value are spread over two screens.
        Picker("Thumbnail Size", selection: $size.animation(.snappy)) {
            ForEach(GridSizeMode.allCases) { mode in
                Label(mode.title, systemImage: mode.systemImage).tag(mode)
            }
        }
        .pickerStyle(.inline)
    }
}
