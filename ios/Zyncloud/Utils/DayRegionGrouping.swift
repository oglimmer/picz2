import Foundation

/// "By day and place" — one section per calendar day, and inside it one sub-section per place,
/// where a place is a set of photos that all sit within `radiusMeters` of each other.
///
/// A port of the web app's `dayRegionGrouping.ts`, kept deliberately faithful so the same album
/// breaks into the same sections in both clients. The clustering is *not* a plain "grow a blob
/// while the next photo is near the last one" pass: that chains, so a walk across a city merges
/// into one 20 km "place" even though its ends are nowhere near each other. What runs here is a
/// complete-linkage agglomerative clustering with the merge threshold as a hard cap — two
/// clusters merge only when *every* cross pair is within the radius, so a finished cluster is at
/// most `radiusMeters` across. Merges are tried shortest-edge-first, which is what makes the
/// greedy pass produce the same natural groups a full O(n³) run would.

/// A position in signed decimal degrees (WGS 84), the same frame the server stores.
struct LatLng: Equatable {
    let lat: Double
    let lng: Double
}

/// One place inside a day.
struct RegionCluster: Identifiable {
    let id: String
    let photos: [Photo]

    /// Mean position of the cluster's photos, or nil for the "no location" bucket.
    let center: LatLng?

    /// Largest distance between any two photos in the cluster, in metres (0 for a single one).
    let spreadMeters: Double

    /// False for the one bucket per day that collects photos with no coordinates.
    let located: Bool
}

/// One calendar day.
struct DayGroup: Identifiable {
    /// `YYYY-MM-DD` at the capture location, or `"unknown"` when a photo carries no usable date.
    /// Not the viewer's day — see `dayOf`.
    let id: String

    /// That day at local midnight, for labelling only. Nil for the unknown-date group.
    let date: Date?

    let clusters: [RegionCluster]
    let count: Int
}

/// Default place size: photos in one cluster are never more than this far apart.
let defaultRegionRadiusMeters: Double = 2000

/// Above this many located photos in a single day the exact pass is skipped for a leader pass.
/// Exact merging is O(n²) in both candidate pairs and cross-pair checks, which is nothing for a
/// normal day out and a frozen screen for a bulk import of a whole year stamped with one date.
///
/// Internal rather than private so the tests can build a day either side of it: the two passes
/// are different code, and a test that only ever builds small days never runs the one a real
/// bulk import takes.
let exactPassLimit = 1500

private let earthRadiusMeters: Double = 6_371_008.8

// MARK: - Geometry

/// Great-circle distance in metres.
func haversineMeters(_ a: LatLng, _ b: LatLng) -> Double {
    let toRad = Double.pi / 180
    let dLat = (b.lat - a.lat) * toRad
    let dLng = (b.lng - a.lng) * toRad
    let lat1 = a.lat * toRad
    let lat2 = b.lat * toRad
    let h = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLng / 2), 2)
    return 2 * earthRadiusMeters * asin(min(1, sqrt(h)))
}

/// Local flat projection in metres around `origin`. Over a few kilometres the error against the
/// ellipsoid is centimetres, and it turns the grid bucketing below into plain arithmetic.
private func project(_ point: LatLng, around origin: LatLng) -> (x: Double, y: Double) {
    let toRad = Double.pi / 180
    return (
        x: (point.lng - origin.lng) * toRad * earthRadiusMeters * cos(origin.lat * toRad),
        y: (point.lat - origin.lat) * toRad * earthRadiusMeters
    )
}

private func centroid(of points: [LatLng]) -> LatLng {
    // Mean of unit vectors, so a cluster straddling the ±180° meridian still lands in the middle.
    let toRad = Double.pi / 180
    var x = 0.0, y = 0.0, z = 0.0
    for point in points {
        let lat = point.lat * toRad
        let lng = point.lng * toRad
        x += cos(lat) * cos(lng)
        y += cos(lat) * sin(lng)
        z += sin(lat)
    }
    let n = Double(max(points.count, 1))
    x /= n
    y /= n
    z /= n
    let hyp = (x * x + y * y).squareRoot()
    return LatLng(
        lat: atan2(z, hyp) * 180 / .pi,
        lng: atan2(y, x) * 180 / .pi,
    )
}

// MARK: - Reading a photo

extension Photo {
    /// The capture position, or nil when the photo carries no coordinates.
    var latLng: LatLng? {
        guard let gpsLatitude, let gpsLongitude,
              gpsLatitude.isFinite, gpsLongitude.isFinite
        else {
            return nil
        }
        return LatLng(lat: gpsLatitude, lng: gpsLongitude)
    }

    /// When the photo was taken, preferring what the camera recorded over when it was uploaded.
    /// A true instant, not a wall clock.
    var captureInstant: Date? {
        ISO8601.parse(exifDateTimeOriginal) ?? ISO8601.parse(uploadedAt)
    }
}

