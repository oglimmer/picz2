import AVKit
import SwiftUI

/// Plays a saved commentary back so the user can hear what they recorded.
///
/// Same black full-screen shape as the recorder, but the taps are gone: the audio drives the
/// slides, so the only controls are play/pause and close.
struct NarrationPlaybackView: View {
    @StateObject private var viewModel: NarrationPlaybackViewModel
    @Environment(\.dismiss) private var dismiss

    /// What the row it was opened from called this commentary, so the title matches.
    private let title: String

    init(recording: RecordingInfo, photosByID: [Int: Photo], title: String) {
        _viewModel = StateObject(
            wrappedValue: NarrationPlaybackViewModel(recording: recording, photosByID: photosByID),
        )
        self.title = title
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let slide = viewModel.currentSlide {
                slideContent(for: slide)
                    // Keyed on the asset so a slide change tears the old player or loader down
                    // instead of reusing it for different bytes.
                    .id(slide.id)
            } else {
                emptyState
            }

            VStack {
                topBar
                Spacer()
                transport
            }
            .padding()
        }
        .statusBarHidden()
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Slide

    @ViewBuilder
    private func slideContent(for slide: Photo) -> some View {
        if slide.isVideo, let videoURL = AssetURLs.video(for: slide) {
            // Muted: the commentary is the sound track, and a video talking over it is the one
            // thing the whole feature exists to avoid.
            MutedSlideVideo(url: videoURL)
        } else if let imageURL = AssetURLs.image(for: slide) {
            AuthenticatedImage(url: imageURL)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 60))
                .foregroundColor(.gray)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 50))
            Text("The photos this commentary was recorded over are no longer in this album.")
                .multilineTextAlignment(.center)
                .font(.footnote)
                .padding(.horizontal, 40)
        }
        .foregroundColor(.white.opacity(0.7))
    }

    // MARK: - Overlays

    private var topBar: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.55), in: Capsule())

            Spacer()

            if !viewModel.slides.isEmpty {
                Text("\(viewModel.currentIndex + 1) / \(viewModel.slides.count)")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .accessibilityLabel("Close preview")
        }
    }

    private var transport: some View {
        VStack(spacing: 10) {
            if let loadError = viewModel.loadError {
                Text(loadError)
                    .font(.footnote)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            } else if let preparingMessage = viewModel.preparingMessage {
                // Nothing is wrong here — the server is converting the commentary into a format
                // iPhone can decode, and the wait ends on its own.
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text(preparingMessage)
                        .font(.footnote)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
            } else {
                if viewModel.missingSlideCount > 0 {
                    Text(missingNote)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }

                ProgressView(value: viewModel.progress)
                    .tint(.white)

                HStack {
                    Text(viewModel.elapsedLabel)
                    Spacer()
                    Text(viewModel.totalLabel)
                }
                .font(.caption2.monospacedDigit())
                .foregroundColor(.white.opacity(0.7))

                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Image(systemName: playIcon)
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
                .accessibilityLabel(playLabel)
            }
        }
        .padding(.horizontal, 8)
    }

    private var playIcon: String {
        if viewModel.hasFinished {
            return "arrow.counterclockwise.circle.fill"
        }
        return viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill"
    }

    private var playLabel: String {
        if viewModel.hasFinished {
            return "Play again"
        }
        return viewModel.isPlaying ? "Pause" : "Play"
    }

    private var missingNote: String {
        viewModel.missingSlideCount == 1
            ? "1 photo from this commentary is no longer in the album."
            : "\(viewModel.missingSlideCount) photos from this commentary are no longer in the album."
    }
}
