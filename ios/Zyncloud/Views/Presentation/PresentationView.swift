import SwiftUI

/// The album with the tools put down: one tag's photos, shelved into the labelled sections the
/// web gallery placed on them, with the commentary recorded for that tag one tap away.
///
/// This is the creator's own read of the album — the phone's answer to the web gallery's
/// "Present". The album itself cannot be changed from here: no tagging, no rotating, no deleting,
/// no reordering. The one thing that can be written is the reading itself — where a chapter starts
/// and what it says — which is the judgement this screen is the right place to make.
struct PresentationView: View {
    @StateObject private var viewModel: PresentationViewModel
    @Environment(\.dismiss) private var dismiss

    /// The commentary being played, if any.
    @State private var playing: RecordingInfo?

    /// The chapter being written, if any. Owned here rather than by the tile or the heading that
    /// opened it: both are rebuilt the moment the chapter is stored, and a sheet presented from
    /// one would go away with it.
    @State private var editingGroup: PresentationGroupFormView.Target?

    /// Set when Remove was chosen on a chapter but not yet confirmed.
    @State private var pendingGroupDelete: PresentationGroup?

    /// Whether the long-press hint has been put away for good. Chapters are the one thing this
    /// screen can write and the only way in is a long press, which nothing on screen says — so it
    /// is said once, and stays said until the reader dismisses it or writes a chapter.
    @AppStorage("presentationChapterHintDismissed") private var chapterHintDismissed = false

    init(album: Album) {
        _viewModel = StateObject(wrappedValue: PresentationViewModel(album: album))
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        AdaptiveGrid.photoColumns(horizontalSizeClass)
    }

    var body: some View {
        // Its own navigation container: this arrives as a full-screen cover, which starts with
        // no bar of its own.
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.offersFilterChoice || hasAudioForSelection {
                    controlBar
                }

                if showsChapterHint {
                    chapterHint
                }

                content
            }
            .navigationTitle(viewModel.album.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fullScreenCover(item: $playing) { recording in
            NarrationPlaybackView(
                recording: recording,
                photosByID: viewModel.photosByID,
                title: title(for: recording),
            )
        }
        .sheet(item: $editingGroup) { target in
            PresentationGroupFormView(
                target: target,
                tag: viewModel.selectedTag ?? "",
                viewModel: viewModel,
            )
        }
        .confirmationDialog(
            "Remove chapter",
            isPresented: groupDeleteConfirmationShown,
            titleVisibility: .visible,
            presenting: pendingGroupDelete,
        ) { group in
            Button("Remove", role: .destructive) {
                pendingGroupDelete = nil
                viewModel.deleteGroup(group)
            }
            Button("Cancel", role: .cancel) { pendingGroupDelete = nil }
        } message: { group in
            Text("This removes the chapter \"\(group.label)\" and its text. The photos stay exactly where they are.")
        }
        .alert(state: $viewModel.alertState)
        .onAppear { viewModel.load() }
    }

    private var groupDeleteConfirmationShown: Binding<Bool> {
        Binding(
            get: { pendingGroupDelete != nil },
            set: { shown in
                if !shown {
                    pendingGroupDelete = nil
                }
            },
        )
    }

    // MARK: - Controls

