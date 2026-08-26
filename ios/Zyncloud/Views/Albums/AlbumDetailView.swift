import AVKit
import PhotosUI
import SwiftUI

/// How an album's photos are laid out.
enum AlbumLayoutMode: String, CaseIterable, Identifiable {
    /// One flat grid in the album's own order.
    case grid

    /// The same photos shelved by the day they were taken and the place they were taken at.
    case days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "Grid"
        case .days: "By Day & Place"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .days: "calendar"
        }
    }
}

struct AlbumDetailView: View {
    let album: Album
    @StateObject private var viewModel: AlbumDetailViewModel

    /// Called after the album is deleted on the server, so the list behind this screen can drop
    /// it. Without it the album would still be on the grid the pop lands back on.
    private let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(album: Album, onDeleted: @escaping () -> Void = {}) {
        self.album = album
        self.onDeleted = onDeleted
        _viewModel = StateObject(wrappedValue: AlbumDetailViewModel(album: album))
    }

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

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

    /// True while Delete Album waits for a yes. Deleting an album takes its photos with it, so
    /// it always asks first — same as the web app.
    @State private var confirmingAlbumDelete = false

    /// The photo whose tag list is open, if any. Held as the photo rather than a flag because
    /// the sheet needs to know which one it is editing.
    @State private var taggingPhoto: Photo?

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

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.uploadsInFlight > 0 {
                uploadBanner
            }

            if viewModel.isArrangingByHand {
                arrangeByHandList
            } else if layoutMode == .days {
                daysGallery
            } else {
                photoGrid
            }

