import Foundation

/// What visitors did with a shared album, as counted by the server.
///
/// Owner-only. The counting itself happens on the public share-token routes, which this app
/// never calls — the phone reads the totals and nothing else. Mirrors `AnalyticsStats` in the
/// web app's `useAnalytics` composable.
///
/// Every count decodes with a zero default. An album nobody has opened answers with nulls, and
/// a screen of blanks reads as a broken request rather than as an album with no visitors.
struct AlbumAnalytics: Codable, Equatable {
    /// True while the album is not counting. The owner sets it; the figures already collected
    /// stay exactly as they are, they simply stop growing.
    var analyticsPaused: Bool

    /// Every recorded event, of every kind. The three counts below do not have to add up to it:
    /// a server that learns a new event type counts it here first.
    var totalEvents: Int

    var uniqueVisitors: Int
    var pageViews: Int
    var filterChanges: Int
    var audioPlays: Int

    /// How often each tag was picked as a filter, keyed by tag name.
    var filterTagCounts: [String: Int]

    /// One tag in the ranked filter list, already scaled for drawing.
    struct FilterRow: Identifiable, Equatable {
        var id: String { tag }
        let tag: String
        let count: Int

        /// This row against the busiest one, 0...1 — the length of its bar. Never quite zero, so
        /// a tag with one event still shows something to aim a tap at.
        let fraction: Double

        /// This row against every filter change, as a whole percentage.
        let share: Int
    }

    /// The busiest tags first, scaled against the top one.
    ///
    /// - Parameter limit: how many rows to return. The rest are counted by
    ///   ``hiddenFilterCount(limit:)`` and named in a footnote rather than drawn — past about
    ///   eight bars the list stops being a comparison and becomes a table.
    func rankedFilters(limit: Int = 8) -> [FilterRow] {
        let sorted = sortedFilters
        let top = sorted.prefix(limit)
        let max = top.first?.value ?? 1
        let total = sorted.reduce(0) { $0 + $1.value }

        return top.map { tag, count in
            FilterRow(
                tag: tag,
                count: count,
                fraction: max > 0 ? Swift.max(0.02, Double(count) / Double(max)) : 0.02,
                share: total > 0 ? Int((Double(count) / Double(total) * 100).rounded()) : 0,
            )
        }
    }

    /// Tags left out of ``rankedFilters(limit:)``.
    func hiddenFilterCount(limit: Int = 8) -> Int {
        Swift.max(0, filterTagCounts.count - limit)
    }

    /// Count descending, then name — two tags on the same count would otherwise swap places
    /// between refreshes, because a dictionary has no order of its own.
    private var sortedFilters: [(key: String, value: Int)] {
        filterTagCounts.sorted { left, right in
            left.value == right.value ? left.key < right.key : left.value > right.value
        }
    }

    init(
        analyticsPaused: Bool = false,
        totalEvents: Int = 0,
        uniqueVisitors: Int = 0,
        pageViews: Int = 0,
        filterChanges: Int = 0,
        audioPlays: Int = 0,
        filterTagCounts: [String: Int] = [:],
    ) {
        self.analyticsPaused = analyticsPaused
        self.totalEvents = totalEvents
        self.uniqueVisitors = uniqueVisitors
        self.pageViews = pageViews
        self.filterChanges = filterChanges
        self.audioPlays = audioPlays
        self.filterTagCounts = filterTagCounts
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        analyticsPaused = try container.decodeIfPresent(Bool.self, forKey: .analyticsPaused) ?? false
        totalEvents = try container.decodeIfPresent(Int.self, forKey: .totalEvents) ?? 0
        uniqueVisitors = try container.decodeIfPresent(Int.self, forKey: .uniqueVisitors) ?? 0
        pageViews = try container.decodeIfPresent(Int.self, forKey: .pageViews) ?? 0
        filterChanges = try container.decodeIfPresent(Int.self, forKey: .filterChanges) ?? 0
        audioPlays = try container.decodeIfPresent(Int.self, forKey: .audioPlays) ?? 0
        filterTagCounts = try container.decodeIfPresent([String: Int].self, forKey: .filterTagCounts) ?? [:]
    }
}
