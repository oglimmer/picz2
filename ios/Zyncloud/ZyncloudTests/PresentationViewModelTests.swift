import Foundation
import Testing
@testable import Zyncloud

/// The rules the presentation screen asks before it draws anything: whether to put up the tag
/// prompt, whether the map is even offered, which chapter a photo anchors, which commentary
/// belongs to the current selection.
///
/// ``PresentationGalleryTests`` already covers the shelving itself. What is left here is the
/// gating around it — the part that decides *whether* to shelve, and under what. Each of those
/// rules fails silently: an album that shows a prompt it should have skipped, or a map that is
/// simply not offered, looks like a design decision rather than a bug.
///
/// Driven through ``PresentationViewModel/load()`` against the stub rather than by setting
/// state, because every one of these properties is derived from `private(set)` state that only
/// a load fills in. That makes each test a small end-to-end of the screen coming up.
///
/// Serialized for the usual reason: the stub intercepts `URLSession.shared`, which is
/// process-wide.
@Suite(.serialized)
@MainActor
struct PresentationViewModelTests {
    // MARK: - Fixtures

    private static let trip = Album(
        id: 7,
        name: "Trip",
        description: nil,
        createdAt: nil,
        updatedAt: nil,
        displayOrder: nil,
        fileCount: nil,
        coverImageFilename: nil,
        coverImageToken: nil,
        shareToken: "share-tok",
    )

    private func photo(
        _ id: Int,
        tags: [String] = [],
        lat: Double? = nil,
        lng: Double? = nil,
    ) -> Photo {
        var file = FileInfo(
            id: id,
            originalName: "shot\(id).jpg",
            filename: "shot\(id).jpg",
            publicToken: "tok\(id)",
            size: 42,
            mimetype: "image/jpeg",
            path: nil,
            uploadedAt: "2026-05-04T12:00:00Z",
            displayOrder: id,
            tags: tags,
            albumId: 7,
            albumName: "Trip",
        )
        file.gpsLatitude = lat
        file.gpsLongitude = lng
        return file
    }

    private func group(_ id: Int, tag: String, startsAt fileId: Int, label: String = "Chapter") -> PresentationGroup {
        PresentationGroup(id: id, albumId: 7, tag: tag, startFileId: fileId, label: label, text: nil)
    }

    private func recording(_ id: Int, tag: String?, language: NarrationLanguage) -> RecordingInfo {
        RecordingInfo(
            id: id,
            albumId: 7,
            filterTag: tag,
            language: language.rawValue,
            audioFilename: "voice\(id).webm",
            publicToken: "rtok\(id)",
            durationMs: 30000,
            createdAt: nil,
            images: nil,
        )
    }

    // MARK: - Driving one load

    private func json(_ value: some Encodable) -> String {
        String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
    }

    /// Waits for `condition` to hold, or gives up. ``PresentationViewModel/load()`` fans out to
    /// four endpoints and reports through `@Published` rather than through anything awaitable,
    /// so there is nothing to `await` on. Copied in spirit from ``ImageLoaderIsolationTests``.
    private func eventually(
        _ label: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool,
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("timed out waiting for \(label)")
    }

    /// Brings a presentation up against a stubbed server and hands it to `act` once all four
    /// answers have landed.
    ///
    /// The wait is on every one of them, not just the photos: the groups and the commentaries
    /// arrive on their own requests, so asserting after only the photos had landed would make
    /// half of these tests pass on an empty fixture some of the time.
    private func presenting(
        album: Album = PresentationViewModelTests.trip,
        photos: [Photo],
        groups: [PresentationGroup] = [],
        recordings: [RecordingInfo] = [],
        language1: String? = "Deutsch",
        language2: String? = "Englisch",
        _ act: (PresentationViewModel) async -> Void,
    ) async {
        let files = json(FilesResponse(success: true, files: photos, count: photos.count, totalSize: nil))
        let groupList = json(PresentationGroupsListResponse(success: true, count: groups.count, groups: groups))
        let recordingList = json(
            RecordingsListResponse(success: true, count: recordings.count, recordings: recordings),
        )
        let languages = json(
            LanguageSettingsResponse(success: true, language1: language1, language2: language2),
        )

        let model = PresentationViewModel(album: album, apiClient: .stubbed)

        _ = await StubServer.routing({ request in
            switch request.path {
            case "/api/albums/7/files": (200, files)
            case "/api/albums/7/presentation-groups": (200, groupList)
            case "/api/albums/7/recordings": (200, recordingList)
            case "/api/settings/languages": (200, languages)
            // Deliberately an empty envelope rather than a failure: an endpoint added to
            // `load()` later should show up here as a missing fixture, not as a network error.
            default: (200, "{\"success\":true}")
            }
        }, {
            model.load()
            await eventually("the presentation to finish loading") {
                !model.isLoading
                    && model.allPhotos.count == photos.count
                    && model.groups.count == groups.count
                    && model.recordings.count == recordings.count
                    && model.language1Name != "Language 1"
            }
            await act(model)
        })
    }