/// The server writes instants as ISO-8601, with fractional seconds when it has them and without
/// when it does not, so both shapes have to be tried.
enum ISO8601 {
    private static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return withFractionalSeconds.date(from: text) ?? plain.date(from: text)
    }
}

// MARK: - Days

/// The offset that stands in for photos carrying none of their own: the one most of this
/// album's photos were shot at.
///
/// An album is normally one trip in one place, so a video with a zone-less container, or a photo
/// whose original was purged before the offset column existed, belongs to the same day
/// boundaries as its neighbours — far closer than the viewer's timezone, which is what the
/// remaining nil case falls back to.
private func dominantOffsetSeconds(_ photos: [Photo]) -> Int? {
    var tally: [Int: Int] = [:]
    for photo in photos {
        guard let seconds = photo.captureUtcOffsetSeconds else { continue }
        tally[seconds, default: 0] += 1
    }
    // Ties broken by the smaller offset so the answer does not wander between runs.
    return tally.max { left, right in
        left.value != right.value ? left.value < right.value : left.key > right.key
    }?.key
}

/// The calendar day a photo belongs to, as `YYYY-MM-DD` plus a local-midnight `Date` to label it
/// with.
///
/// Cut on the wall clock where the shutter fired, never on the viewer's: the capture instant is a
/// true instant, so reading its day in Frankfurt puts a Toronto photo taken at 19:00 into the
/// next day. Adding the capture offset back and then reading UTC fields gives the camera's own
/// clock. With no offset anywhere the viewer's timezone is all that is left, which is correct for
/// photos taken at home.
func dayOf(_ instant: Date, offsetSeconds: Int?) -> (key: String, date: Date?) {
    var calendar = Calendar(identifier: .gregorian)
    let moment: Date

    if let offsetSeconds {
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        moment = instant.addingTimeInterval(TimeInterval(offsetSeconds))
    } else {
        calendar.timeZone = .current
        moment = instant
    }

    let parts = calendar.dateComponents([.year, .month, .day], from: moment)
    guard let year = parts.year, let month = parts.month, let day = parts.day else {
        return ("unknown", nil)
    }

    let key = String(format: "%04d-%02d-%02d", year, month, day)

    // Local midnight of that day: only its year/month/day are ever read back, by the label.
    var localMidnight = Calendar(identifier: .gregorian)
    localMidnight.timeZone = .current
    let date = localMidnight.date(from: DateComponents(year: year, month: month, day: day))

    return (key, date)
}

// MARK: - Clustering

private struct Cluster {
    var members: [Int]
    var spread: Double
}

/// Groups indices of `points` so that no cluster is wider than `radius`.
///
/// Candidate pairs come from a uniform grid with cells one radius wide, so only the 3×3 cell
/// neighbourhood of each point is examined instead of all pairs. Those pairs are then merged
/// shortest-first under the complete-linkage rule.
private func completeLinkageCluster(_ points: [LatLng], radius: Double) -> [Cluster] {
    let n = points.count
    if n == 0 { return [] }
    if n == 1 { return [Cluster(members: [0], spread: 0)] }

    let origin = points[0]
    let flat = points.map { project($0, around: origin) }

    // --- Candidate pairs via a radius-wide grid ---------------------------------------------
    struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    func cell(of index: Int) -> Cell {
        Cell(
            x: Int((flat[index].x / radius).rounded(.down)),
            y: Int((flat[index].y / radius).rounded(.down)),
        )
    }

    var cells: [Cell: [Int]] = [:]
    for index in 0 ..< n {
        cells[cell(of: index), default: []].append(index)
    }

    struct Edge {
        let a: Int
        let b: Int
        let distance: Double
    }

    var edges: [Edge] = []
    for index in 0 ..< n {
        let home = cell(of: index)
        for dx in -1 ... 1 {
            for dy in -1 ... 1 {
                guard let bucket = cells[Cell(x: home.x + dx, y: home.y + dy)] else { continue }
                for other in bucket where other > index { // each unordered pair once
                    let distance = haversineMeters(points[index], points[other])
                    if distance <= radius {
                        edges.append(Edge(a: index, b: other, distance: distance))
                    }
                }
            }
        }
    }
    edges.sort { $0.distance < $1.distance }

    // --- Merge shortest-first, but only when the whole merged set stays inside the radius ----
    var owner = Array(0 ..< n)
    var clusters: [Cluster?] = (0 ..< n).map { Cluster(members: [$0], spread: 0) }

    for edge in edges {
        let idA = owner[edge.a]
        let idB = owner[edge.b]
        if idA == idB { continue }
        guard let a = clusters[idA], let b = clusters[idB] else { continue }

        var worst = max(a.spread, b.spread)
        var joinable = true
        outer: for i in a.members {
            for j in b.members {
                let distance = haversineMeters(points[i], points[j])
                if distance > radius {
                    joinable = false
                    break outer
                }
                if distance > worst { worst = distance }
            }
        }
        if !joinable { continue }

        // Fold the smaller side in, so the owner rewrite stays cheap.
        let keepId = a.members.count >= b.members.count ? idA : idB
        let dropId = keepId == idA ? idB : idA
        guard let drop = clusters[dropId] else { continue }
        for i in drop.members { owner[i] = keepId }
        clusters[keepId]?.members.append(contentsOf: drop.members)
        clusters[keepId]?.spread = worst
        clusters[dropId] = nil
    }

    return clusters.compactMap { $0 }
}

