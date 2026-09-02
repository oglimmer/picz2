import AVKit
// ObservableObject's synthesised conformance needs Combine in scope — PlayerBox below is the
// only reason this file imports it.
import Combine
import SwiftUI

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

    /// True while this photo's caption editor is up, stacked on top of this sheet.
    @State private var isCaptioning = false

    /// Owned by the view so the sheet keeps one player across body re-evaluations; the item is
    /// attached in `onAppear` because `photo` is not available at initialiser time here.
    @StateObject private var playerBox = PlayerBox()
    private var player: AVPlayer {
        playerBox.player
    }

    var body: some View {
        NavigationStack {
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
                // Only drawn when there is something to say, so a photo with neither caption
                // nor tags keeps the whole screen for the picture.
                if !(photo.caption ?? "").isEmpty || !photo.tags.isEmpty {
                    VStack(spacing: 0) {
                        if let caption = photo.caption, !caption.isEmpty {
                            captionBar(caption)
                        }
                        if !photo.tags.isEmpty {
                            tagBar
                        }
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
                            onTag: { isTagging = true },
                            onCaption: { isCaptioning = true },
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
            .sheet(isPresented: $isCaptioning) {
                PhotoCaptionView(photo: photo, viewModel: viewModel)
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
    /// The owner's caption (D69), under the picture and above the tags. Selectable and
    /// scrollable rather than clipped: this is the one screen where the whole text has to be
    /// readable, however long it is.
    func captionBar(_ caption: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(caption)
                .font(.subheadline)
                .foregroundColor(.white)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(maxHeight: 140)
        .background(.ultraThinMaterial)
    }

    /// Every tag on this photo, spelled out. The grid tile only has room for two, so this is
    /// where the full list is readable — and it scrolls sideways rather than wrapping, because
    /// a growing strip would push the picture around.
    var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(photo.tags, id: \.self) { tag in
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