    // MARK: - Whether to ask for a tag

    /// One tag is not a choice. The web gallery selects the only entry rather than making the
    /// reader open a picker to pick it, and the phone has to agree or the same album reads
    /// differently on the two clients.
    @Test func `theonly tag is selected rather than asked about`() async {
        await presenting(photos: [photo(1, tags: ["beach"]), photo(2, tags: ["beach"])]) { model in
            #expect(model.filter == .tag("beach"))
            #expect(model.needsTagChoice == false)
            #expect(model.selectedTag == "beach")
            #expect(model.sections.flatMap(\.photos).count == 2)
        }
    }

    /// Two tags are a choice, so nothing is shown until one is made. An unfiltered presentation
    /// is as long as the album and says nothing.
    @Test func `twotags leave the prompt up and shelve nothing`() async {
        await presenting(photos: [photo(1, tags: ["beach"]), photo(2, tags: ["hike"])]) { model in
            #expect(model.filter == .unset)
            #expect(model.needsTagChoice)
            #expect(model.sections.isEmpty)
        }
    }

    /// An album with no tags at all is the one case shown unfiltered — there is nothing to ask.
    @Test func `analbum with no tags is shown whole with no prompt`() async {
        await presenting(photos: [photo(1), photo(2, tags: ["no_tag"])]) { model in
            #expect(model.availableTags.isEmpty)
            #expect(model.needsTagChoice == false)
            #expect(model.selectedTag == nil)
            #expect(model.sections.flatMap(\.photos).map(\.id) == [1, 2])
        }
    }

    /// `no_tag` is the server's marker for "this photo carries none". Offering it as something to
    /// present under would say the opposite of what it means.
    @Test func `nottag is never offered as A tag`() async {
        await presenting(photos: [photo(1, tags: ["no_tag", "beach"]), photo(2, tags: ["no_tag"])]) { model in
            #expect(model.availableTags.map(\.name) == ["beach"])
        }
    }

    /// A tag that no photo carries any more would present an empty album, so the selection is
    /// dropped back to the prompt on the next load rather than left pointing at nothing.
    ///
    /// Two loads against a changing album, so this one drives the stub itself rather than going
    /// through ``presenting(album:photos:groups:recordings:language1:language2:_:)``.
    @Test func `aselected tag that vanishes drops back to the prompt`() async {
        let before = [photo(1, tags: ["beach"]), photo(2, tags: ["hike"])]
        let after = [photo(2, tags: ["hike"]), photo(3, tags: ["hike"])]
        let album = Album2Loads(
            first: json(FilesResponse(success: true, files: before, count: 2, totalSize: nil)),
            second: json(FilesResponse(success: true, files: after, count: 2, totalSize: nil)),
        )
        let languages = json(LanguageSettingsResponse(success: true, language1: "Deutsch", language2: "Englisch"))

        let model = PresentationViewModel(album: Self.trip, apiClient: .stubbed)

        _ = await StubServer.routing({ request in
            if request.path == "/api/albums/7/files" {
                return (200, album.nextFiles())
            }
            if request.path == "/api/settings/languages" {
                return (200, languages)
            }
            return (200, "{\"success\":true}")
        }, {
            model.load()
            await eventually("the first load") {
                !model.isLoading && model.allPhotos.map(\.id) == [1, 2] && model.language1Name != "Language 1"
            }

            model.filter = .tag("beach")
            #expect(model.selectedTag == "beach")

            // The same album after the beach photos were untagged.
            model.load()
            await eventually("the second load") {
                !model.isLoading && model.allPhotos.map(\.id) == [2, 3]
            }

            #expect(model.filter == .unset)
            #expect(model.needsTagChoice)
            #expect(model.sections.isEmpty)
        })
    }

    /// Hands out one body for the first `/files` request and another for every one after, so a
    /// test can reload the same album after it changed. Locked: the route closure runs on the
    /// URL loading thread, not the main actor.
    private final class Album2Loads: @unchecked Sendable {
        private let lock = NSLock()
        private let first: String
        private let second: String
        private var served = 0

        init(first: String, second: String) {
            self.first = first
            self.second = second
        }

        func nextFiles() -> String {
            lock.lock()
            defer { lock.unlock() }
            served += 1
            return served == 1 ? first : second
        }
    }

    // MARK: - Whether the map is offered

