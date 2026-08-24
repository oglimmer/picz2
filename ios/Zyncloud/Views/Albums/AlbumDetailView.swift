import AVKit
import PhotosUI
import SwiftUI

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

    /// Photos chosen in the system picker, cleared as soon as they are handed to the uploader.
    @State private var pickedItems: [PhotosPickerItem] = []

    /// Set when Delete was chosen on a tile but not yet confirmed. Deleting is irreversible —
    /// the server drops the stored file, not just the row — so it always asks first.
    @State private var pendingDelete: Photo?

    /// The link handed to the system share sheet, set by the menu's Share entry.
    @State private var sharingLink: ShareableLink?

    /// True while Delete Album waits for a yes. Deleting an album takes its photos with it, so
    /// it always asks first — same as the web app.
    @State private var confirmingAlbumDelete = false

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
            } else {
                photoGrid
            }
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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

    // MARK: - Album Menu

    /// Share and Delete, the two album-wide actions the web app has. Share hands the public link
    /// to the system share sheet; a missing token only hides the entry, because a link cannot be
    /// invented on the phone.
    private var albumMenu: some View {
        Menu {
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
                        PhotoThumbnailView(
                            photo: photo,
                            viewModel: viewModel,
                            reloadToken: viewModel.imageReloadToken,
                            isRotating: viewModel.rotatingPhotoIds.contains(photo.id),
                            onDelete: { pendingDelete = photo },
                        )
                    }
                }
            }
        }
        .refreshable {
            await viewModel.reloadPhotosAndImagesAwaiting()
        }
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

    /// Raised to the album screen, which owns the confirmation dialog — a dialog presented from
    /// inside a grid cell would go away with the cell.
    let onDelete: () -> Void

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
        }
        .aspectRatio(1.0, contentMode: .fit)
        .clipped()
        .onTapGesture {
            showingFullImage = true
        }
        .contextMenu {
            PhotoActionButtons(photo: photo, viewModel: viewModel, onDelete: onDelete)
        }
        .sheet(isPresented: $showingFullImage) {
            PhotoDetailView(openedWith: photo, viewModel: viewModel)
        }
    }
}

// MARK: - Photo Action Buttons

/// Rotate and Delete, shared by the grid's long-press menu and the full-screen view's menu so
/// the two cannot drift apart. Delete only *asks* — the owner of the surrounding screen runs
/// the confirmation, because that is where a dialog can outlive the thing being deleted.
struct PhotoActionButtons: View {
    let photo: Photo
    let viewModel: AlbumDetailViewModel
    let onDelete: () -> Void

    var body: some View {
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

    /// Owned by the view so the sheet keeps one player across body re-evaluations; the item is
    /// attached in `onAppear` because `photo` is not available at initialiser time here.
    @StateObject private var playerBox = PlayerBox()
    private var player: AVPlayer { playerBox.player }

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
                            // Without .playback the ring/silent switch silences the video.
                            try? AVAudioSession.sharedInstance().setCategory(.playback)
                            try? AVAudioSession.sharedInstance().setActive(true)
                            if player.currentItem == nil {
                                player.replaceCurrentItem(with: AVPlayerItem(url: videoURL))
                            }
                            player.play()
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
            .navigationTitle(photo.filename ?? photo.originalName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        PhotoActionButtons(
                            photo: photo,
                            viewModel: viewModel,
                            onDelete: { confirmingDelete = true },
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

/// Keeps one `AVPlayer` alive for a `PhotoDetailView`. `@StateObject` needs a reference type,
/// and `AVPlayer` is not `ObservableObject`, so it is wrapped rather than held directly.
final class PlayerBox: ObservableObject {
    let player = AVPlayer()
}

// Note: AuthenticatedImage is now implemented in Utils/AuthenticatedImageLoader.swift
