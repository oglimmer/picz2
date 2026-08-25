import AVKit
import SwiftUI

/// The full-screen slideshow the user talks over.
///
/// One asset at a time on black. A tap anywhere moves on; the last tap ends the recording. The
/// only other control is Stop, because every other pixel has to stay tappable.
struct NarrationSlideshowView: View {
    @ObservedObject var viewModel: NarrationRecorderViewModel

    /// Set when Stop or the close button was tapped, before the confirmation. Ending early is
    /// normal, so it saves rather than asking — but *discarding* asks, because the audio is
    /// gone for good.
    @State private var confirmingDiscard = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let slide = viewModel.currentSlide {
                slideContent(for: slide)
                    // Keyed on the asset so switching slides tears down the old player and
                    // image loader instead of reusing them for different bytes.
                    .id(slide.id)
            }

            // A transparent layer over the whole screen, so the tap target is the screen and
            // not just the picture — a portrait photo on a landscape phone leaves wide black
            // bars, and tapping those has to work too.
            Color.white.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { viewModel.advance() }

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding()
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .confirmationDialog(
            "Discard commentary",
            isPresented: $confirmingDiscard,
            titleVisibility: .visible,
        ) {
            Button("Discard", role: .destructive) { viewModel.cancelRecording() }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("The audio you have recorded so far is thrown away. It cannot be undone.")
        }
    }

    // MARK: - Slide

    @ViewBuilder
    private func slideContent(for slide: Photo) -> some View {
        if slide.isVideo, let videoURL = viewModel.videoURL(for: slide) {
            // Muted, always: the narrator is the sound track. Autoplay so the slide is not a
            // still frame waiting for a tap that would instead move on.
            MutedSlideVideo(url: videoURL)
                .allowsHitTesting(false)
        } else if let imageURL = viewModel.imageURL(for: slide) {
            AuthenticatedImage(url: imageURL)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 60))
                .foregroundColor(.gray)
        }
    }

    // MARK: - Overlays

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                Text(viewModel.elapsedLabel)
                    .monospacedDigit()
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())

            Spacer()

            Text("\(viewModel.currentIndex + 1) / \(viewModel.slides.count)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.55), in: Capsule())

            Button {
                confirmingDiscard = true
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .accessibilityLabel("Discard commentary")
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Text("Tap the screen for the next one")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))

            Button {
                viewModel.finish()
            } label: {
                Label("Stop and Save", systemImage: "stop.fill")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.red, in: Capsule())
            }
        }
    }
}
