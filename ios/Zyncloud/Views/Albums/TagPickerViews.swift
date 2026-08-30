import SwiftUI

// MARK: - One photo

/// The tags on a single photo. Tapping a name puts it on or takes it off straight away.
///
/// The list offered is the album's, not the account's: the server refuses any tag the album
/// does not accept, so the others would only ever fail. "Album Tags" at the bottom is the way
/// to widen that list.
struct PhotoTagsView: View {
    let photo: Photo

    @ObservedObject var viewModel: AlbumDetailViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var newTagName: String = ""

    /// The photo as the view model holds it now. Tagging replaces the row, and the sheet has
    /// to show the new tick rather than the list the sheet opened with.
    private var current: Photo {
        viewModel.photos.first { $0.id == photo.id } ?? photo
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if viewModel.isLoadingTags, viewModel.albumTags.isEmpty {
                        LoadingTagsRow()
                    } else if viewModel.albumTags.isEmpty {
                        Text("This album accepts no tags yet. Add one below.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.albumTags) { tag in
                            TagToggleRow(
                                name: tag.name,
                                isSystem: tag.isSystem,
                                icon: current.tags.contains(tag.name) ? .on : .off,
                                isBusy: viewModel.isApplyingTags,
                            ) {
                                viewModel.toggleTag(tag.name, on: current)
                            }
                        }
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Tap a tag to put it on this photo or take it off.")
                }

                NewTagSection(name: $newTagName, viewModel: viewModel)

                AlbumTagsLinkSection(viewModel: viewModel)
            }
            .navigationTitle(current.filename ?? current.originalName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { viewModel.loadTagsIfNeeded() }
        // Nothing here reports success with an alert, so an alert means something went wrong —
        // and an alert raised behind a sheet is never seen. Closing first hands it to the album
        // screen, which can show it.
        .onChange(of: viewModel.alertState?.id) { _, id in
            if id != nil { dismiss() }
        }
    }
}

// MARK: - Many photos

/// Tagging every picked photo at once.
///
/// Nothing is sent while the sheet is open. A tap on a row only stages what that tag should
/// become across the selection; **Done** sends the lot, **Cancel** throws it away. The old sheet
/// wrote each tap straight to the server and closed itself, which made Done look like a save
/// button that did not save.
///
/// One staged tap still means one thing for the whole selection: a tag goes on every picked
/// photo or on none of them, never per photo.
struct BulkTagView: View {
    @ObservedObject var viewModel: AlbumDetailViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var newTagName: String = ""

    /// What each touched tag should become: `true` on every picked photo, `false` on none.
    /// Untouched tags are absent, and a tag put back the way it started is taken out again — so
    /// this is exactly the work Done has to do, and empty means there is none.
    @State private var draft: [String: Bool] = [:]

    private var pickedCount: Int {
        viewModel.selectedPhotoIds.count
    }

    /// The staged wish if the row was tapped, otherwise how the tag really sits right now.
    private func icon(for tagName: String) -> TagRowIcon {
        if let wanted = draft[tagName] {
            return wanted ? .on : .off
        }
        return TagRowIcon(viewModel.selectionState(of: tagName))
    }

    /// A tap flips the row between "on every picked photo" and "on none of them". A half-filled
    /// row goes to on first, which is the change people mean when they tap one.
    private func toggle(_ tagName: String) {
        let wanted = icon(for: tagName) != .on
        let original = viewModel.selectionState(of: tagName)

        if wanted, original == .all {
            draft.removeValue(forKey: tagName)
        } else if !wanted, original == .none {
            draft.removeValue(forKey: tagName)
        } else {
            draft[tagName] = wanted
        }
    }

    private var footerText: String {
        let rule = "A tag goes on every picked photo or on none of them."
        switch draft.count {
        case 0: return "\(rule) Nothing is saved until you tap Done."
        case 1: return "\(rule) 1 change waiting for Done."
        case let count: return "\(rule) \(count) changes waiting for Done."
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if viewModel.isLoadingTags, viewModel.albumTags.isEmpty {
                        LoadingTagsRow()
                    } else if viewModel.albumTags.isEmpty {
                        Text("This album accepts no tags yet. Add one below.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.albumTags) { tag in
                            TagToggleRow(
                                name: tag.name,
                                isSystem: tag.isSystem,
                                icon: icon(for: tag.name),
                                isBusy: viewModel.isApplyingTags,
                            ) {
                                toggle(tag.name)
                            }
                        }
                    }
                } header: {
                    Text(pickedCount == 1 ? "1 photo picked" : "\(pickedCount) photos picked")
                } footer: {
                    Text(footerText)
                }

                // A tag made here is meant for the picked photos, so it is staged on straight
                // away. Without that, "Add" then "Done" would quietly change nothing.
                NewTagSection(name: $newTagName, viewModel: viewModel) { created in
                    draft[created] = true
                }

                AlbumTagsLinkSection(viewModel: viewModel)
            }
            .navigationTitle("Tag Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isApplyingTags)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.applyTagChangesToSelection(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.isApplyingTags)
                }
            }
        }
        .onAppear { viewModel.loadTagsIfNeeded() }
        .onChange(of: viewModel.alertState?.id) { _, id in
            if id != nil { dismiss() }
        }
    }
}