    /// Not gated on the server's `maps.enabled` capability, deliberately: that flag says the
    /// server holds an Apple key for MapKit **JS**, which native MapKit does not need. Gating on
    /// it would hide a map that works.
    @Test func `themap is offered when any photo carries A location`() async {
        await presenting(photos: [photo(1, tags: ["beach"]), photo(2, tags: ["beach"], lat: 48.1, lng: 11.5)]) { model in
            #expect(model.mapAvailable)
        }
    }

    @Test func `themap is not offered when no photo carries one`() async {
        await presenting(photos: [photo(1, tags: ["beach"]), photo(2, tags: ["beach"])]) { model in
            #expect(model.mapAvailable == false)
        }
    }

    /// Half a location is no location — a photo with a latitude and no longitude would put a pin
    /// on the prime meridian.
    @Test func `ahalf located photo does not offer the map`() async {
        await presenting(photos: [photo(1, tags: ["beach"], lat: 48.1, lng: nil)]) { model in
            #expect(model.mapAvailable == false)
        }
    }

    /// One tag and no map is not a choice — the tag is already selected, so a picker offering the
    /// one thing that is on screen is noise.
    @Test func `one tag and no map offers no choice`() async {
        await presenting(photos: [photo(1, tags: ["beach"])]) { model in
            #expect(model.offersFilterChoice == false)
        }
    }

    /// One tag *and* a map is a choice, or the map would be unreachable — the picker is the only
    /// way to it.
    @Test func `one tag with A map still offers A choice`() async {
        await presenting(photos: [photo(1, tags: ["beach"], lat: 48.1, lng: 11.5)]) { model in
            #expect(model.offersFilterChoice)
        }
    }

    @Test func `twotags offer A choice with or without A map`() async {
        await presenting(photos: [photo(1, tags: ["beach"]), photo(2, tags: ["hike"])]) { model in
            #expect(model.offersFilterChoice)
        }
    }

    // MARK: - The map is a view, not a shelving

    /// Choosing the map clears the tag rather than intersecting with it, so nothing downstream —
    /// chapters, commentaries — can end up scoped to a tag the reader is not looking at.
    @Test func `themap mode selects no tag and shelves nothing`() async {
        await presenting(
            photos: [photo(1, tags: ["beach"], lat: 48.1, lng: 11.5), photo(2, tags: ["hike"])],
            groups: [group(10, tag: "beach", startsAt: 1)],
        ) { model in
            model.filter = .map

            #expect(model.isMapMode)
            #expect(model.selectedTag == nil)
            #expect(model.sections.isEmpty)
            #expect(model.orderedPhotos.isEmpty)
        }
    }

    /// Chapters belong to one `(album, tag)` pair, so there has to be a tag. The map selects
    /// none, and neither does the opening prompt.
    @Test func `chapters can only be written with A tag selected`() async {
        await presenting(photos: [photo(1, tags: ["beach"]), photo(2, tags: ["hike"])]) { model in
            #expect(model.canManageGroups == false) // the prompt

            model.filter = .map
            #expect(model.canManageGroups == false)

            model.filter = .tag("beach")
            #expect(model.canManageGroups)
        }
    }

    /// Read-only here. The framing is set from the album's own map screen, which is where the
    /// controls are.
    @Test func `thesaved map view is the albums own`() async {
        var framed = Self.trip
        framed.mapCenterLat = 48.1
        framed.mapCenterLng = 11.5
        framed.mapSpanLat = 0.2
        framed.mapSpanLng = 0.3

        await presenting(album: framed, photos: [photo(1, tags: ["beach"], lat: 48.1, lng: 11.5)]) { model in
            #expect(model.savedMapView?.centerLat == 48.1)
            #expect(model.savedMapView?.spanLng == 0.3)
        }

        await presenting(photos: [photo(1, tags: ["beach"], lat: 48.1, lng: 11.5)]) { model in
            #expect(model.savedMapView == nil)
        }
    }

    // MARK: - Which chapter a photo anchors

    /// A photo anchors at most one chapter *per tag*. The same photo anchoring a chapter under a
    /// different tag must not be offered as "a chapter already starts here".
    @Test func `group starting at ignores chapters belonging to another tag`() async {
        await presenting(
            photos: [photo(1, tags: ["beach", "hike"]), photo(2, tags: ["beach"])],
            groups: [group(10, tag: "beach", startsAt: 1, label: "Sand"),
                     group(11, tag: "hike", startsAt: 1, label: "Uphill")],
        ) { model in
            model.filter = .tag("beach")

            #expect(model.groupStarting(at: 1)?.label == "Sand")
            #expect(model.groupStarting(at: 2) == nil)
        }
    }

