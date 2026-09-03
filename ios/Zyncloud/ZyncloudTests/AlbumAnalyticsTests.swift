import Foundation
import Testing

@testable import Zyncloud

/// The album's visitor counts: what survives decoding, and how the filter list is ranked.
struct AlbumAnalyticsTests {
    private func decode(_ json: String) throws -> AlbumAnalytics {
        try JSONDecoder().decode(AlbumAnalytics.self, from: Data(json.utf8))
    }

    // MARK: - Decoding

    @Test func afullAnswerDecodes() throws {
        let stats = try decode("""
        {"success":true,"analyticsPaused":true,"totalEvents":42,"uniqueVisitors":7,
         "pageViews":30,"filterChanges":9,"audioPlays":3,
         "filterTagCounts":{"beach":6,"city":3}}
        """)

        #expect(stats.analyticsPaused)
        #expect(stats.totalEvents == 42)
        #expect(stats.uniqueVisitors == 7)
        #expect(stats.pageViews == 30)
        #expect(stats.filterChanges == 9)
        #expect(stats.audioPlays == 3)
        #expect(stats.filterTagCounts == ["beach": 6, "city": 3])
    }

    /// An album nobody has opened answers with nulls. Those are zeros, not a broken response —
    /// throwing here would show an error screen for the ordinary case of a brand-new album.
    @Test func nullCountsReadAsZero() throws {
        let stats = try decode("""
        {"success":true,"analyticsPaused":false,"totalEvents":null,"uniqueVisitors":null,
         "pageViews":null,"filterChanges":null,"audioPlays":null,"filterTagCounts":null}
        """)

        #expect(stats.totalEvents == 0)
        #expect(stats.uniqueVisitors == 0)
        #expect(stats.filterTagCounts.isEmpty)
    }

    @Test func missingKeysReadAsZeroAndCounting() throws {
        let stats = try decode(#"{"success":true}"#)

        #expect(!stats.analyticsPaused)
        #expect(stats.pageViews == 0)
        #expect(stats.filterTagCounts.isEmpty)
    }

    // MARK: - Ranking the filters

    @Test func filtersAreRankedBusiestFirst() {
        let stats = AlbumAnalytics(filterTagCounts: ["beach": 3, "city": 10, "food": 7])

        #expect(stats.rankedFilters().map(\.tag) == ["city", "food", "beach"])
        #expect(stats.rankedFilters().map(\.count) == [10, 7, 3])
    }

    /// A dictionary has no order, so two tags on the same count would swap places between
    /// refreshes and the list would look like it was changing when it was not.
    @Test func atieIsBrokenByName() {
        let stats = AlbumAnalytics(filterTagCounts: ["zebra": 5, "apple": 5])

        #expect(stats.rankedFilters().map(\.tag) == ["apple", "zebra"])
    }

    /// Bar lengths are relative to the busiest tag, and shares are of the whole.
    @Test func barsAreScaledAgainstTheBusiestTag() {
        let stats = AlbumAnalytics(filterTagCounts: ["a": 10, "b": 5])
        let rows = stats.rankedFilters()

        #expect(rows[0].fraction == 1)
        #expect(rows[1].fraction == 0.5)
        #expect(rows[0].share == 67)
        #expect(rows[1].share == 33)
    }

    /// A tag with one event against a tag with thousands would round to a bar of no width, and
    /// an invisible row reads as a missing one.
    @Test func atinyBarStaysVisible() {
        let stats = AlbumAnalytics(filterTagCounts: ["huge": 10000, "tiny": 1])

        #expect(stats.rankedFilters()[1].fraction == 0.02)
    }

    @Test func nofiltersRankToAnEmptyList() {
        #expect(AlbumAnalytics().rankedFilters().isEmpty)
        #expect(AlbumAnalytics().hiddenFilterCount() == 0)
    }

    @Test func thelistIsCappedAndTheRestAreCounted() {
        let counts = Dictionary(uniqueKeysWithValues: (1 ... 12).map { ("tag\($0)", $0) })
        let stats = AlbumAnalytics(filterTagCounts: counts)

        #expect(stats.rankedFilters().count == 8)
        #expect(stats.hiddenFilterCount() == 4)
        #expect(stats.rankedFilters(limit: 3).map(\.tag) == ["tag12", "tag11", "tag10"])
        #expect(stats.hiddenFilterCount(limit: 3) == 9)
    }
}