// MARK: - Which tags the album accepts

/// The account's tags, each switched on or off for this album.
///
/// Switching one off does not strip it from photos that already carry it — the server keeps
/// those. It only stops the tag being offered here.
struct AlbumTagsSettingsView: View {
    @ObservedObject var viewModel: AlbumDetailViewModel

    @State private var newTagName: String = ""

    private var togglableTags: [Tag] {
        viewModel.accountTags.filter { !$0.isSystem }
    }

    var body: some View {
        List {
            Section {
                if viewModel.isLoadingTags, viewModel.accountTags.isEmpty {
                    LoadingTagsRow()
                } else if togglableTags.isEmpty {
                    Text("You have no tags yet. Add one below.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(togglableTags) { tag in
                        TagToggleRow(
                            name: tag.name,
                            isSystem: false,
                            icon: viewModel.enabledTagIds.contains(tag.id) ? .on : .off,
                            isBusy: viewModel.isApplyingTags,
                        ) {
                            toggle(tag)
                        }
                    }
                }
            } header: {
                Text("Tags for This Album")
            } footer: {
                Text("Only tags switched on here can be put on this album's photos. Switching one off leaves it on photos that already have it.")
            }

            NewTagSection(name: $newTagName, viewModel: viewModel)
        }
        .navigationTitle("Album Tags")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.loadTagsIfNeeded() }
    }

    /// The server takes the whole list, not a single change, so the new list is built here and
    /// sent in one go.
    private func toggle(_ tag: Tag) {
        var ids = viewModel.enabledTagIds
        if let index = ids.firstIndex(of: tag.id) {
            ids.remove(at: index)
        } else {
            ids.append(tag.id)
        }
        viewModel.setAlbumTags(ids)
    }
}

// MARK: - Shared pieces

/// What the tick at the end of a row says.
enum TagRowIcon {
    case on
    case partly
    case off

    init(_ state: TagSelectionState) {
        switch state {
        case .all: self = .on
        case .some: self = .partly
        case .none: self = .off
        }
    }

    var systemName: String {
        switch self {
        case .on: "checkmark.circle.fill"
        case .partly: "minus.circle.fill"
        case .off: "circle"
        }
    }

    var color: Color {
        switch self {
        case .on: .accentColor
        case .partly: .orange
        case .off: .secondary
        }
    }
}

/// One tappable tag row. Shared by all three screens so the tick means the same thing
/// everywhere.
struct TagToggleRow: View {
    let name: String
    let isSystem: Bool
    let icon: TagRowIcon
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(name)
                    .foregroundColor(.primary)

                if isSystem {
                    Text("system")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: icon.systemName)
                    .foregroundColor(icon.color)
            }
            .contentShape(Rectangle())
        }
        .disabled(isBusy)
    }
}

struct LoadingTagsRow: View {
    var body: some View {
        HStack {
            Text("Loading tags…")
                .foregroundColor(.secondary)
            Spacer()
            ProgressView()
        }
    }
}

/// Makes a tag and switches it on for this album in one step — a tag the album does not accept
/// cannot be put on anything in it, so creating one without enabling it would look broken.
struct NewTagSection: View {
    @Binding var name: String

    @ObservedObject var viewModel: AlbumDetailViewModel

    /// Told the name that was just made, for a sheet that has to do something with it — the
    /// bulk sheet stages it on. Left out where creating the tag is the whole job.
    var onCreated: ((String) -> Void)?

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Section {
            HStack {
                TextField("Tag name", text: $name)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit(create)

                Button("Add", action: create)
                    .disabled(trimmed.isEmpty || viewModel.isApplyingTags)
            }
        } header: {
            Text("New Tag")
        } footer: {
            Text("A new tag is switched on for this album right away.")
        }
    }

    private func create() {
        guard !trimmed.isEmpty else { return }
        let created = trimmed
        viewModel.createTag(named: created)
        name = ""
        onCreated?(created)
    }
}

/// The way from either tag sheet to the album's accepted-tag list.
struct AlbumTagsLinkSection: View {
    @ObservedObject var viewModel: AlbumDetailViewModel

    var body: some View {
        Section {
            NavigationLink {
                AlbumTagsSettingsView(viewModel: viewModel)
            } label: {
                Label("Album Tags", systemImage: "tag")
            }
        } footer: {
            Text("Choose which of your tags this album accepts.")
        }
    }
}

// MARK: - Showing tags

/// The tags on a photo, small enough to sit on a grid tile.
///
/// Only two names fit across a third of a phone screen, so the rest are counted rather than
/// truncated — "+3" says there is more, where a clipped third name would look like the whole
/// list.
struct PhotoTagChips: View {
    let tags: [String]

    /// How many names to spell out before counting the rest.
    var limit: Int = 2

    var font: Font = .system(size: 9, weight: .semibold)

    private var shown: [String] {
        Array(tags.prefix(limit))
    }

    private var extra: Int {
        max(0, tags.count - limit)
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(shown, id: \.self) { tag in
                chip(tag)
            }
            if extra > 0 {
                chip("+\(extra)")
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
