import AVKit
import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @StateObject private var viewModel: AlbumDetailViewModel

    init(album: Album) {
        self.album = album
        _viewModel = StateObject(wrappedValue: AlbumDetailViewModel(album: album))
    }

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

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
        Group {
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
                sortMenu
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(
                    action: { viewModel.fetchPhotos() },
                    label: { Image(systemName: "arrow.clockwise") },
                )
                .disabled(viewModel.isLoading || viewModel.isArrangingByHand)
            }
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
            }
        }
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
                        PhotoThumbnailView(photo: photo, viewModel: viewModel)
                    }
                }
            }
        }
        .refreshable {
            await viewModel.refreshPhotos()
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

    @State private var showingFullImage = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black)

            if let thumbnailURL = viewModel.thumbnailURL(for: photo) {
                AuthenticatedImage(url: thumbnailURL)
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.gray)
            }

            if photo.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .shadow(radius: 3)
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .clipped()
        .onTapGesture {
            showingFullImage = true
        }
        .sheet(isPresented: $showingFullImage) {
            PhotoDetailView(photo: photo, viewModel: viewModel)
        }
    }
}

// MARK: - Photo Detail View

struct PhotoDetailView: View {
    let photo: Photo
    let viewModel: AlbumDetailViewModel

    @Environment(\.dismiss) private var dismiss

    /// Owned by the view so the sheet keeps one player across body re-evaluations; the item is
    /// attached in `onAppear` because `photo` is not available at initialiser time here.
    @StateObject private var playerBox = PlayerBox()
    private var player: AVPlayer { playerBox.player }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if photo.isVideo, let videoURL = viewModel.videoURL(for: photo) {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
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