/// Fallback for very large days: one pass that opens a new cluster whenever a photo is further
/// than half a radius from every existing cluster's leader. Half, because two photos on opposite
/// sides of a leader are then still within a full radius of each other — the diameter guarantee
/// of the exact pass survives, only the choice of groups is cruder.
private func leaderCluster(_ points: [LatLng], radius: Double) -> [Cluster] {
    let half = radius / 2
    var leaderPoints: [LatLng] = []
    var clusters: [Cluster] = []

    for index in points.indices {
        var best: Int?
        var bestDistance = Double.infinity
        for leader in leaderPoints.indices {
            let distance = haversineMeters(points[index], leaderPoints[leader])
            if distance <= half, distance < bestDistance {
                best = leader
                bestDistance = distance
            }
        }
        if let best {
            clusters[best].members.append(index)
            clusters[best].spread = max(clusters[best].spread, bestDistance * 2)
        } else {
            leaderPoints.append(points[index])
            clusters.append(Cluster(members: [index], spread: 0))
        }
    }

    return clusters
}

// MARK: - The grouping itself

/// Splits photos into day sections, each split again into places of at most `radiusMeters`.
///
/// Days, the places inside a day, and the photos inside a place all keep the order they had in
/// `photos` (the album's own order): the grouping re-shelves the album, it does not re-sort it.
/// Photos with no usable date land in a trailing "unknown" day; photos with no coordinates land
/// in a trailing bucket of their own day.
func groupByDayAndRegion(
    _ photos: [Photo],
    radiusMeters: Double = defaultRegionRadiusMeters,
) -> [DayGroup] {
    var order: [String] = []
    var days: [String: (date: Date?, photos: [Photo])] = [:]
    let fallbackOffsetSeconds = dominantOffsetSeconds(photos)

    for photo in photos {
        let at = photo.captureInstant.map {
            dayOf($0, offsetSeconds: photo.captureUtcOffsetSeconds ?? fallbackOffsetSeconds)
        }
        let key = at?.key ?? "unknown"
        if days[key] == nil {
            days[key] = (date: at?.date, photos: [])
            order.append(key)
        }
        days[key]?.photos.append(photo)
    }

    return order.compactMap { key -> DayGroup? in
        guard let day = days[key] else { return nil }

        var located: [Photo] = []
        var points: [LatLng] = []
        var unlocated: [Photo] = []
        for photo in day.photos {
            if let at = photo.latLng {
                located.append(photo)
                points.append(at)
            } else {
                unlocated.append(photo)
            }
        }

        var raw = points.count > exactPassLimit
            ? leaderCluster(points, radius: radiusMeters)
            : completeLinkageCluster(points, radius: radiusMeters)

        // Album order decides which place comes first and how photos sit inside it.
        for index in raw.indices {
            raw[index].members.sort()
        }
        raw.sort { ($0.members.first ?? 0) < ($1.members.first ?? 0) }

        var clusters: [RegionCluster] = raw.map { cluster in
            let clusterPhotos = cluster.members.map { located[$0] }
            return RegionCluster(
                id: "\(key):loc:\(clusterPhotos.first?.id ?? 0)",
                photos: clusterPhotos,
                center: centroid(of: cluster.members.map { points[$0] }),
                spreadMeters: cluster.spread,
                located: true,
            )
        }

        if !unlocated.isEmpty {
            clusters.append(RegionCluster(
                id: "\(key):nogps",
                photos: unlocated,
                center: nil,
                spreadMeters: 0,
                located: false,
            ))
        }

        return DayGroup(id: key, date: day.date, clusters: clusters, count: day.photos.count)
    }
}

// MARK: - Labels

/// "1.2 km" / "800 m" — the span quoted next to a place heading.
func formatDistance(_ meters: Double) -> String {
    guard meters.isFinite, meters > 0 else { return "0 m" }
    if meters < 1000 {
        return "\(Int((meters / 10).rounded()) * 10) m"
    }
    return String(format: "%.1f km", meters / 1000)
}

/// "48.137, 11.575" — the place label used when no name is available.
func formatCoordinates(_ at: LatLng) -> String {
    String(format: "%.3f, %.3f", at.lat, at.lng)
}

/// "Monday, 4 May 2026" in the device's locale; "Date unknown" for the trailing group.
func formatDayLabel(_ day: DayGroup) -> String {
    guard let date = day.date else { return "Date unknown" }
    let formatter = DateFormatter()
    formatter.dateStyle = .full
    formatter.timeStyle = .none
    return formatter.string(from: date)
}