    /// No tag, no chapter lookup — the map and the prompt both select none, and answering with a
    /// chapter there would offer to edit something the reader cannot see.
    @Test func `group starting at is nil with no tag selected`() async {
        await presenting(
            photos: [photo(1, tags: ["beach"], lat: 48.1, lng: 11.5), photo(2, tags: ["hike"])],
            groups: [group(10, tag: "beach", startsAt: 1)],
        ) { model in
            #expect(model.groupStarting(at: 1) == nil) // the prompt

            model.filter = .map
            #expect(model.groupStarting(at: 1) == nil)
        }
    }

    /// The full-screen pager walks `orderedPhotos`, the grid draws `sections`. They cannot drift
    /// or a swipe lands on a photo the grid never showed.
    @Test func `ordered photos is exactly what the sections hold`() async {
        await presenting(
            photos: [photo(1, tags: ["beach"]), photo(2, tags: ["hike"]), photo(3, tags: ["beach"])],
            groups: [group(10, tag: "beach", startsAt: 3)],
        ) { model in
            model.filter = .tag("beach")

            #expect(model.orderedPhotos.map(\.id) == [1, 3])
            #expect(model.orderedPhotos.map(\.id) == model.sections.flatMap(\.photos).map(\.id))
        }
    }

    /// Built from the unfiltered list on purpose: a commentary recorded under one tag still has
    /// to resolve its slides while a different tag is selected.
    @Test func `photos by ID still resolves photos the filter excludes`() async {
        await presenting(photos: [photo(1, tags: ["beach"]), photo(2, tags: ["hike"])]) { model in
            model.filter = .tag("beach")

            #expect(model.orderedPhotos.map(\.id) == [1])
            #expect(model.photosByID[2]?.id == 2)
        }
    }

    // MARK: - Which commentary belongs to the selection

    /// A recording is looked up by `(tag, language)`. Handing back one recorded under a different
    /// tag would play the wrong voice over the right pictures.
    @Test func `acommentary is matched on both tag and language`() async {
        await presenting(
            photos: [photo(1, tags: ["beach"]), photo(2, tags: ["hike"])],
            recordings: [recording(1, tag: "beach", language: .language1),
                         recording(2, tag: "hike", language: .language2)],
        ) { model in
            model.filter = .tag("beach")
            #expect(model.recording(for: .language1)?.id == 1)
            #expect(model.recording(for: .language2) == nil)

            model.filter = .tag("hike")
            #expect(model.recording(for: .language1) == nil)
            #expect(model.recording(for: .language2)?.id == 2)
        }
    }

    /// Marks the tag in the picker, exactly as the web dropdown's music note does — so the audio
    /// is not a thing you only find by guessing the right filter.
    @Test func `has recording marks only the tags that have one`() async {
        await presenting(
            photos: [photo(1, tags: ["beach"]), photo(2, tags: ["hike"])],
            recordings: [recording(1, tag: "beach", language: .language1)],
        ) { model in
            #expect(model.hasRecording(forTag: "beach"))
            #expect(model.hasRecording(forTag: "hike") == false)
            #expect(model.hasAnyRecording)
        }
    }

    @Test func `analbum with no commentaries says so`() async {
        await presenting(photos: [photo(1, tags: ["beach"]), photo(2, tags: ["hike"])]) { model in
            #expect(model.hasAnyRecording == false)
            #expect(model.hasRecording(forTag: "beach") == false)
        }
    }

    /// A commentary over the whole album carries a null tag. It belongs to the untagged album,
    /// not to every tag in a tagged one.
    @Test func `awhole album commentary belongs to the null tag`() async {
        await presenting(
            photos: [photo(1), photo(2)],
            recordings: [recording(1, tag: nil, language: .language1)],
        ) { model in
            #expect(model.selectedTag == nil)
            #expect(model.recording(for: .language1)?.id == 1)
            #expect(model.hasRecording(forTag: nil))
        }
    }

    // MARK: - What the two languages are called

    @Test func `thelanguage names come from the account settings`() async {
        await presenting(
            photos: [photo(1, tags: ["beach"])],
            language1: "Bairisch",
            language2: "Kiwi",
        ) { model in
            #expect(model.name(of: .language1) == "Bairisch")
            #expect(model.name(of: .language2) == "Kiwi")
        }
    }

    /// The server answers with nulls until the user has named them. The web app falls back to the
    /// same two words, so an unnamed slot reads identically on both clients.
    @Test func `unnamed language slots fall back to the web apps defaults`() async {
        await presenting(
            photos: [photo(1, tags: ["beach"])],
            language1: nil,
            language2: nil,
        ) { model in
            #expect(model.name(of: .language1) == "German")
            #expect(model.name(of: .language2) == "English")
        }
    }
}
