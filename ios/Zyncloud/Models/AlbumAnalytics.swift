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

    // MARK: Full-screen looks (D90)

    /// Photos opened from the grid or the map on the share page.
    var imageOpens: Int

    /// Photos reached with next/previous while already full screen.
    var imageWalkIns: Int

    /// Distinct photos looked at full screen at least once.
    var imagesViewed: Int

    /// Photos a visitor could look at: pictures and videos that are not hidden.
    var imagesInAlbum: Int

    /// The most looked-at photos, busiest first, at most 50.
    var topImages: [ImageViews]

    /// One photo's looks, as the server ranks them.
    struct ImageViews: Codable, Equatable, Identifiable {
        var id: Int { fileId }
        let fileId: Int
        let publicToken: String
        let originalName: String
        let mimeType: String?
        let opens: Int
        let walkIns: Int

        /// Distinct visitors who looked at it full screen.
        let viewers: Int

        var total: Int { opens + walkIns }
    }

    /// Photos nobody opened full screen. Clamped, because a photo hidden after it was looked at
    /// still counts as viewed but no longer counts as in the album.
    var imagesNeverViewed: Int {
        Swift.max(0, imagesInAlbum - imagesViewed)
    }

    /// The share of the album anyone looked at up close, as a whole percentage.
    var viewedShare: Int {
        guard imagesInAlbum > 0 else { return 0 }
        let viewed = Swift.min(imagesViewed, imagesInAlbum)
        return Int((Double(viewed) / Double(imagesInAlbum) * 100).rounded())
    }

    /// Each photo's bar length against the busiest one, 0...1. Never quite zero, like
    /// ``FilterRow/fraction``.
    func lookFraction(_ row: ImageViews) -> Double {
        let max = topImages.map(\.total).max() ?? 0
        guard max > 0 else { return 0.02 }
        return Swift.max(0.02, Double(row.total) / Double(max))
    }

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
        imageOpens: Int = 0,
        imageWalkIns: Int = 0,
        imagesViewed: Int = 0,
        imagesInAlbum: Int = 0,
        topImages: [ImageViews] = [],
    ) {
        self.analyticsPaused = analyticsPaused
        self.totalEvents = totalEvents
        self.uniqueVisitors = uniqueVisitors
        self.pageViews = pageViews
        self.filterChanges = filterChanges
        self.audioPlays = audioPlays
        self.filterTagCounts = filterTagCounts
        self.imageOpens = imageOpens
        self.imageWalkIns = imageWalkIns
        self.imagesViewed = imagesViewed
        self.imagesInAlbum = imagesInAlbum
        self.topImages = topImages
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
        imageOpens = try container.decodeIfPresent(Int.self, forKey: .imageOpens) ?? 0
        imageWalkIns = try container.decodeIfPresent(Int.self, forKey: .imageWalkIns) ?? 0
        imagesViewed = try container.decodeIfPresent(Int.self, forKey: .imagesViewed) ?? 0
        imagesInAlbum = try container.decodeIfPresent(Int.self, forKey: .imagesInAlbum) ?? 0
        topImages = try container.decodeIfPresent([ImageViews].self, forKey: .topImages) ?? []
    }
}
