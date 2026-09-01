import Foundation
import Testing

@testable import Zyncloud

/// How a presentation is shelved. A port of the web app's `usePresentationGroups`, so the same
/// album has to break into the same chapters here as it does in the browser — a group placed in
/// the web gallery and read on the phone is the whole point of the feature.
struct PresentationGalleryTests {
    private func photo(id: Int, tags: [String] = []) -> Photo {
        FileInfo(
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
    }

    private func group(
        id: Int,
        tag: String = "beach",
        startFileId: Int,
        label: String = "Chapter",
        text: String? = nil,
    ) -> PresentationGroup {
        PresentationGroup(
            id: id,
            albumId: 7,
            tag: tag,
            startFileId: startFileId,
            label: label,
            text: text,
        )
    }

    // MARK: - Tag counts

    /// Sorted case-insensitively so the picker does not reshuffle between visits — a dictionary
    /// walked in its own order would.
    @Test func tagCountsAreSortedByNameIgnoringCase() {
        let counts = PresentationGallery.tagCounts(for: [
            photo(id: 1, tags: ["Zoo"]),
            photo(id: 2, tags: ["apple"]),
            photo(id: 3, tags: ["Bike"]),
        ])

        #expect(counts.map(\.name) == ["apple", "Bike", "Zoo"])
    }

    // MARK: - Sections

    /// With no group for the selected tag the presentation is one unheaded run, not an empty
    /// list — the photos are still there to be read.
    @Test func aTagWithNoGroupsIsOneSectionWithNoHeading() {
        let photos = [photo(id: 1), photo(id: 2)]

        let sections = PresentationGallery.sections(from: photos, groups: [], tag: "beach")

        #expect(sections.count == 1)
        #expect(sections[0].group == nil)
        #expect(sections[0].photos.map(\.id) == [1, 2])
    }

    @Test func anEmptySelectionProducesNoSections() {
        #expect(PresentationGallery.sections(from: [], groups: [], tag: "beach").isEmpty)
    }

    /// A group owns the photo it is anchored to and every following one until the next anchor.
    @Test func eachGroupOwnsItsAnchorAndEveryPhotoUpToTheNextOne() {
        let photos = [photo(id: 1), photo(id: 2), photo(id: 3), photo(id: 4), photo(id: 5)]
        let groups = [
            group(id: 10, startFileId: 2, label: "Morning"),
            group(id: 11, startFileId: 4, label: "Evening"),
        ]

        let sections = PresentationGallery.sections(from: photos, groups: groups, tag: "beach")

        #expect(sections.count == 3)
        #expect(sections[0].group == nil)
        #expect(sections[0].photos.map(\.id) == [1])
        #expect(sections[1].group?.label == "Morning")
        #expect(sections[1].photos.map(\.id) == [2, 3])
        #expect(sections[2].group?.label == "Evening")
        #expect(sections[2].photos.map(\.id) == [4, 5])
    }

    /// Otherwise every presentation whose first photo starts a chapter would open with an empty
    /// unheaded block above it.
    @Test func aGroupOnTheFirstPhotoLeavesNoEmptyLeadSection() {
        let photos = [photo(id: 1), photo(id: 2)]
        let groups = [group(id: 10, startFileId: 1, label: "Opening")]

        let sections = PresentationGallery.sections(from: photos, groups: groups, tag: "beach")

        #expect(sections.count == 1)
        #expect(sections[0].group?.label == "Opening")
        #expect(sections[0].photos.map(\.id) == [1, 2])
    }

    /// A group is scoped to one `(album, tag)` pair. Reading the album under a different tag must
    /// not pick up another tag's chapters.
    @Test func groupsBelongingToAnotherTagAreIgnored() {
        let photos = [photo(id: 1), photo(id: 2)]
        let groups = [group(id: 10, tag: "mountains", startFileId: 1, label: "Wrong tag")]

        let sections = PresentationGallery.sections(from: photos, groups: groups, tag: "beach")

        #expect(sections.count == 1)
        #expect(sections[0].group == nil)
    }

    /// An anchor that is not in the current list — untagged since, deleted, filtered out —
    /// simply stops rendering. That is the whole reason groups are anchors and not membership
    /// lists: there is no orphan state to clean up.
    @Test func aGroupWhoseAnchorIsNotInTheListDoesNotRender() {
        let photos = [photo(id: 1), photo(id: 3)]
        let groups = [group(id: 10, startFileId: 2, label: "Gone")]

        let sections = PresentationGallery.sections(from: photos, groups: groups, tag: "beach")

        #expect(sections.count == 1)
        #expect(sections[0].group == nil)
        #expect(sections[0].photos.map(\.id) == [1, 3])
    }

    /// An album with no tags at all is presented whole — the one case the web gallery shows
    /// without asking for a filter first.
    @Test func noSelectedTagMeansNoGroupsAndOneRun() {
        let photos = [photo(id: 1), photo(id: 2)]
        let groups = [group(id: 10, startFileId: 1)]

        let sections = PresentationGallery.sections(from: photos, groups: groups, tag: nil)

        #expect(sections.count == 1)
        #expect(sections[0].group == nil)
        #expect(sections[0].photos.map(\.id) == [1, 2])
    }

    // MARK: - Filtering

    @Test func filteringKeepsOnlyThePhotosCarryingTheTagAndTheirOrder() {
        let photos = [
            photo(id: 1, tags: ["beach"]),
            photo(id: 2, tags: ["mountains"]),
            photo(id: 3, tags: ["beach", "mountains"]),
        ]

        let filtered = PresentationGallery.photos(from: photos, tag: "beach")

        #expect(filtered.map(\.id) == [1, 3])
    }

    @Test func noTagKeepsEveryPhoto() {
        let photos = [photo(id: 1, tags: ["beach"]), photo(id: 2)]

        #expect(PresentationGallery.photos(from: photos, tag: nil).map(\.id) == [1, 2])
    }

    // MARK: - Chapter marker

    @Test func theChapterNamesTheGroupAndWhereInItThePhotoSits() {
        let photos = [photo(id: 1), photo(id: 2), photo(id: 3)]
        let groups = [group(id: 10, startFileId: 1, label: "Morning", text: "Before the rain.")]
        let sections = PresentationGallery.sections(from: photos, groups: groups, tag: "beach")

        let chapter = PresentationGallery.chapter(in: sections, forPhotoID: 2)

        #expect(chapter?.id == 10)
        #expect(chapter?.label == "Morning")
        #expect(chapter?.text == "Before the rain.")
        #expect(chapter?.position == 2)
        #expect(chapter?.total == 3)
    }

    /// A photo ahead of the first anchor belongs to no chapter, and an empty marker would read
    /// as a bug rather than as an absence.
    @Test func aPhotoAheadOfTheFirstGroupHasNoChapter() {
        let photos = [photo(id: 1), photo(id: 2)]
        let groups = [group(id: 10, startFileId: 2)]
        let sections = PresentationGallery.sections(from: photos, groups: groups, tag: "beach")

        #expect(PresentationGallery.chapter(in: sections, forPhotoID: 1) == nil)
    }

    @Test func aPhotoThatIsNotInTheSelectionHasNoChapter() {
        let sections = PresentationGallery.sections(
            from: [photo(id: 1)],
            groups: [group(id: 10, startFileId: 1)],
            tag: "beach",
        )

        #expect(PresentationGallery.chapter(in: sections, forPhotoID: 99) == nil)
        #expect(PresentationGallery.chapter(in: sections, forPhotoID: nil) == nil)
    }

    /// The marker re-appears on the *id* changing, not the label, so two chapters that happen to
    /// share a name still count as two.
    @Test func adjacentGroupsSharingALabelKeepDistinctIds() {
        let photos = [photo(id: 1), photo(id: 2)]
        let groups = [
            group(id: 10, startFileId: 1, label: "Day"),
            group(id: 11, startFileId: 2, label: "Day"),
        ]
        let sections = PresentationGallery.sections(from: photos, groups: groups, tag: "beach")

        #expect(PresentationGallery.chapter(in: sections, forPhotoID: 1)?.id == 10)
        #expect(PresentationGallery.chapter(in: sections, forPhotoID: 2)?.id == 11)
    }

    // MARK: - The filter

    /// The whole reason the map is its own case and not a sentinel tag name: `selectedTag` feeds
    /// the commentary lookup and the chapter markers, and a sentinel reaching either would be a
    /// silent data bug rather than a compile error (D34).
    @Test func onlyAtagFilterEverNamesAtag() {
        #expect(PresentationFilter.tag("beach").tagName == "beach")
        #expect(PresentationFilter.map.tagName == nil)
        #expect(PresentationFilter.unset.tagName == nil)
    }

    @Test func onlyThemapFilterIsThemap() {
        #expect(PresentationFilter.map.isMap)
        #expect(!PresentationFilter.tag("beach").isMap)
        #expect(!PresentationFilter.unset.isMap)
    }

    // MARK: - Writing a chapter

    /// The rules are the server's `normalizedLabel` / `normalizedText`. The point of having them
    /// here too is that a `TextField` has no `maxlength`, so an over-long value is reachable on
    /// the phone in a way it is not in the browser.
    @Test func alabelIsTrimmedAndRequired() {
        #expect(draft(label: "  Arrival  ")?.label == "Arrival")
        #expect(problem(label: "") == .labelMissing)
        #expect(problem(label: "   \n  ") == .labelMissing)
    }

    @Test func alabelAtTheLimitIsKeptAndOneOverIsRefused() {
        let atLimit = String(repeating: "a", count: PresentationGroupDraft.maxLabelLength)

        #expect(draft(label: atLimit)?.label == atLimit)
        #expect(problem(label: atLimit + "a") == .labelTooLong)
    }

    /// Blank collapses to nil rather than to an empty string, so the heading has one thing to
    /// test — the same collapse the server does on the way in.
    @Test func blankTextBecomesNoTextAtAll() {
        #expect(draft(label: "Arrival", text: "")?.text == nil)
        #expect(draft(label: "Arrival", text: "   ")?.text == nil)
        #expect(draft(label: "Arrival", text: "  Before the rain. ")?.text == "Before the rain.")
    }

    @Test func textOverTheLimitIsRefused() {
        let atLimit = String(repeating: "a", count: PresentationGroupDraft.maxTextLength)

        #expect(draft(label: "Arrival", text: atLimit)?.text == atLimit)
        #expect(problem(label: "Arrival", text: atLimit + "a") == .textTooLong)
    }

    /// A missing label is reported before an over-long body: it is the field the reader has to
    /// fix first, and reporting the other one would send them to the wrong box.
    @Test func themissingLabelIsReportedFirst() {
        let tooLong = String(repeating: "a", count: PresentationGroupDraft.maxTextLength + 1)

        #expect(problem(label: "", text: tooLong) == .labelMissing)
    }

    private func draft(label: String, text: String = "") -> PresentationGroupDraft? {
        try? PresentationGroupDraft.make(label: label, text: text).get()
    }

    private func problem(label: String, text: String = "") -> PresentationGroupDraft.Problem? {
        guard case let .failure(problem) = PresentationGroupDraft.make(label: label, text: text) else {
            return nil
        }
        return problem
    }

    // MARK: - Section identity

    /// The unheaded lead run needs an id that no group can collide with — server ids are
    /// positive, so a negative one is safe.
    @Test func theLeadSectionsIdCannotCollideWithAGroupId() {
        let sections = PresentationGallery.sections(
            from: [photo(id: 1), photo(id: 2)],
            groups: [group(id: 10, startFileId: 2)],
            tag: "beach",
        )

        #expect(sections[0].id == PresentationSection.leadID)
        #expect(sections[1].id == 10)
        #expect(PresentationSection.leadID < 0)
    }
}
