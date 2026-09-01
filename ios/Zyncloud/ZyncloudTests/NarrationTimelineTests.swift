import Foundation
import Testing

@testable import Zyncloud

/// Which assets a narration walks, and the timings a recording ships.
///
/// The timings are the feature: playback advances the slideshow against them, so a wrong number
/// here is a slideshow out of step with the voice — and nothing about it is visible until
/// somebody plays a recording back.
@MainActor
struct NarrationTimelineTests {
    // MARK: - Fixtures

    private func photo(
        id: Int,
        tags: [String] = [],
        status: String? = "DONE",
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
            displayOrder: nil,
            tags: tags,
            albumId: 7,
            albumName: "Trip",
        )
        file.processingStatus = status
        return file
    }

    // MARK: - Which assets are narratable

    /// A "Processing…" placeholder is nothing to narrate, and a timing entry aimed at one would
    /// point playback at a slide the gallery may render differently once the derivative exists.
    @Test func stillProcessingAssetsAreLeftOut() {
        let ready = NarrationSlides.ready(from: [
            photo(id: 1, status: "DONE"),
            photo(id: 2, status: "QUEUED"),
            photo(id: 3, status: "PROCESSING"),
            photo(id: 4, status: "DONE"),
        ])

        #expect(ready.map(\.id) == [1, 4])
    }

    /// An asset the worker gave up on is not narratable either — there is no thumbnail to show.
    @Test func failedAssetsAreLeftOut() {
        let ready = NarrationSlides.ready(from: [
            photo(id: 1, status: "DONE"),
            photo(id: 2, status: "FAILED"),
            photo(id: 3, status: "DEAD_LETTER"),
        ])

        #expect(ready.map(\.id) == [1])
    }

    /// An older asset carries no status at all. Those predate the pipeline and are perfectly
    /// good slides — excluding them would empty out every old album.
    @Test func assetsWithNoStatusAreStillNarratable() {
        let ready = NarrationSlides.ready(from: [photo(id: 1, status: nil)])

        #expect(ready.map(\.id) == [1])
    }

    /// Album order is the slideshow order. Filtering must not reshuffle it.
    @Test func readyAssetsKeepTheAlbumsOrder() {
        let ready = NarrationSlides.ready(from: (1 ... 10).map { photo(id: $0) })

        #expect(ready.map(\.id) == Array(1 ... 10))
    }

    // MARK: - The tag filter list

    @Test func tagsAreCountedAcrossTheAlbum() {
        let counts = NarrationSlides.tagCounts(for: [
            photo(id: 1, tags: ["beach", "2024"]),
            photo(id: 2, tags: ["beach"]),
            photo(id: 3, tags: ["mountains"]),
        ])

        #expect(counts.map { $0.name } == ["2024", "beach", "mountains"])
        #expect(counts.first { $0.name == "beach" }?.count == 2)
        #expect(counts.first { $0.name == "2024" }?.count == 1)
    }

    /// The count is of *narratable* assets. Counting a processing one would promise a slideshow
    /// longer than the one that runs.
    @Test func tagCountsIgnoreAssetsThatCannotBeNarrated() {
        let counts = NarrationSlides.tagCounts(for: [
            photo(id: 1, tags: ["beach"], status: "DONE"),
            photo(id: 2, tags: ["beach"], status: "QUEUED"),
            photo(id: 3, tags: ["beach"], status: "FAILED"),
        ])

        #expect(counts.first { $0.name == "beach" }?.count == 1)
    }

    /// Sorted case-insensitively, so the list reads naturally and does not reshuffle between
    /// runs — a dictionary's own order is not stable.
    @Test func tagsAreSortedCaseInsensitively() {
        let counts = NarrationSlides.tagCounts(for: [
            photo(id: 1, tags: ["zebra", "Apple", "beach", "Beach2"]),
        ])

        #expect(counts.map { $0.name } == ["Apple", "beach", "Beach2", "zebra"])
    }

    @Test func analbumWithNoTagsOffersNothing() {
        #expect(NarrationSlides.tagCounts(for: [photo(id: 1)]).isEmpty)
        #expect(NarrationSlides.tagCounts(for: []).isEmpty)
    }

    // MARK: - Keeping or dropping the chosen filter

    /// A filter the album no longer has any ready asset for would start an *empty* slideshow.
    /// Falling back to "all photos" is the only useful answer.
    @Test func afilterThatNoLongerMatchesAnythingIsDropped() {
        let available = [(name: "beach", count: 2)]

        #expect(NarrationSlides.survivingFilter("mountains", among: available) == nil)
        #expect(NarrationSlides.survivingFilter("beach", among: available) == "beach")
        #expect(NarrationSlides.survivingFilter(nil, among: available) == nil)
        #expect(NarrationSlides.survivingFilter("beach", among: []) == nil)
    }

    /// Tag names are matched exactly. A near-miss must drop the filter rather than quietly
    /// narrating a different tag.
    @Test func thefilterIsMatchedExactly() {
        let available = [(name: "beach", count: 2)]

        #expect(NarrationSlides.survivingFilter("Beach", among: available) == nil)
        #expect(NarrationSlides.survivingFilter("beach ", among: available) == nil)
        #expect(NarrationSlides.survivingFilter("bea", among: available) == nil)
    }

    // MARK: - The slides a recording walks

    @Test func nofilterWalksEveryNarratableAsset() {
        let slides = NarrationSlides.slides(
            from: [photo(id: 1), photo(id: 2, status: "QUEUED"), photo(id: 3)],
            tag: nil,
        )

        #expect(slides.map(\.id) == [1, 3])
    }

    @Test func afilterNarrowsToThatTagAndKeepsAlbumOrder() {
        let slides = NarrationSlides.slides(
            from: [
                photo(id: 1, tags: ["beach"]),
                photo(id: 2, tags: ["mountains"]),
                photo(id: 3, tags: ["beach", "2024"]),
            ],
            tag: "beach",
        )

        #expect(slides.map(\.id) == [1, 3])
    }

    /// A filtered slideshow still skips what cannot be narrated — the filter and the readiness
    /// gate both apply, not one or the other.
    @Test func afilteredSlideshowStillSkipsUnreadyAssets() {
        let slides = NarrationSlides.slides(
            from: [
                photo(id: 1, tags: ["beach"], status: "DONE"),
                photo(id: 2, tags: ["beach"], status: "PROCESSING"),
            ],
            tag: "beach",
        )

        #expect(slides.map(\.id) == [1])
    }

    // MARK: - Timings

    /// The straightforward run: three slides, ten seconds apart.
    @Test func slidesGetTheirStartAndDurationInMilliseconds() {
        var timeline = NarrationTimeline(startedAt: 100)

        timeline.openSlide(fileId: 1, at: 100)
        timeline.closeCurrentSlide(at: 110)
        timeline.openSlide(fileId: 2, at: 110)
        timeline.closeCurrentSlide(at: 125)
        timeline.openSlide(fileId: 3, at: 125)
        timeline.closeCurrentSlide(at: 130)

        #expect(timeline.timings.map(\.fileId) == [1, 2, 3])
        #expect(timeline.timings.map(\.startTimeMs) == [0, 10000, 25000])
        #expect(timeline.timings.map(\.durationMs) == [10000, 15000, 5000])
        #expect(timeline.totalMilliseconds(at: 130) == 30000)
    }

    /// Starts are measured from the beginning of the audio, not from the previous slide — that
    /// is what playback seeks against.
    @Test func startsAreRelativeToTheStartOfTheAudio() {
        var timeline = NarrationTimeline(startedAt: 1000)

        timeline.openSlide(fileId: 1, at: 1000)
        timeline.closeCurrentSlide(at: 1002)
        timeline.openSlide(fileId: 2, at: 1002)

        #expect(timeline.timings[1].startTimeMs == 2000)
    }

    /// Closing twice is normal — the Stop button and the auto-stop at the end of the list can
    /// both reach it — and the second close must simply re-measure, not append or corrupt.
    @Test func closingTheSameSlideTwiceIsHarmless() {
        var timeline = NarrationTimeline(startedAt: 0)

        timeline.openSlide(fileId: 1, at: 0)
        timeline.closeCurrentSlide(at: 5)
        timeline.closeCurrentSlide(at: 8)

        #expect(timeline.timings.count == 1)
        #expect(timeline.timings[0].durationMs == 8000)
    }

    /// Closing before any slide has opened must not crash on an empty list.
    @Test func closingWithNoSlideOpenIsHarmless() {
        var timeline = NarrationTimeline(startedAt: 0)

        timeline.closeCurrentSlide(at: 5)

        #expect(timeline.timings.isEmpty)
    }

    /// A slide that is closed the instant it opens is legitimate — a fast double tap — and must
    /// come out as zero, not as a negative or a missing entry.
    @Test func azeroLengthSlideIsRecordedAsZero() {
        var timeline = NarrationTimeline(startedAt: 0)

        timeline.openSlide(fileId: 1, at: 3)
        timeline.closeCurrentSlide(at: 3)

        #expect(timeline.timings[0].durationMs == 0)
        #expect(timeline.timings[0].startTimeMs == 3000)
    }

    /// The clock should be monotonic, but a zero-length slide is a far better failure than a
    /// negative one: the server would store a negative, and playback would read it as a slide
    /// that ends before it starts.
    @Test func aclockThatWentBackwardsCannotProduceANegativeDuration() {
        var timeline = NarrationTimeline(startedAt: 100)

        timeline.openSlide(fileId: 1, at: 110)
        timeline.closeCurrentSlide(at: 105)

        #expect(timeline.timings[0].durationMs == 0)
        #expect(timeline.timings[0].startTimeMs == 10000)
        #expect(timeline.totalMilliseconds(at: 90) == 0)
    }

    /// Sub-second timings round to whole milliseconds rather than being truncated to zero.
    @Test func subSecondSlidesKeepTheirMilliseconds() {
        var timeline = NarrationTimeline(startedAt: 0)

        timeline.openSlide(fileId: 1, at: 0)
        timeline.closeCurrentSlide(at: 0.25)

        #expect(timeline.timings[0].durationMs == 250)
    }

    /// A recording that was started and stopped without advancing still ships one entry — the
    /// one slide that was on screen.
    @Test func aone1SlideRecordingShipsOneTiming() {
        var timeline = NarrationTimeline(startedAt: 50)

        timeline.openSlide(fileId: 9, at: 50)
        timeline.closeCurrentSlide(at: 62)

        #expect(timeline.timings.count == 1)
        #expect(timeline.timings[0].fileId == 9)
        #expect(timeline.timings[0].startTimeMs == 0)
        #expect(timeline.timings[0].durationMs == 12000)
    }

    /// The slide durations should account for the whole recording, with no gaps — playback
    /// walks them end to end.
    @Test func theSlideDurationsCoverTheWholeRecording() {
        var timeline = NarrationTimeline(startedAt: 0)
        var now = 0.0

        for id in 1 ... 5 {
            timeline.openSlide(fileId: id, at: now)
            now += Double(id)
            timeline.closeCurrentSlide(at: now)
        }

        let covered = timeline.timings.map(\.durationMs).reduce(0, +)
        #expect(covered == timeline.totalMilliseconds(at: now))
        #expect(timeline.timings.last?.startTimeMs == 10000)
    }

    // MARK: - The duration label

    @Test(arguments: [
        (0, "0:00"),
        (999, "0:00"),
        (1000, "0:01"),
        (59_000, "0:59"),
        (60_000, "1:00"),
        (61_500, "1:01"),
        (600_000, "10:00"),
        (3_661_000, "61:01"),
    ])
    func thedurationLabelReadsAsMinutesAndSeconds(milliseconds: Int, label: String) {
        #expect(NarrationRecorderViewModel.durationLabel(milliseconds) == label)
    }
}
