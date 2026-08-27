import Combine
import Foundation

/// Drives the album's presentation — the creator's own read of what a share-link visitor sees.
///
/// A presentation is a tag-driven narrative, not a second way to browse: it shows one tag's
/// photos, shelved into labelled chapters, with the audio commentary recorded for that tag one tap
/// away. The album is read-only here — no tagging, rotating, deleting or reordering — but the
/// chapters are not: placing one is a judgement about a run of photos, best made while looking at
/// them.
///
/// Mirrors the web gallery's presentation mode (`GalleryView` with `presentationMode: true`), so
/// an album reads the same on both clients.
@MainActor
final class PresentationViewModel: ViewModelProtocol {
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?

    /// Every photo in the album, unfiltered. The tag filter is applied on the phone, so changing
    /// it costs no round trip — and a commentary's `fileId` still resolves under a filter that
    /// excludes it.
    @Published private(set) var allPhotos: [Photo] = []

    /// The tags this album can be presented under.
    @Published private(set) var availableTags: [PresentationGallery.TagCount] = []

    /// The section markers, for every tag. Narrowed to the selected one when sections are built.
    @Published private(set) var groups: [PresentationGroup] = []

    /// The album's saved commentaries, so the tag that has one can say so and offer to play it.
    @Published private(set) var recordings: [RecordingInfo] = []

    @Published private(set) var language1Name: String = "Language 1"
    @Published private(set) var language2Name: String = "Language 2"

    /// What the presentation is showing: nothing yet, one tag, or the map.
    ///
    /// There is deliberately no "all photos" option: a presentation of a whole album is not a
    /// narrative, and the web gallery asks for a filter before it shows anything. The one
    /// exception is an album with no tags at all — see ``needsTagChoice``.
    @Published var filter: PresentationFilter = .unset {
        didSet {
            guard filter != oldValue else { return }
            rebuildSections()
        }
    }

    /// The tag being presented, if one is. Derived rather than stored, so the map can never end
    /// up in it — see ``PresentationFilter``.
    var selectedTag: String? {
        filter.tagName
    }

    var isMapMode: Bool {
        filter.isMap
    }

    /// The chosen tag's photos, shelved into their groups. What the screen actually renders.
    @Published private(set) var sections: [PresentationSection] = []

    /// True while a chapter is being written to the server, so the form can say so and a second
    /// save cannot be started on top of the first.
    @Published private(set) var isSavingGroup: Bool = false

    let album: Album

    private let apiClient: APIClient?

    init(album: Album, apiClient: APIClient? = APIClientProvider.shared.current) {
        self.album = album
        self.apiClient = apiClient
    }

    // MARK: - What the screen asks

    /// True while the album has tags but nothing is chosen. The screen shows the prompt rather
    /// than the photos — the same thing the web gallery does, and for the same reason: an
    /// unfiltered album is as long as the album and says nothing.
    var needsTagChoice: Bool {
        !availableTags.isEmpty && filter == .unset
    }

    /// True when there is something to pick between. One tag and no map is not a choice — the tag
    /// is selected on load — but one tag *and* a map is, or the map would be unreachable.
    var offersFilterChoice: Bool {
        availableTags.count > 1 || mapAvailable
    }

    /// True when any photo in the album carries a location.
    ///
    /// Deliberately **not** also gated on `/api/capabilities.maps.enabled`: that flag says the
    /// server holds an Apple key for MapKit **JS**, which the browser cannot draw a tile without.
    /// Native MapKit needs no key and no token endpoint, so gating on it here would hide a map
    /// that works perfectly well.
    var mapAvailable: Bool {
        !PhotoMapPlaces.located(in: allPhotos).isEmpty
    }

    /// The framing the owner saved for this album's map, or nil to fit every pin. Read-only here:
    /// the framing is set from the album's own map screen, which is where the controls are.
    var savedMapView: SavedMapView? {
        album.savedMapView
    }

    /// True when chapters can be written. They belong to one `(album, tag)` pair, so there has to
    /// be a tag — the map selects none, and neither does the opening prompt.
    var canManageGroups: Bool {
        selectedTag != nil
    }

    /// The chapter anchored at this photo, if one is. A photo can anchor at most one chapter per
    /// tag — the server holds `(album, tag, start_file_id)` unique — so this is what decides
    /// between offering "start a chapter here" and saying one already starts here.
    func groupStarting(at photoID: Int) -> PresentationGroup? {
        guard let selectedTag else { return nil }
        return groups.first { $0.tag == selectedTag && $0.startFileId == photoID }
    }

    /// The photos of the current selection in reading order, flattened back out of the sections.
    /// This is what the full-screen pager walks, so it cannot drift from what the grid shows.
    var orderedPhotos: [Photo] {
        sections.flatMap(\.photos)
    }

    /// True when any tag in this album has a commentary. Used to say so before a tag is picked,
    /// so the audio is not a thing you only find by guessing the right filter.
    var hasAnyRecording: Bool {
        !recordings.isEmpty
    }

    /// The commentary saved for the current selection in one language, if there is one.
    func recording(for language: NarrationLanguage) -> RecordingInfo? {
        recordings.first { $0.filterTag == selectedTag && $0.language == language.rawValue }
    }

