import PhotosUI
import SwiftUI

/// How an album's photos are laid out.
enum AlbumLayoutMode: String, CaseIterable, Identifiable {
    /// One flat grid in the album's own order.
    case grid

    /// The same photos shelved by the day they were taken and the place they were taken at.
    case days

    /// The album's located photos as pins on Apple Maps. Only offered when the album has one —
    /// see ``AlbumDetailViewModel/hasLocatedPhotos``.
    case map

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .grid: "Grid"
        case .days: "By Day & Place"
        case .map: "Map"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .days: "calendar"
        case .map: "map"
        }
    }
}

struct AlbumDetailView: View {
    let album: Album
    @StateObject private var viewModel: AlbumDetailViewModel

    /// Called after the album is deleted on the server, so the list behind this screen can drop
    /// it. Without it the album would still be on the grid the pop lands back on.
    private let onDeleted: () -> Void

    /// Called with the server's album after a publish or unpublish, so the list behind this
    /// screen shows the new label. The list pushed a value, so it cannot see the change itself.
    private let onChanged: (Album) -> Void

    @Environment(\.dismiss) private var dismiss

    init(album: Album, onDeleted: @escaping () -> Void = {}, onChanged: @escaping (Album) -> Void = { _ in }) {
        self.album = album
        self.onDeleted = onDeleted
        self.onChanged = onChanged
        _viewModel = StateObject(wrappedValue: AlbumDetailViewModel(album: album))
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// How big the thumbnails are drawn. A reading preference like ``layoutMode``, and stored
    /// the same way, under its own key: the album shelf keeps a separate one.
    @AppStorage("photoGridSize") private var gridSize: GridSizeMode = .medium

    private var columns: [GridItem] {
        AdaptiveGrid.photoColumns(horizontalSizeClass, size: gridSize)
    }

    /// Flat grid, or day-and-place sections. Kept in app storage rather than on the view model
    /// because it is a reading preference, not a fact about this album — whichever way the user
    /// last looked at one album is how the next one opens.
    @AppStorage("albumLayoutMode") private var layoutMode: AlbumLayoutMode = .grid

    /// Whether tag names ride along on the tiles. Also a reading preference.
    @AppStorage("albumShowsTags") private var showsTags: Bool = true

    /// Names for the place headings. A shared store, so a place named once is named everywhere.
    @ObservedObject private var regionNames = RegionNameStore.shared

    /// Photos chosen in the system picker, cleared as soon as they are handed to the uploader.
    @State private var pickedItems: [PhotosPickerItem] = []

    /// Set when Delete was chosen on a tile but not yet confirmed. Deleting is irreversible —
    /// the server drops the stored file, not just the row — so it always asks first.
    @State private var pendingDelete: Photo?

    /// The link handed to the system share sheet, set by the menu's Share entry.
    @State private var sharingLink: ShareableLink?

    /// True while the audio-commentary screen is up.
    ///
    /// Presented as a sheet rather than pushed: this is opened from a `Menu`, and a
    /// `NavigationLink` inside menu content never pushes — the menu closes and nothing happens.
    @State private var isNarrationPresented = false

    /// True while the presentation — the album read the way a share-link visitor reads it — owns
    /// the screen. A full-screen cover rather than a sheet: a presentation the album is still
    /// visible behind is not one.
    @State private var isPresentationPresented = false

    /// True while Delete Album waits for a yes. Deleting an album takes its photos with it, so
    /// it always asks first — same as the web app.
    @State private var confirmingAlbumDelete = false

    /// Set when Delete was tapped in the selection bar. Held here rather than in the bar
    /// so the dialog outlives a re-draw of the bar under it.
    @State private var confirmingSelectionDelete = false

    /// The photo whose tag list is open, if any. Held as the photo rather than a flag because
    /// the sheet needs to know which one it is editing.
    @State private var taggingPhoto: Photo?

    /// The photo whose caption is being written, or nil. Raised to this screen for the same
    /// reason as `taggingPhoto`: the sheet has to outlive the grid cell it was opened from.
    @State private var captioningPhoto: Photo?

    /// True while the tag sheet for the picked photos is up.
    @State private var isBulkTagPresented = false

    /// True while the album's accepted-tag list is up. Opened from the album menu; the two tag
    /// sheets reach the same screen by pushing it instead.
    @State private var isAlbumTagsPresented = false

    /// Set when a Sort menu item was picked but not yet confirmed. The web app puts the same
    /// warning behind these two actions because they rewrite the order of the whole album.
    @State private var pendingSort: AlbumSortAction?

    private var sortConfirmationShown: Binding<Bool> {
        Binding(
            get: { pendingSort != nil },
            set: { shown in
                if !shown {
                    pendingSort = nil
                }
            },
        )
    }

    /// The screen itself: an optional banner, one of the four galleries, an optional
    /// selection bar.
    ///
    /// Split out of ``body`` rather than left inline, and it has to stay split: with this
    /// stack and the modifier chain below it in one expression the type checker gives up —
    /// "unable to type-check this expression in reasonable time" — and the whole target
    /// stops building. Nothing about the view itself changed in the split.
    private var content: some View {
        VStack(spacing: 0) {
            if viewModel.uploadsInFlight > 0 {
                uploadBanner
            }

            if viewModel.isArrangingByHand {
                arrangeByHandList
            } else if layoutMode == .days {
                daysGallery
            } else if layoutMode == .map, viewModel.hasLocatedPhotos {
                albumMap
            } else {
                photoGrid
            }

            if viewModel.isSelecting {
                selectionBar
            }
        }
    }

    var body: some View {
        content
            .navigationTitle(album.name)
            .navigationBarTitleDisplayMode(.inline)
            // The tab bar and the selection bar would otherwise stack up two rows deep at the
            // bottom, and the tabs lead away from a selection that would be thrown away on the way
            // out. So while picking, the bottom of the screen belongs to the selection bar alone.
            .toolbar(viewModel.isSelecting ? .hidden : .visible, for: .tabBar)
            .toolbar {
                if viewModel.isSelecting {
                    // On the right, where the Select button that opened this mode was — and away
                    // from the back arrow, which it sat next to and read as a second way out.
                    ToolbarItem(placement: .navigationBarTrailing) {
                        // "Done", not "Cancel": leaving selection mode keeps every edit already
                        // applied, so there is nothing here to take back.
                        Button("Done") { viewModel.endSelecting() }
                            .disabled(viewModel.isBulkWorking)
                    }
                } else {
                    // Top-level rather than buried in the album menu, because this is the one
                    // entry point for every multi-photo action and iPhone users look for a
                    // "Select" here first. The long press on a tile reaches the same mode.
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Select") { viewModel.beginSelecting() }
                            .disabled(!canSelectPhotos)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(
                            action: { viewModel.requestUpload() },
                            label: { Image(systemName: "plus") },
                        )
                        .disabled(viewModel.isArrangingByHand)
                        .accessibilityLabel("Upload photos")
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        sortMenu
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(
                            action: { viewModel.reloadPhotosAndImages() },
                            label: { Image(systemName: "arrow.clockwise") },
                        )
                        .disabled(viewModel.isLoading || viewModel.isArrangingByHand)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        albumMenu
                    }
                }
            }
            // `photoLibrary: .shared()` is load-bearing, not a default: without it the picker runs
            // out of process and the returned items carry no `itemIdentifier`, which is the only
            // way back to the PHAsset the uploader needs.
            .photosPicker(
                isPresented: $viewModel.isPickerPresented,
                selection: $pickedItems,
                maxSelectionCount: nil,
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared(),
            )
            .onChange(of: viewModel.revisedAlbum) { _, revised in
                guard let revised else { return }
                onChanged(revised)
            }
            .onChange(of: pickedItems) { _, items in
                guard !items.isEmpty else { return }
                viewModel.upload(
                    assetIdentifiers: items.compactMap(\.itemIdentifier),
                    pickedCount: items.count,
                )
                pickedItems = []
            }
            .confirmationDialog(
                "Delete photo",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { shown in
                        if !shown {
                            pendingDelete = nil
                        }
                    },
                ),
                titleVisibility: .visible,
                presenting: pendingDelete,
            ) { photo in
                Button("Delete", role: .destructive) {
                    pendingDelete = nil
                    viewModel.delete(photo)
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { _ in
                Text("This removes the photo from your server for good. It cannot be undone.")
            }
            .confirmationDialog(
                viewModel.selectedPhotoIds.count == 1
                    ? "Delete 1 photo"
                    : "Delete \(viewModel.selectedPhotoIds.count) photos",
                isPresented: $confirmingSelectionDelete,
                titleVisibility: .visible,
            ) {
                Button("Delete", role: .destructive) { viewModel.deleteSelection() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes them from your server for good. It cannot be undone.")
            }
            .sheet(item: $sharingLink) { link in
                ShareSheet(items: [link.url])
            }
            .sheet(item: $taggingPhoto) { photo in
                PhotoTagsView(photo: photo, viewModel: viewModel)
            }
            .sheet(item: $captioningPhoto) { photo in
                PhotoCaptionView(photo: photo, viewModel: viewModel)
            }
            .sheet(isPresented: $isBulkTagPresented) {
                BulkTagView(viewModel: viewModel)
            }
            .sheet(isPresented: $isAlbumTagsPresented) {
                NavigationStack {
                    AlbumTagsSettingsView(viewModel: viewModel)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { isAlbumTagsPresented = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $isNarrationPresented) {
                NarrationSetupView(album: album)
            }
            .fullScreenCover(isPresented: $isPresentationPresented) {
                PresentationView(album: album)
            }
            .confirmationDialog(
                "Delete album",
                isPresented: $confirmingAlbumDelete,
                titleVisibility: .visible,
            ) {
                Button("Delete", role: .destructive) {
                    viewModel.deleteAlbum { deleted in
                        if deleted {
                            onDeleted()
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes '\(album.name)' and every photo in it for good. It cannot be undone.")
            }
            .confirmationDialog(
                "Reorder album",
                isPresented: sortConfirmationShown,
                titleVisibility: .visible,
                presenting: pendingSort,
            ) { action in
                Button("Reorder") {
                    pendingSort = nil
                    viewModel.reorder(by: action)
                }
                Button("Cancel", role: .cancel) { pendingSort = nil }
            } message: { action in
                Text(action.confirmationMessage)
            }
            .alert(state: $viewModel.alertState)
            .onAppear {
                if viewModel.photos.isEmpty {
                    viewModel.fetchPhotos()
                } else {
                    // Coming back to a screen that already has its list: anything the worker was
                    // still busy with when we left needs watching again.
                    viewModel.startProcessingPollingIfNeeded()
                }
            }
            .onDisappear {
                viewModel.stopProcessingPolling()
            }
    }

    // MARK: - Upload Banner

    /// Uploads keep running on a background session after this screen closes, so the banner
    /// says what is outstanding rather than pretending to be a blocking progress bar.
    private var uploadBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(viewModel.uploadsInFlight == 1
                ? "Uploading 1 photo…"
                : "Uploading \(viewModel.uploadsInFlight) photos…")
                .font(.footnote)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    // MARK: - Selection Bar

    /// True when every photo in the album is picked. Also what turns the whole-album shortcut
    /// on in the view model, so the label has to agree with it.
    private var allPhotosPicked: Bool {
        !viewModel.photos.isEmpty && viewModel.selectedPhotoIds.count == viewModel.photos.count
    }

    /// Picking works by tapping tiles, and the map has no tiles — it draws pins. So Select is
    /// off there rather than opening a mode with nothing to tap.
    private var canSelectPhotos: Bool {
        !viewModel.photos.isEmpty
            && !viewModel.isArrangingByHand
            && !(layoutMode == .map && viewModel.hasLocatedPhotos)
    }

    private var selectionCountLabel: String {
        if viewModel.isBulkWorking {
            return "Working…"
        }

        switch viewModel.selectedPhotoIds.count {
        case 0: return "Select photos to tag, rotate or delete"
        case 1: return "1 photo selected"
        case let count: return "\(count) photos selected"
        }
    }

    /// Everything the picked photos can be done to, in one place at the bottom of the screen —
    /// including Select All, which used to sit in the top bar and made the eye jump between two
    /// corners for one job.
    ///
    /// The three actions mirror the single-photo long-press menu on purpose: a mode for many
    /// photos that could do less than one photo alone was the reason this screen felt wrong.
    private var selectionBar: some View {
        VStack(spacing: 8) {
            Text(selectionCountLabel)
                .font(.footnote)
                .foregroundColor(.secondary)

            HStack(spacing: 0) {
                selectionAction(
                    title: allPhotosPicked ? "Clear" : "All",
                    systemImage: allPhotosPicked ? "xmark.circle" : "checklist",
                    isEnabled: !viewModel.photos.isEmpty && !viewModel.isBulkWorking,
                ) {
                    if allPhotosPicked {
                        viewModel.selectedPhotoIds = []
                    } else {
                        viewModel.selectAllPhotos()
                    }
                }

                selectionAction(
                    title: "Tag",
                    systemImage: "tag",
                    isEnabled: hasSelection && !viewModel.isApplyingTags && !viewModel.isBulkWorking,
                ) {
                    isBulkTagPresented = true
                }

                selectionAction(
                    title: "Rotate",
                    systemImage: "rotate.left",
                    isEnabled: viewModel.selectionHasRotatablePhoto && !viewModel.isBulkWorking,
                ) {
                    viewModel.rotateSelection()
                }

                selectionAction(
                    title: "Delete",
                    systemImage: "trash",
                    isEnabled: hasSelection && !viewModel.isBulkWorking,
                    isDestructive: true,
                ) {
                    confirmingSelectionDelete = true
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.thinMaterial)
    }

    private var hasSelection: Bool {
        !viewModel.selectedPhotoIds.isEmpty
    }

    /// One bar button: icon over label, each taking an equal share of the width so the row
    /// stays even whatever the labels say.
    private func selectionAction(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        isDestructive: Bool = false,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 19))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .foregroundColor(isDestructive ? .red : .accentColor)
        .disabled(!isEnabled)
    }

    // MARK: - Album Menu

    /// The album-wide actions: how to look at it, Present, the tag and commentary screens, then
    /// publishing, Share and Delete. Share hands the public link to the system share sheet; it is
    /// hidden when the album is unpublished or has no token, because in both cases there is no
    /// working link and one cannot be invented on the phone.
    private var albumMenu: some View {
        Menu {
            Picker("View", selection: $layoutMode) {
                ForEach(availableLayoutModes) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.inline)

            GridSizePicker(size: $gridSize)

            Toggle(isOn: $showsTags) {
                Label("Show Tags", systemImage: "tag")
            }

            Divider()

            Button {
                isPresentationPresented = true
            } label: {
                Label("Present", systemImage: "play.rectangle")
            }
            .disabled(viewModel.photos.isEmpty)

            Button {
                isAlbumTagsPresented = true
            } label: {
                Label("Album Tags", systemImage: "tag")
            }

            Button {
                isNarrationPresented = true
            } label: {
                Label("Audio Commentary", systemImage: "mic")
            }

            Divider()

            // The switch that decides whether Share does anything: an unpublished album's link
            // answers 404 and its subscribers get no mail.
            Button {
                viewModel.setPublished(!viewModel.isPublished)
            } label: {
                viewModel.isPublished
                    ? Label("Make Private", systemImage: "eye.slash")
                    : Label("Make Public", systemImage: "eye")
            }

            if let shareURL = viewModel.shareURL {
                Button {
                    sharingLink = ShareableLink(url: shareURL)
                } label: {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
            }

            Button(role: .destructive) {
                confirmingAlbumDelete = true
            } label: {
                Label("Delete Album", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .disabled(viewModel.isArrangingByHand)
        .accessibilityLabel("Album actions")
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            Section("Reorder every photo by") {
                ForEach(AlbumSortAction.allCases) { action in
                    Button(action.title) { pendingSort = action }
                }
            }

            Divider()

            Button {
                viewModel.toggleArrangeByHand()
            } label: {
                Label(
                    viewModel.isArrangingByHand ? "Stop arranging by hand" : "Arrange by hand",
                    systemImage: viewModel.isArrangingByHand ? "checkmark" : "hand.draw",
                )
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .disabled(viewModel.photos.isEmpty || viewModel.isReordering)
    }

    // MARK: - Grid

    private var photoGrid: some View {
        ScrollView {
            if viewModel.isLoading, viewModel.photos.isEmpty {
                ProgressView("Loading photos...")
                    .padding()
            } else if viewModel.photos.isEmpty {
                emptyStateView
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(viewModel.photos) { photo in
                        photoTile(for: photo)
                    }
                }
            }
        }
        .gridZoom($gridSize)
        .refreshable {
            await viewModel.reloadPhotosAndImagesAwaiting()
        }
    }

    /// One tile, built in one place so the flat grid and the day sections cannot drift apart.
    private func photoTile(for photo: Photo) -> some View {
        PhotoThumbnailView(
            photo: photo,
            viewModel: viewModel,
            reloadToken: viewModel.imageReloadToken,
            isRotating: viewModel.rotatingPhotoIds.contains(photo.id),
            isSelecting: viewModel.isSelecting,
            isSelected: viewModel.selectedPhotoIds.contains(photo.id),
            // Chips are dropped at the smallest step whatever the toggle says: five tiles across
            // a phone leaves a tag name about a centimetre wide, which is clutter rather than
            // information. The toggle still governs the two sizes where they can be read.
            showsTags: showsTags && gridSize != .small,
            onDelete: { pendingDelete = photo },
            onTag: { taggingPhoto = photo },
            onCaption: { captioningPhoto = photo },
            onBeginSelecting: { viewModel.beginSelecting(with: photo) },
        )
    }

    // MARK: - Map

    /// The album's located photos as pins.
    ///
    /// The layout is a reading preference kept in app storage, so it follows the user from album
    /// to album — and an album with no located photo would open on an empty map with no Map entry
    /// left in the picker to escape from. Hence the `hasLocatedPhotos` guard at the call site,
    /// which mirrors the web gallery's watcher on `mapFilterAvailable`.
    private var albumMap: some View {
        AlbumMapView(
            photos: viewModel.photos,
            savedView: viewModel.savedMapView,
            canEditView: true,
            onSaveView: { viewModel.saveMapView($0) },
            onClearView: { viewModel.clearMapView() },
        )
    }

    /// Map is offered only when there is something to put on it. Grid and By Day & Place always
    /// work — a photo with no date or place still has a trailing bucket to sit in.
    private var availableLayoutModes: [AlbumLayoutMode] {
        AlbumLayoutMode.allCases.filter { $0 != .map || viewModel.hasLocatedPhotos }
    }

    // MARK: - By Day & Place

    /// The same photos, re-shelved: a section per calendar day, and inside it one heading per
    /// place. The day headers stick to the top while scrolling, which is how iOS lists behave
    /// and how the day being looked at stays named.
    ///
    /// The album's own order is kept throughout — this changes how the photos are shelved, not
    /// what order they are in.
    private var daysGallery: some View {
        ScrollView {
            if viewModel.isLoading, viewModel.photos.isEmpty {
                ProgressView("Loading photos...")
                    .padding()
            } else if viewModel.photos.isEmpty {
                emptyStateView
            } else {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    ForEach(viewModel.dayGroups) { day in
                        Section {
                            ForEach(day.clusters) { cluster in
                                regionSection(cluster)
                            }
                        } header: {
                            dayHeader(day)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
        // The day sections draw the same tiles from the same `columns`, so the pinch has to work
        // here too — a gesture that only answers in one of two layouts reads as broken.
        .gridZoom($gridSize)
        .refreshable {
            await viewModel.reloadPhotosAndImagesAwaiting()
        }
    }

    private func dayHeader(_ day: DayGroup) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(formatDayLabel(day))
                .font(.headline)
            Spacer()
            Text(day.count == 1 ? "1 photo" : "\(day.count) photos")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func regionSection(_ cluster: RegionCluster) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: cluster.located ? "mappin.and.ellipse" : "mappin.slash")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(regionTitle(cluster))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if cluster.located, cluster.spreadMeters > 0 {
                    Text("· \(formatDistance(cluster.spreadMeters)) across")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(cluster.photos.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(cluster.photos) { photo in
                    photoTile(for: photo)
                }
            }
        }
    }

    /// The place name once the server has one, its coordinates until then, and a plain words
    /// heading for the bucket of photos that carry no location at all.
    private func regionTitle(_ cluster: RegionCluster) -> String {
        guard let center = cluster.center else { return "No place recorded" }
        return regionNames.label(for: center)
    }

    // MARK: - Arrange By Hand

    /// A grid cannot be dragged into order reliably, so hand-arranging switches to a `List` in
    /// permanent edit mode — the standard iOS way to move rows. Every move is saved at once.
    private var arrangeByHandList: some View {
        List {
            Section {
                ForEach(viewModel.photos) { photo in
                    PhotoArrangeRow(photo: photo, viewModel: viewModel)
                }
                .onMove { source, destination in
                    viewModel.movePhotos(from: source, to: destination)
                }
            } header: {
                Text("Drag the handles to set the order. Changes are saved right away.")
                    .textCase(nil)
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Photos")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This album doesn't have any photos yet.\nStart syncing photos to this album from the Sync Options tab.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Photo Arrange Row

/// One movable row of the hand-arrange list: the thumbnail plus the name, enough to tell the
/// photos apart while dragging.
struct PhotoArrangeRow: View {
    let photo: Photo
    let viewModel: AlbumDetailViewModel

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Rectangle().fill(Color.black)

                if let thumbnailURL = viewModel.thumbnailURL(for: photo) {
                    AuthenticatedImage(url: thumbnailURL)
                        .scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundColor(.gray)
                }

                if photo.isVideo {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
            }
            .frame(width: 44, height: 44)
            .clipped()
            .cornerRadius(4)

            Text(photo.filename ?? photo.originalName)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Photo Thumbnail View

struct PhotoThumbnailView: View {
    let photo: Photo
    let viewModel: AlbumDetailViewModel

    /// Passed down rather than read off the view model, which is held here as a plain `let`
    /// and so does not re-render this cell on its own.
    let reloadToken: Int

    /// Also passed down, and for the same reason: a rotate is the view model's state, and this
    /// cell does not observe it.
    let isRotating: Bool

    /// While on, a tap picks this photo instead of opening it, and the long-press menu is off —
    /// a menu of single-photo actions has no meaning mid-selection.
    let isSelecting: Bool

    let isSelected: Bool

    /// Whether the tag names ride along the bottom of the tile.
    let showsTags: Bool

    /// Raised to the album screen, which owns the confirmation dialog — a dialog presented from
    /// inside a grid cell would go away with the cell.
    let onDelete: () -> Void

    /// Also raised: the tag sheet outlives the cell being re-made under it.
    let onTag: () -> Void

    /// Raised for the same reason as ``onTag`` — the caption sheet outlives this cell.
    let onCaption: () -> Void

    /// Long-press entry into picking, with this photo already picked. The second way in, next
    /// to the Select button in the top bar — it is the gesture iPhone users try first.
    let onBeginSelecting: () -> Void

    @State private var showingFullImage = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black)

            if !photo.isThumbnailReady {
                // Do not even ask for the picture: the server answers 202 with nothing until
                // the worker has made the thumbnail, and a freshly uploaded photo spends its
                // first seconds here. Asking anyway is what used to show "Failed".
                ProcessingPlaceholder(
                    label: photo.processingFailed ? "Failed" : "Processing…",
                    isFailure: photo.processingFailed,
                )
            } else if let thumbnailURL = viewModel.thumbnailURL(for: photo) {
                AuthenticatedImage(url: thumbnailURL, reloadToken: reloadToken)
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.gray)
            }

            if photo.isVideo, photo.isThumbnailReady {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .shadow(radius: 3)
            }

            if isRotating {
                Color.black.opacity(0.55)
                ProgressView()
                    .tint(.white)
            }

            if photo.isThumbnailReady, showsTags || hasCaption {
                VStack(spacing: 4) {
                    Spacer()

                    // The caption sits above the chips: it is a sentence, and a sentence
                    // reads badly wedged under a row of one-word pills.
                    if let caption = photo.caption, !caption.isEmpty {
                        captionStrip(caption)
                    }

                    if showsTags, !photo.tags.isEmpty {
                        HStack {
                            PhotoTagChips(tags: photo.tags)
                            Spacer()
                        }
                    }
                }
                .padding(4)
            }

            if isSelecting {
                selectionOverlay
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .clipped()
        .onTapGesture {
            if isSelecting {
                viewModel.toggleSelection(of: photo)
            } else {
                showingFullImage = true
            }
        }
        .contextMenu {
            if !isSelecting {
                PhotoActionButtons(
                    photo: photo,
                    viewModel: viewModel,
                    onDelete: onDelete,
                    onTag: onTag,
                    onCaption: onCaption,
                )

                Divider()

                Button(action: onBeginSelecting) {
                    Label("Select…", systemImage: "checkmark.circle")
                }
            }
        }
        .sheet(isPresented: $showingFullImage) {
            PhotoDetailView(openedWith: photo, viewModel: viewModel)
        }
    }
}

private extension PhotoThumbnailView {
    var hasCaption: Bool {
        !(photo.caption ?? "").isEmpty
    }

    /// The caption over the bottom of the tile (D69). Two lines at most: a tile is square and
    /// fixed, so a long caption has to be cut rather than allowed to cover the picture.
    func captionStrip(_ caption: String) -> some View {
        Text(caption)
            .font(.caption2)
            .foregroundColor(.white)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    /// Dims the tile and puts a tick in the corner. Drawn over the picture rather than beside
    /// it because the grid has no room for a second column.
    var selectionOverlay: some View {
        ZStack {
            Color.black.opacity(isSelected ? 0.35 : 0.0)

            VStack {
                HStack {
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isSelected ? .accentColor : .white)
                        .shadow(radius: 2)
                }
                Spacer()
            }
            .padding(6)
        }
    }
}

// MARK: - Photo Action Buttons

/// Tags, Rotate and Delete, shared by the grid's long-press menu and the full-screen view's
/// menu so the two cannot drift apart. Delete only *asks* — the owner of the surrounding screen
/// runs the confirmation, because that is where a dialog can outlive the thing being deleted.
/// Tags is raised for the same reason: the sheet must outlive the cell.
struct PhotoActionButtons: View {
    let photo: Photo
    let viewModel: AlbumDetailViewModel
    let onDelete: () -> Void
    let onTag: () -> Void
    let onCaption: () -> Void

    var body: some View {
        Button(action: onCaption) {
            Label(
                (photo.caption ?? "").isEmpty ? "Add Caption" : "Edit Caption",
                systemImage: "text.bubble",
            )
        }

        Button(action: onTag) {
            Label("Tags", systemImage: "tag")
        }

        if !photo.isVideo {
            Button {
                viewModel.rotate(photo)
            } label: {
                Label("Rotate Left", systemImage: "rotate.left")
            }
        }

        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
        }
    }
}
