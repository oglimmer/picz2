import AVKit
import SwiftUI

/// One photo of a presentation, full screen, with the section it belongs to named over it.
///
/// Swiping moves through the presentation in its reading order, so the chapter marker follows —
/// which is the whole reason this exists rather than reusing the album's detail sheet. Most of a
/// presentation is read zoomed in, and a heading that only appears in the grid is a heading
/// nobody sees. Same as the web app's Lightbox.
struct PresentationPhotoView: View {
    /// Every photo of the current selection, in reading order.
    let photos: [Photo]

    /// The same photos shelved into their groups, which is what names the chapter.
    let sections: [PresentationSection]

    @Environment(\.dismiss) private var dismiss

    @State private var index: Int

    /// Dismissed by tapping the marker; back on at the next chapter. A reader who wants the
    /// picture unobstructed should not have to keep dismissing the same heading, and should not
    /// have to remember it either.
    @State private var markerDismissed = false

    @State private var textExpanded = false

    init(photos: [Photo], sections: [PresentationSection], openedAt: Photo) {
        self.photos = photos
        self.sections = sections
        _index = State(initialValue: photos.firstIndex { $0.id == openedAt.id } ?? 0)
    }

    private var currentPhoto: Photo? {
        photos.indices.contains(index) ? photos[index] : nil
    }

    private var chapter: PresentationChapter? {
        PresentationGallery.chapter(in: sections, forPhotoID: currentPhoto?.id)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { position, photo in
                    slide(photo, isCurrent: position == index)
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
            }
            .padding()
        }
        .statusBarHidden()
        // Keyed on the group's id, not its label: two adjacent chapters that happen to share a
        // label still count as a new one to arrive at.
        .onChange(of: chapter?.id) { _, _ in
            markerDismissed = false
            textExpanded = false
        }
    }

    // MARK: - Slide

    @ViewBuilder
    private func slide(_ photo: Photo, isCurrent: Bool) -> some View {
        if !photo.isThumbnailReady {
            ProcessingPlaceholder(
                label: photo.processingFailed
                    ? "The server could not process this file."
                    : "Processing on the server…",
                isFailure: photo.processingFailed,
            )
        } else if photo.isVideo, let videoURL = AssetURLs.video(for: photo) {
            // A video must be played, not decoded — asking for an image derivative of one is
            // what renders as a failure.
            PresentationSlideVideo(url: videoURL, isCurrent: isCurrent)
        } else if let imageURL = AssetURLs.image(for: photo) {
            AuthenticatedImage(url: imageURL)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 60))
                Text("This photo is not available.")
                    .font(.footnote)
            }
            .foregroundColor(.white.opacity(0.7))
        }
    }

    // MARK: - Overlays

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            if let chapter, !markerDismissed {
                chapterMarker(chapter)
            }

            Spacer(minLength: 0)

            Text("\(index + 1) / \(photos.count)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.55), in: Capsule())

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .accessibilityLabel("Close")
        }
    }

    /// Which chapter this photo is in, and how far into it. Tapping it puts it away until the
    /// next chapter starts.
    private func chapterMarker(_ chapter: PresentationChapter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(chapter.label)
                    .font(.footnote.weight(.semibold))

                Text("\(chapter.position) / \(chapter.total)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.white.opacity(0.7))
            }

            if let text = chapter.text, !text.isEmpty {
                Text(text)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(textExpanded ? nil : 2)

                Button {
                    textExpanded.toggle()
                } label: {
                    Text(textExpanded ? "Show less" : "Show more")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
                // Without its own hit area the marker's dismiss tap swallows this one.
                .buttonStyle(.borderless)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: 260, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { markerDismissed = true }
        // The tap gesture is not a control as far as VoiceOver is concerned unless it is told
        // so — without this the heading reads as text with no way to put it away.
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Hides this chapter heading until the next one")
    }
}

// MARK: - Video slide

/// A video in the presentation pager.
///
/// Playback is gated on being the photo actually on screen: a paged `TabView` keeps its
/// neighbours alive, so a player that started on `onAppear` would have the next two videos
/// talking over the one being watched.
struct PresentationSlideVideo: View {
    let url: URL
    let isCurrent: Bool

    @StateObject private var playerBox = PlayerBox()

    var body: some View {
        VideoPlayer(player: playerBox.player)
            .onAppear {
                if playerBox.player.currentItem == nil {
                    playerBox.player.replaceCurrentItem(with: AVPlayerItem(url: url))
                }
                if isCurrent {
                    startPlaying()
                }
            }
            .onDisappear { playerBox.player.pause() }
            .onChange(of: isCurrent) { _, current in
                if current {
                    startPlaying()
                } else {
                    playerBox.player.pause()
                }
            }
    }

    private func startPlaying() {
        // Without `.playback` the ring/silent switch silences the video. Awaited off the main
        // thread before `play()` — see ``AudioSessionConfigurator``.
        Task {
            try? await AudioSessionConfigurator.activate(category: .playback)
            playerBox.player.play()
        }
    }
}