            if viewModel.isSelecting {
                selectionBar
            }
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.isSelecting {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { viewModel.endSelecting() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(allPhotosPicked ? "Clear" : "Select All") {
                        if allPhotosPicked {
                            viewModel.selectedPhotoIds = []
                        } else {
                            viewModel.selectAllPhotos()
                        }
                    }
                    .disabled(viewModel.photos.isEmpty)
                }
            } else {
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
        .sheet(item: $sharingLink) { link in
            ShareSheet(items: [link.url])
        }
        .sheet(item: $taggingPhoto) { photo in
            PhotoTagsView(photo: photo, viewModel: viewModel)
        }
        .sheet(isPresented: $isBulkTagPresented) {
            BulkTagView(viewModel: viewModel)
        }
        .sheet(isPresented: $isAlbumTagsPresented) {
            NavigationView {
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
        .alert(item: $viewModel.alertState) { alertState in
            Alert(
                title: Text(alertState.title),
                message: Text(alertState.message),
            )
        }
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

    /// What the picked photos can be done to. Only tagging for now, which is why it is a plain
    /// bar rather than a menu.
    private var selectionBar: some View {
        HStack {
            Text(viewModel.selectedPhotoIds.count == 1
                ? "1 photo picked"
                : "\(viewModel.selectedPhotoIds.count) photos picked")
                .font(.footnote)
                .foregroundColor(.secondary)

            Spacer()

            Button {
                isBulkTagPresented = true
            } label: {
                Label("Tag", systemImage: "tag")
            }
            .disabled(viewModel.selectedPhotoIds.isEmpty || viewModel.isApplyingTags)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    // MARK: - Album Menu

    /// Share and Delete, the two album-wide actions the web app has. Share hands the public link
    /// to the system share sheet; a missing token only hides the entry, because a link cannot be
    /// invented on the phone.
    private var albumMenu: some View {
        Menu {
            Picker("View", selection: $layoutMode) {
                ForEach(AlbumLayoutMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.inline)

            Toggle(isOn: $showsTags) {
                Label("Show Tags", systemImage: "tag")
            }

            Divider()

            Button {
                viewModel.beginSelecting()
            } label: {
                Label("Select Photos", systemImage: "checkmark.circle")
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
            showsTags: showsTags,
            onDelete: { pendingDelete = photo },
            onTag: { taggingPhoto = photo },
        )
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

            if showsTags, !photo.visibleTags.isEmpty, photo.isThumbnailReady {
                VStack {
                    Spacer()
                    HStack {
                        PhotoTagChips(tags: photo.visibleTags)
                        Spacer()
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
                )
            }
        }
        .sheet(isPresented: $showingFullImage) {
            PhotoDetailView(openedWith: photo, viewModel: viewModel)
        }
    }
}

private extension PhotoThumbnailView {
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

    var body: some View {
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

// MARK: - Photo Detail View

struct PhotoDetailView: View {
    /// The photo as it was when the sheet opened. A rotate replaces it with a new `publicToken`,
    /// so what is actually rendered is ``photo`` — this is only the identity to look it up by,
    /// and the fallback for the moment between a delete and the dismiss.
    let openedWith: Photo

    /// Observed, unlike in the grid: the sheet is the one place a photo can be rotated while
    /// being looked at, and it has to show the result.
    @ObservedObject var viewModel: AlbumDetailViewModel

    private var photo: Photo {
        viewModel.photos.first { $0.id == openedWith.id } ?? openedWith
    }

    @Environment(\.dismiss) private var dismiss

    /// The sheet runs its own confirmation rather than borrowing the album screen's: a dialog
    /// presented behind a sheet never reaches the user.
    @State private var confirmingDelete = false

    /// True while this photo's tag list is up, stacked on top of this sheet.
    @State private var isTagging = false

    /// Owned by the view so the sheet keeps one player across body re-evaluations; the item is
    /// attached in `onAppear` because `photo` is not available at initialiser time here.
    @StateObject private var playerBox = PlayerBox()
    private var player: AVPlayer {
        playerBox.player
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if !photo.isThumbnailReady {
                    ProcessingPlaceholder(
                        label: photo.processingFailed
                            ? "The server could not process this file."
                            : "Processing on the server…",
                        isFailure: photo.processingFailed,
                    )
                } else if photo.isVideo, let videoURL = viewModel.videoURL(for: photo) {
                    // A video must be played, not decoded. AVPlayer streams it; feeding the
                    // same bytes to AuthenticatedImage is what used to render "Failed".
                    VideoPlayer(player: player)
                        .onAppear {
                            if player.currentItem == nil {
                                player.replaceCurrentItem(with: AVPlayerItem(url: videoURL))
                            }
                            // Without .playback the ring/silent switch silences the video.
                            //
                            // Off the main thread, and awaited before `play()` — see
                            // ``AudioSessionConfigurator``. This is `onAppear` on the video
                            // screen, so doing it inline froze the screen for as long as the
                            // audio route took to come up.
                            Task {
                                try? await AudioSessionConfigurator.activate(category: .playback)
                                player.play()
                            }
                        }
                        .onDisappear { player.pause() }
                } else if let imageURL = viewModel.fullImageURL(for: photo) {
                    AuthenticatedImage(url: imageURL)
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack {
                        Image(systemName: "photo")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                        Text("Image not available")
                            .foregroundColor(.white)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Only drawn when there is something to say, so a photo with no tags keeps the
                // whole screen for the picture.
                if !photo.visibleTags.isEmpty {
                    tagBar
                }
            }
            .navigationTitle(photo.filename ?? photo.originalName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        PhotoActionButtons(
                            photo: photo,
                            viewModel: viewModel,
                            onDelete: { confirmingDelete = true },
                            onTag: { isTagging = true },
                        )
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $isTagging) {
                PhotoTagsView(photo: photo, viewModel: viewModel)
            }
            .confirmationDialog(
                "Delete photo",
                isPresented: $confirmingDelete,
                titleVisibility: .visible,
            ) {
                Button("Delete", role: .destructive) {
                    // Dismissed straight away: the photo it is showing is about to stop
                    // existing, and the grid behind has already dropped it.
                    viewModel.delete(photo)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the photo from your server for good. It cannot be undone.")
            }
        }
    }
}

private extension PhotoDetailView {
    /// Every tag on this photo, spelled out. The grid tile only has room for two, so this is
    /// where the full list is readable — and it scrolls sideways rather than wrapping, because
    /// a growing strip would push the picture around.
    var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(photo.visibleTags, id: \.self) { tag in
                    Text(tag)
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.18), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }
}

/// Keeps one `AVPlayer` alive for a `PhotoDetailView`. `@StateObject` needs a reference type,
/// and `AVPlayer` is not `ObservableObject`, so it is wrapped rather than held directly.
final class PlayerBox: ObservableObject {
    let player = AVPlayer()
}

// Note: AuthenticatedImage is now implemented in Utils/AuthenticatedImageLoader.swift