    /// Which tag is being presented, and the commentary for it. Both are about *reading* the
    /// album, which is why they share one bar rather than hiding in a menu — in a presentation
    /// there is nothing else competing for the space.
    private var controlBar: some View {
        VStack(spacing: 8) {
            if viewModel.offersFilterChoice {
                Picker("Filter", selection: $viewModel.filter) {
                    Text("Select a filter…").tag(PresentationFilter.unset)
                    ForEach(viewModel.availableTags) { tag in
                        Text(label(for: tag)).tag(PresentationFilter.tag(tag.name))
                    }
                    // A view of the album, not a tag — which is why it is its own case and not a
                    // name in the same list (D34).
                    if viewModel.mapAvailable {
                        Text("🗺️ Map").tag(PresentationFilter.map)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if hasAudioForSelection {
                HStack(spacing: 12) {
                    ForEach(NarrationLanguage.allCases) { language in
                        if let recording = viewModel.recording(for: language) {
                            Button {
                                playing = recording
                            } label: {
                                Label(
                                    "Play \(viewModel.name(of: language))",
                                    systemImage: "play.circle.fill",
                                )
                                .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                            .disabled(recording.audioURL == nil)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    /// Shown only where the gesture would do something: a tag is selected, there are photos to
    /// press, and no chapter has been written under this tag yet. Writing one is the reader
    /// telling us they found it, so the hint goes away on its own rather than waiting to be
    /// dismissed.
    private var showsChapterHint: Bool {
        guard viewModel.canManageGroups, !chapterHintDismissed else { return false }
        guard !viewModel.sections.isEmpty else { return false }
        return !viewModel.sections.contains { $0.group != nil }
    }

    /// Says the one thing the grid cannot show: that a long press is a control.
    private var chapterHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.footnote)
                .foregroundColor(.accentColor)

            Text("Touch and hold a photo to start a chapter there.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button {
                chapterHintDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss hint")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
    }

    /// The map has no commentary: a narration is recorded against a tag, walking that tag's
    /// photos in order, and there is no such order on a map.
    private var hasAudioForSelection: Bool {
        guard !viewModel.isMapMode else { return false }
        return NarrationLanguage.allCases.contains { viewModel.recording(for: $0) != nil }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.allPhotos.isEmpty {
            centered { ProgressView("Loading album…") }
        } else if viewModel.isMapMode {
            AlbumMapView(photos: viewModel.allPhotos, savedView: viewModel.savedMapView)
        } else if viewModel.needsTagChoice {
            centered { tagPrompt }
        } else if viewModel.sections.isEmpty {
            centered { emptyState }
        } else {
            gallery
        }
    }

    private var gallery: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(viewModel.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        if let group = section.group {
                            PresentationSectionHeader(
                                group: group,
                                count: section.photos.count,
                                editable: viewModel.canManageGroups,
                                onEdit: { editingGroup = .existing(group) },
                                onRemove: { pendingGroupDelete = group },
                            )
                        }

                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(section.photos) { photo in
                                PresentationTile(
                                    photo: photo,
                                    viewModel: viewModel,
                                    // The chapter this photo is being read under, which is the one
                                    // an "end it here" would end. Derived from the section rather
                                    // than looked up, because that is what the walk decided.
                                    enclosingGroup: section.group,
                                    onStartGroup: { editingGroup = .new(anchor: photo) },
                                    onEditGroup: { editingGroup = .existing($0) },
                                    onRemoveGroup: { pendingGroupDelete = $0 },
                                    onSetGroupEnd: { group, endPhoto in
                                        Task { await viewModel.setGroupEnd(group, at: endPhoto) }
                                    },
                                )
                            }
                        }

                        if section.isClosed, let group = section.group {
                            PresentationSectionEndRule(label: group.label)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    /// The album has tags, so a presentation of all of them is not what anyone means by one.
    /// Same prompt the web gallery shows in the same place.
    private var tagPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 44))
                .foregroundColor(.secondary)

            Text("Please select a tag filter")
                .font(.headline)

            Text("Choose a tag above to start the presentation.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if viewModel.hasAnyRecording {
                Text("Filters marked ♪ have an audio commentary.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.system(size: 44))
                .foregroundColor(.secondary)

            Text("Nothing to present")
                .font(.headline)

            Text(viewModel.selectedTag == nil
                ? "This album has no photos yet."
                : "No photo in this album carries that tag any more.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    private func centered(@ViewBuilder _ inner: () -> some View) -> some View {
        VStack {
            Spacer()
            inner()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Labels

    /// The music note marks a tag that has a commentary — the same hint the web dropdown gives,
    /// so the audio is not something you find only by picking the right filter by luck.
    private func label(for tag: PresentationGallery.TagCount) -> String {
        let note = viewModel.hasRecording(forTag: tag.name) ? " ♪" : ""
        return "\(tag.name) (\(tag.count))\(note)"
    }

    private func title(for recording: RecordingInfo) -> String {
        guard let language = recording.narrationLanguage else {
            return recording.language ?? "Commentary"
        }
        return viewModel.name(of: language)
    }
}

// MARK: - Section Header

/// A group's heading: the label, how many photos it covers, and the paragraph underneath.
///
/// The accent rule down the left is what ties the heading to the photos below it — without it a
/// run of sections reads as a list of captions rather than as chapters.
struct PresentationSectionHeader: View {
    let group: PresentationGroup
    let count: Int

    /// Offers Edit and Remove. Off unless a tag is selected — a chapter belongs to one, and there
    /// is nothing to edit under the map or the opening prompt.
    var editable: Bool = false

    /// Raised to the screen, which owns the form and the confirmation: this heading is rebuilt
    /// the moment the chapter changes, and a sheet presented from here would go with it.
    var onEdit: () -> Void = {}
    var onRemove: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor.opacity(0.75))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.label)
                        .font(.title3.weight(.semibold))

                    Text(count == 1 ? "1 photo" : "\(count) photos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())

                    if editable {
                        Spacer(minLength: 0)
                        chapterMenu
                    }
                }

                if let text = group.text, !text.isEmpty {
                    Text(text)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    /// A menu rather than two buttons in the heading: Remove is destructive and a heading is a
    /// small target to put it next to.
    private var chapterMenu: some View {
        Menu {
            Button {
                onEdit()
            } label: {
                Label("Edit Chapter", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove Chapter", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(4)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Chapter actions")
    }
}

/// The closing line of a chapter that stopped on its own end photo.
///
/// Deliberately ``PresentationSectionHeader``'s own accent rule laid on its side: the heading opens
/// a chapter with a vertical 3pt bar, and this closes it with the same bar running the other way,
/// fading out into a full stop. Only drawn for a chapter that closed itself — one that merely ran
/// into the next heading is already announced by that heading.
struct PresentationSectionEndRule: View {
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            // The heading's bar, same width and opacity, so the pair reads as one bracket.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor.opacity(0.75))
                .frame(width: 3, height: 14)

            Text("End of “\(label)”")
                .font(.caption2.weight(.semibold))
                .kerning(1.2)
                .textCase(.uppercase)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            LinearGradient(
                colors: [Color.accentColor.opacity(0.6), Color.accentColor.opacity(0.17)],
                startPoint: .leading,
                endPoint: .trailing,
            )
            .frame(height: 2)
            .clipShape(Capsule())

            // The full stop the line trails into. Pulled back off the row spacing: at the full
            // gap it reads as a stray dot rather than as the end of the line.
            Circle()
                .fill(Color.accentColor.opacity(0.55))
                .frame(width: 5, height: 5)
                .padding(.leading, -6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("End of the chapter \(label).")
    }
}

// MARK: - Tile

/// One photo in the presentation grid.
///
/// Deliberately not ``PhotoThumbnailView``: that one carries tagging, rotating and deleting, none
/// of which belong in a presentation. A tap opens the pager at this photo; the only things that
/// can be *changed* from here are where a chapter starts and where it stops, both behind a long
/// press.
struct PresentationTile: View {
    let photo: Photo

    @ObservedObject var viewModel: PresentationViewModel

    /// The chapter this photo is currently read under, or nil for a headingless run. Only a photo
    /// inside a chapter can be made that chapter's last one.
    var enclosingGroup: PresentationGroup?

    /// Raised to the screen, which owns the form and the confirmation.
    var onStartGroup: () -> Void = {}
    var onEditGroup: (PresentationGroup) -> Void = { _ in }
    var onRemoveGroup: (PresentationGroup) -> Void = { _ in }

    /// Moves the chapter's end to this photo, or clears it when the photo passed is nil.
    var onSetGroupEnd: (PresentationGroup, Photo?) -> Void = { _, _ in }

    @State private var isOpen = false

    /// The chapter that starts here, if this photo anchors one.
    private var anchoredGroup: PresentationGroup? {
        viewModel.groupStarting(at: photo.id)
    }

    /// The chapter that stops here, if this photo is one's last.
    private var closingGroup: PresentationGroup? {
        viewModel.groupEnding(at: photo.id)
    }

    var body: some View {
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

            if anchoredGroup != nil {
                chapterStartBadge
            }

            if closingGroup != nil {
                chapterEndBadge
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .clipped()
        .onTapGesture { isOpen = true }
        .contextMenu {
            // A photo either starts a chapter or could start one — and the chapter that starts
            // here is reachable from the photo as well as from the heading, which is where the
            // eye is when the thought "this is the wrong place for it" arrives.
            if viewModel.canManageGroups {
                if let anchoredGroup {
                    Button {
                        onEditGroup(anchoredGroup)
                    } label: {
                        Label("Edit Chapter", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        onRemoveGroup(anchoredGroup)
                    } label: {
                        Label("Remove Chapter", systemImage: "trash")
                    }
                } else {
                    Button {
                        onStartGroup()
                    } label: {
                        Label("Start a Chapter Here", systemImage: "text.insert")
                    }
                }

                // Ending is offered on any photo inside a chapter, the anchor included — a
                // chapter of exactly one photo starts and stops on the same one.
                if let enclosingGroup {
                    if closingGroup != nil {
                        Button {
                            onSetGroupEnd(enclosingGroup, nil)
                        } label: {
                            Label("Reopen Chapter", systemImage: "arrow.turn.down.right")
                        }
                    } else {
                        Button {
                            onSetGroupEnd(enclosingGroup, photo)
                        } label: {
                            Label("End Chapter Here", systemImage: "text.append")
                        }
                    }
                }
            }
        }
        // A grid of pictures with no labels is a grid of "image, image, image" to VoiceOver, and
        // a tap gesture is not a control unless it says it is.
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
        .fullScreenCover(isPresented: $isOpen) {
            PresentationPhotoView(
                photos: viewModel.orderedPhotos,
                sections: viewModel.sections,
                openedAt: photo,
            )
        }
    }

    /// Says a chapter starts here, so the anchor is visible in the grid rather than only in the
    /// heading above it — which is what makes it obvious why the long-press menu is empty here.
    private var chapterStartBadge: some View {
        VStack {
            HStack {
                Image(systemName: "text.insert")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.accentColor.opacity(0.9), in: Circle())
                Spacer()
            }
            Spacer()
        }
        .padding(4)
    }

    /// Says a chapter stops here. Opposite corner from the start badge, so a one-photo chapter —
    /// which carries both — still reads at a glance, and the start badge inverted rather than a
    /// second colour: filled accent opens a chapter, outlined accent closes it.
    ///
    /// The bar down the trailing edge is the section's closing rule foreshadowed on the last tile,
    /// so the boundary is visible in the grid and not only underneath it.
    private var chapterEndBadge: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Image(systemName: "text.append")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.accentColor)
                    .padding(4)
                    .background(Color.white.opacity(0.92), in: Circle())
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                    .padding(4)

                Spacer(minLength: 0)
            }

            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor.opacity(0.75))
                .frame(width: 3)
                .padding(.vertical, 4)
        }
    }

    private var accessibilityLabel: String {
        let name = photo.filename ?? photo.originalName
        var parts = [name]
        if let anchoredGroup {
            parts.append("Starts the chapter \(anchoredGroup.label).")
        }
        if let closingGroup {
            parts.append("Ends the chapter \(closingGroup.label).")
        }
        return parts.joined(separator: ". ")
    }
}
