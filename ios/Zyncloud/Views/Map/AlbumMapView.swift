import Combine
import SwiftUI

/// Holds the map's live framing.
///
/// The framing itself is deliberately **not** published: it is only read when the owner presses
/// Save, and `MKMapView` reports a new region throughout a pan — re-rendering the screen for each
/// of those would rebuild the pin list for nothing. Only the fact that a framing now exists is
/// published, and only once.
@MainActor
final class MapFramingBox: ObservableObject {
    /// Published exactly once, when the map first reports where it is. Without it the Save button
    /// would be born disabled and stay that way, since nothing else on this screen changes.
    @Published private(set) var hasFraming = false

    /// Set once the hop below has been booked, so a burst of region reports arriving before it
    /// runs books only the one.
    private var announcing = false

    var current: SavedMapView? {
        didSet {
            guard current != nil, !hasFraming, !announcing else { return }
            announcing = true
            // `MKMapView` reports its opening region from inside the same pass that placed it, and
            // publishing from within a view update is what SwiftUI warns about. One hop puts the
            // change after that pass instead of inside it.
            Task { @MainActor in
                self.hasFraming = true
            }
        }
    }
}

/// The album read as a map: one pin per place, tap a pin for the photos taken there.
///
/// A port of what `PhotoMap.vue` is wrapped in on the web. The photo strip is a sheet rather than
/// an overlay because a phone has no room to put a filmstrip over a map and still leave a map.
struct AlbumMapView: View {
    let photos: [Photo]

    /// The album's saved framing, or nil to fit every pin.
    let savedView: SavedMapView?

    /// Offers Save/Reset. The owner looking at their own album, not a presentation.
    var canEditView: Bool = false

    var onSaveView: (SavedMapView) -> Void = { _ in }
    var onClearView: () -> Void = {}

    @StateObject private var framing = MapFramingBox()

    /// Held as ids, not photos: the album is replaced wholesale by every reload, and a stored
    /// `Photo` would go stale where an id does not.
    @State private var selectedIDs: [Int] = []

    private var places: [PhotoPlace] {
        PhotoMapPlaces.places(from: photos)
    }

    private var selectedPhotos: [Photo] {
        selectedIDs.compactMap { id in photos.first { $0.id == id } }
    }

    var body: some View {
        Group {
            if places.isEmpty {
                emptyState
            } else {
                map
            }
        }
    }

    private var map: some View {
        PhotoMap(
            places: places,
            savedView: savedView,
            onSelect: { selectedIDs = $0 },
            onRegionChanged: { framing.current = $0 },
        )
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .topTrailing) {
            if canEditView {
                viewControls
            }
        }
        .sheet(isPresented: selectionShown) {
            PhotoPlaceSheet(photos: selectedPhotos)
                .presentationDetents([.height(190)])
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.hidden)
        }
    }

    /// Bound to the sheet so dismissing it also drops the map's selection — otherwise tapping the
    /// same pin again would do nothing, the selection never having been let go.
    private var selectionShown: Binding<Bool> {
        Binding(
            get: { !selectedIDs.isEmpty },
            set: { shown in
                if !shown {
                    selectedIDs = []
                }
            },
        )
    }

    /// Drag and pinch to the framing you want, then save it. No coordinate entry — the map itself
    /// is the better input.
    private var viewControls: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button {
                if let current = framing.current {
                    onSaveView(current)
                }
            } label: {
                Label("Save this view", systemImage: "mappin.and.ellipse")
                    .font(.footnote)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!framing.hasFraming)

            if savedView != nil {
                Button {
                    onClearView()
                } label: {
                    Text("Reset")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 44))
                .foregroundColor(.secondary)

            Text("No photos with a location")
                .font(.headline)

            Text("Only photos whose original still carries GPS data appear here.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - The photos at one pin

/// What was taken at the tapped place, as a strip. Tapping one opens it full screen.
struct PhotoPlaceSheet: View {
    let photos: [Photo]

    /// The photo opened from the strip, if any.
    @State private var opened: Photo?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(PhotoMapPlaces.title(forPhotoCount: photos.count) + " here")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos) { photo in
                        thumbnail(photo)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .fullScreenCover(item: $opened) { photo in
            // One place, one photo: the strip is the whole list, so the pager walks exactly the
            // photos taken here.
            PresentationPhotoView(
                photos: photos,
                sections: [PresentationSection(group: nil, photos: photos)],
                openedAt: photo,
            )
        }
    }

    private func thumbnail(_ photo: Photo) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black)

            if !photo.isThumbnailReady {
                ProcessingPlaceholder(
                    label: photo.processingFailed ? "Failed" : "Processing…",
                    isFailure: photo.processingFailed,
                )
            } else if let thumbnailURL = AssetURLs.thumbnail(for: photo) {
                AuthenticatedImage(url: thumbnailURL)
                    .scaledToFill()
            }

            if photo.isVideo, photo.isThumbnailReady {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.white)
                    .shadow(radius: 2)
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { opened = photo }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(photo.filename ?? photo.originalName)
    }
}