    /// True when `tag` has a commentary in either language. Marks the tag in the picker, exactly
    /// as the web dropdown's music note does.
    func hasRecording(forTag tag: String?) -> Bool {
        recordings.contains { $0.filterTag == tag }
    }

    func name(of language: NarrationLanguage) -> String {
        language == .language1 ? language1Name : language2Name
    }

    /// The album's photos keyed by id, so a commentary's `fileId` can be turned back into
    /// something to render. Built from the unfiltered list — a commentary recorded under one tag
    /// must still resolve while a different one is selected.
    var photosByID: [Int: Photo] {
        Dictionary(allPhotos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Loading

    /// Pulls everything the presentation needs: the album's photos, its section markers, its
    /// commentaries and the two language names.
    ///
    /// The groups and the commentaries are decoration — a presentation with neither is still a
    /// presentation — so a failure to fetch either is left silent rather than put in front of
    /// someone who is trying to read. A failure to fetch the photos is reported: there is
    /// nothing to show without them.
    func load() {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            return
        }

        isLoading = true

        apiClient.fetchFiles(albumId: album.id) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case let .success(response):
                    self.allPhotos = response.files
                    self.rebuildTags()
                    self.rebuildSections()
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }

        apiClient.fetchPresentationGroups(albumId: album.id) { [weak self] result in
            Task { @MainActor in
                guard let self, case let .success(groups) = result else { return }
                self.groups = groups
                self.rebuildSections()
            }
        }

        apiClient.fetchRecordings(albumId: album.id) { [weak self] result in
            Task { @MainActor in
                guard let self, case let .success(recordings) = result else { return }
                self.recordings = recordings
            }
        }

        apiClient.fetchLanguageSettings { [weak self] result in
            Task { @MainActor in
                guard let self, case let .success(response) = result else { return }
                // The server answers with nulls until the user has named them; the web app falls
                // back to the same two defaults.
                self.language1Name = response.language1 ?? "German"
                self.language2Name = response.language2 ?? "English"
            }
        }
    }

    // MARK: - Writing chapters

    /// Starts a chapter at `photo`, running from it until the next one begins.
    ///
    /// - Returns: true when it was stored, so the form knows whether to close.
    func createGroup(startingAt photo: Photo, draft: PresentationGroupDraft) async -> Bool {
        guard let apiClient, let selectedTag else { return false }
        guard !isSavingGroup else { return false }

        isSavingGroup = true
        defer { isSavingGroup = false }

        let result: Result<PresentationGroup, Error> = await withCheckedContinuation { continuation in
            apiClient.createPresentationGroup(
                albumId: album.id,
                tag: selectedTag,
                startFileId: photo.id,
                draft: draft,
            ) { continuation.resume(returning: $0) }
        }

        switch result {
        case let .success(group):
            // The stored group, not the draft: the server trims the label and collapses a blank
            // body to null, and the screen should show what was actually kept.
            groups.append(group)
            rebuildSections()
            return true
        case let .failure(error):
            handleError(error)
            return false
        }
    }

    func updateGroup(_ group: PresentationGroup, draft: PresentationGroupDraft) async -> Bool {
        guard let apiClient else { return false }
        guard !isSavingGroup else { return false }

        isSavingGroup = true
        defer { isSavingGroup = false }

        let result: Result<PresentationGroup, Error> = await withCheckedContinuation { continuation in
            apiClient.updatePresentationGroup(id: group.id, draft: draft) {
                continuation.resume(returning: $0)
            }
        }

        switch result {
        case let .success(updated):
            groups = groups.map { $0.id == updated.id ? updated : $0 }
            rebuildSections()
            return true
        case let .failure(error):
            handleError(error)
            return false
        }
    }

    /// Removes a chapter marker. The photos stay exactly where they are — the caller confirms
    /// first, because the words are gone for good even though the album is untouched.
    func deleteGroup(_ group: PresentationGroup) {
        guard let apiClient else { return }

        apiClient.deletePresentationGroup(id: group.id) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.groups.removeAll { $0.id == group.id }
                    self.rebuildSections()
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }

    // MARK: - Deriving what is shown

    private func rebuildTags() {
        availableTags = PresentationGallery.tagCounts(for: allPhotos)

        // One tag is not a choice — the web gallery selects it rather than making the reader open
        // a picker to pick the only entry. Not done while the map is up: that is a deliberate
        // choice the reader made, and replacing it would take them off the map on every reload.
        if availableTags.count == 1, filter == .unset {
            filter = .tag(availableTags[0].name)
            return
        }

        // A tag that no photo carries any more would present an empty album, so it is dropped
        // back to the prompt rather than left selected.
        if let selectedTag, !availableTags.contains(where: { $0.name == selectedTag }) {
            filter = .unset
        }
    }

    private func rebuildSections() {
        // The map is a view of the album, not a shelving of it.
        guard !needsTagChoice, !isMapMode else {
            sections = []
            return
        }

        let filtered = PresentationGallery.photos(from: allPhotos, tag: selectedTag)
        sections = PresentationGallery.sections(from: filtered, groups: groups, tag: selectedTag)
    }
}
