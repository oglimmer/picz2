import SwiftUI

/// A text card in the album grid (D86): a chapter heading standing where a photo would stand.
///
/// The background is the *next* picture in the album, blurred past recognition. That is the whole
/// idea — the card belongs to what follows it, so it takes its colour from it and the grid reads
/// as one run of images rather than as tiles with a text box wedged between them.
struct TextCardTileView: View {
    let card: Photo

    /// The photo behind the blur, or nil when the card is last in the album (or followed only by
    /// other cards). Handed in rather than looked up here: only the list knows what comes next,
    /// and it changes on every reorder and every tag filter.
    let backgroundURL: URL?

    /// Passed down like every other image in this grid, so Refresh reaches the blur too.
    let reloadToken: Int

    var body: some View {
        ZStack {
            // The ground a card falls back to when there is nothing after it. Warm, not grey — a
            // plain grey square reads as a broken picture rather than as a deliberate card.
            LinearGradient(
                colors: [Color(white: 0.30), Color(white: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )

            if let backgroundURL {
                AuthenticatedImage(url: backgroundURL, reloadToken: reloadToken)
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .blur(radius: 14)
                    // Scaled up after the blur so its soft edge is pushed outside the tile —
                    // `blur` samples nothing beyond the view, so an un-scaled image fades to a
                    // pale rim all the way round.
                    .scaleEffect(1.3)
                    .clipped()
            }

            // The text has to stay readable over a picture nobody chose for its contrast.
            LinearGradient(
                colors: [.black.opacity(0.32), .black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom,
            )

            VStack(spacing: 6) {
                Text(card.cardHeadline)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    // Three lines and then stop. A tile is a fixed square: a heading allowed to
                    // grow would push its own body text out rather than get more room.
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .shadow(radius: 4)

                if let bodyText = card.bodyText, !bodyText.isEmpty {
                    Text(bodyText)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(4)
                        .multilineTextAlignment(.center)
                        .shadow(radius: 3)
                }
            }
            .padding(10)
        }
        .clipped()
    }
}

/// A text card read full screen (D86): the chapter page.
///
/// Same words as ``TextCardTileView`` and the same blurred neighbour behind them, but sized to be
/// read rather than glanced at. Its own view rather than the tile scaled up, because the tile
/// clamps its text to fit a square and this one must not — the full text is the point here.
struct TextCardSlideView: View {
    let card: Photo

    /// The photo behind the blur, or nil for a card with nothing after it.
    let backgroundURL: URL?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    Text(card.cardHeadline)
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .shadow(radius: 8)

                    if let bodyText = card.bodyText, !bodyText.isEmpty {
                        Text(bodyText)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.93))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .shadow(radius: 6)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 64)
                .frame(maxWidth: 620)
                // A card is usually a heading and a sentence, which should sit in the middle of
                // the screen rather than at the top: a scroll view stacks its content from the
                // top, so the content is made at least as tall as the screen and centred in that.
                // The scroll view is there for the long one.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // The text keeps to the safe area, so it never runs under the detail sheet's navigation
        // bar or the home indicator; only the picture behind it reaches the edges. As a
        // background it cannot size the page either.
        .background { background.ignoresSafeArea() }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.28), Color(white: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )

            if let backgroundURL {
                AuthenticatedImage(url: backgroundURL)
                    .scaledToFill()
                    // The zero minimums are load-bearing, as in the tile: without them the frame
                    // reports the filled image's size, which for a landscape photo is far wider
                    // than the screen, and `clipped()` then clips to that instead of the screen.
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .blur(radius: 30)
                    // Scaled after the blur so its soft edge is pushed off screen — `blur`
                    // samples nothing outside the view, so an un-scaled image fades to a pale
                    // border all the way round.
                    .scaleEffect(1.25)
                    .clipped()
            }

            LinearGradient(
                colors: [.black.opacity(0.42), .black.opacity(0.68)],
                startPoint: .top,
                endPoint: .bottom,
            )
        }
    }
}

/// Writes a text card's heading and body (D86) — the same sheet for a new card and for an edit.
///
/// Its own sheet rather than an inline field, for the reason ``PhotoCaptionView`` gives: a text
/// box inside a grid cell would be typed into blind behind the keyboard.
struct TextCardEditView: View {
    /// The card being edited, or nil when this is a new one.
    let card: Photo?

    @ObservedObject var viewModel: AlbumDetailViewModel

    @Environment(\.dismiss) private var dismiss

    /// Both mirror the caps in the server's FileStorageService, enforced while typing so nobody
    /// writes a paragraph and loses it to a rejected save.
    private static let maxHeadlineLength = 200
    private static let maxBodyLength = 4000

    @State private var headline: String = ""
    @State private var bodyText: String = ""

    /// Set once in `onAppear`. Without it every body re-evaluation would re-seed the fields from
    /// the server's copy and wipe what is being typed.
    @State private var didSeedDrafts = false

    @FocusState private var isFocused: Bool

    private var isEditing: Bool { card != nil }

    private var trimmedHeadline: String {
        headline.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Day three — over the pass", text: $headline)
                        .focused($isFocused)
                        .onChange(of: headline) { _, new in
                            if new.count > Self.maxHeadlineLength {
                                headline = String(new.prefix(Self.maxHeadlineLength))
                            }
                        }
                } header: {
                    Text("Headline")
                }

                Section {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 120)
                        .onChange(of: bodyText) { _, new in
                            if new.count > Self.maxBodyLength {
                                bodyText = String(new.prefix(Self.maxBodyLength))
                            }
                        }
                } header: {
                    Text("Text (optional)")
                } footer: {
                    Text(isEditing
                        ? "The card takes its background from the photo that follows it."
                        : "The card is added at the end of the album. Move it where the chapter starts — it takes its background from the photo that follows it.")
                }
            }
            .navigationTitle(isEditing ? "Edit Card" : "New Text Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Save" : "Add") {
                        save()
                        dismiss()
                    }
                    // A card with no heading is nothing, and the server refuses it — so the
                    // button is off rather than the save being thrown back.
                    .disabled(trimmedHeadline.isEmpty)
                }
            }
            .onAppear {
                guard !didSeedDrafts else { return }
                headline = card?.headline ?? ""
                bodyText = card?.bodyText ?? ""
                didSeedDrafts = true
                isFocused = true
            }
        }
    }

    /// A blank body is sent as an empty string; the server stores null for it.
    private func save() {
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let card {
            viewModel.updateTextCard(headline: trimmedHeadline, bodyText: trimmedBody, on: card)
        } else {
            viewModel.createTextCard(headline: trimmedHeadline, bodyText: trimmedBody)
        }
    }
}
