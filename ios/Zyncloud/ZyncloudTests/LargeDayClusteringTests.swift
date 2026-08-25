import Foundation
import Testing

@testable import Zyncloud

/// The clustering pass that only a big day ever reaches.
///
/// ``groupByDayAndRegion`` runs an exact complete-linkage pass up to ``exactPassLimit`` located
/// photos in one day, and a much cruder leader pass above it. Those are two different pieces of
/// code, and every other grouping test builds days of a handful of photos — so the pass that a
/// real bulk import actually takes had no test at all. These build days either side of the
/// threshold and check that the promises the exact pass makes survive the swap.
struct LargeDayClusteringTests {
    // MARK: - Fixtures

    /// All photos share one capture date and one offset, so they land in a single day group and
    /// the clustering is the only thing under test.
    private func photo(id: Int, lat: Double?, lng: Double?) -> Photo {
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
            tags: [],
            albumId: 7,
            albumName: "Trip",
        )
        file.exifDateTimeOriginal = "2026-05-04T12:00:00Z"
        file.captureUtcOffsetSeconds = 0
        file.gpsLatitude = lat
        file.gpsLongitude = lng
        return file
    }

    private func latOffset(metres: Double) -> Double {
        metres / 111_195.0
    }

    /// `count` photos scattered within a few metres of `lat`/`lng` — one place by any reading.
    private func blob(count: Int, firstId: Int, lat: Double, lng: Double) -> [Photo] {
        (0 ..< count).map { index in
            photo(
                id: firstId + index,
                lat: lat + latOffset(metres: Double(index % 20)),
                lng: lng,
            )
        }
    }

    private func located(_ day: DayGroup) -> [RegionCluster] {
        day.clusters.filter(\.located)
    }

    /// The widest gap between any two photos in a cluster, which is what "a place is at most
    /// `radius` across" actually claims.
    private func trueDiameter(of cluster: RegionCluster) -> Double {
        let points = cluster.photos.compactMap(\.latLng)
        var worst = 0.0
        for i in points.indices {
            for j in points.indices where j > i {
                worst = max(worst, haversineMeters(points[i], points[j]))
            }
        }
        return worst
    }

    // MARK: - The threshold itself

    /// The pass swaps at `exactPassLimit` *located* photos in one day. Both sides have to answer
    /// the same obvious question the same way, or the same album re-shelves itself the moment one
    /// more photo is added to it.
    @Test func bothPassesAgreeOnThreeFarApartPlaces() {
        for count in [exactPassLimit - 3, exactPassLimit + 300] {
            let perPlace = count / 3
            let photos = blob(count: perPlace, firstId: 0, lat: 48.0, lng: 11.0)
                + blob(count: perPlace, firstId: 10000, lat: 49.0, lng: 11.0)
                + blob(count: count - 2 * perPlace, firstId: 20000, lat: 50.0, lng: 11.0)

            let groups = groupByDayAndRegion(photos)

            #expect(groups.count == 1)
            #expect(located(groups[0]).count == 3, "\(count) photos should still be 3 places")
            #expect(groups[0].count == count)
        }
    }

    /// The pass really does swap where it says it does — if this stops holding, the test above is
    /// running the same code twice and proving nothing.
    @Test func aDayJustOverTheLimitTakesTheOtherPass() {
        // 20 spots 100 m apart in a line, so the line is 1.9 km end to end. The exact pass folds
        // the whole thing into one place, because every pair is inside the 2 km radius. The
        // leader pass cannot: it only ever measures against a leader, and its reach is half a
        // radius, so the far end opens a second place.
        func line(count: Int) -> [Photo] {
            (0 ..< count).map { index in
                photo(
                    id: index,
                    lat: 48.0 + latOffset(metres: Double(index % 20) * 100),
                    lng: 11.0,
                )
            }
        }

        let small = groupByDayAndRegion(line(count: exactPassLimit))
        let large = groupByDayAndRegion(line(count: exactPassLimit + 1))

        #expect(located(small[0]).count == 1, "every pair is inside 2 km, so the exact pass merges them")
        #expect(located(large[0]).count > 1,
                "the leader pass should split what the exact pass merged")
    }

    // MARK: - What the leader pass still has to guarantee

    /// The whole reason the leader pass uses half a radius: two photos on opposite sides of a
    /// leader are then still within a full radius of each other. So a place is never wider than
    /// the radius, on either pass. This is the promise the section headings rely on.
    @Test func noPlaceIsEverWiderThanTheRadius() {
        // A dense drift: 2000 photos walking 40 m at a time, which is exactly the chaining case
        // that a naive "near the last one" pass gets wrong.
        let photos = (0 ..< 2000).map { index in
            photo(id: index, lat: 48.0 + latOffset(metres: Double(index) * 40), lng: 11.0)
        }

        let groups = groupByDayAndRegion(photos)
        let places = located(groups[0])

        #expect(places.count > 1, "an 80 km walk is not one place")
        for place in places {
            #expect(trueDiameter(of: place) <= defaultRegionRadiusMeters + 1,
                    "a place spans \(trueDiameter(of: place)) m, over the \(defaultRegionRadiusMeters) m cap")
        }
    }

    /// Every photo comes out exactly once. A clustering pass that drops or duplicates one is a
    /// gallery that silently hides a photo.
    @Test func everyPhotoLandsInExactlyOnePlace() {
        let photos = blob(count: 900, firstId: 0, lat: 48.0, lng: 11.0)
            + blob(count: 900, firstId: 10000, lat: 52.5, lng: 13.4)

        let groups = groupByDayAndRegion(photos)
        let ids = groups.flatMap { $0.clusters.flatMap { $0.photos.map(\.id) } }

        #expect(ids.count == 1800)
        #expect(Set(ids).count == 1800)
        #expect(Set(ids) == Set(photos.map(\.id)))
    }

    /// Places keep the album's order — the first place is the one holding the earliest photo in
    /// the album — and photos keep it inside a place too. The leader pass builds its clusters in
    /// encounter order, so this could quietly hold only by luck; pin it.
    @Test func albumOrderSurvivesTheLeaderPass() {
        // Interleaved so encounter order and place order are not trivially the same.
        var photos: [Photo] = []
        for index in 0 ..< (exactPassLimit + 200) {
            let far = index % 3 == 0
            photos.append(photo(
                id: index,
                lat: far ? 55.0 : 48.0 + latOffset(metres: Double(index % 10)),
                lng: 11.0,
            ))
        }

        let places = located(groupByDayAndRegion(photos)[0])

        #expect(places.count >= 2)
        let firstIds = places.map { $0.photos[0].id }
        #expect(firstIds == firstIds.sorted(), "places should be ordered by their earliest photo")
        for place in places {
            let ids = place.photos.map(\.id)
            #expect(ids == ids.sorted(), "photos inside a place should keep album order")
        }
    }

    /// Photos with no coordinates are not clustered at all — they go in one trailing bucket, on
    /// both passes, and that bucket does not count toward the threshold.
    @Test func theNoLocationBucketStillTrailsOnABigDay() {
        let photos = blob(count: exactPassLimit + 100, firstId: 0, lat: 48.0, lng: 11.0)
            + (0 ..< 50).map { photo(id: 90000 + $0, lat: nil, lng: nil) }

        let groups = groupByDayAndRegion(photos)
        let clusters = groups[0].clusters

        #expect(clusters.last?.located == false)
        #expect(clusters.last?.photos.count == 50)
        #expect(clusters.dropLast().allSatisfy { $0.located })
        #expect(groups[0].count == exactPassLimit + 150)
    }

    /// A day of photos that carry no coordinates at all never reaches either pass, however big
    /// it is: there is nothing to cluster.
    @Test func aBigDayOfUnlocatedPhotosIsOneBucket() {
        let photos = (0 ..< (exactPassLimit + 500)).map { photo(id: $0, lat: nil, lng: nil) }

        let clusters = groupByDayAndRegion(photos)[0].clusters

        #expect(clusters.count == 1)
        #expect(clusters[0].located == false)
        #expect(clusters[0].photos.count == exactPassLimit + 500)
    }

    /// A place's centre has to sit among its photos. The leader pass reports a `spread` that is
    /// an upper bound rather than a measured width, so the centre is the part of a heading that
    /// still has to be exactly right.
    @Test func aBigPlacesCentreSitsInsideIt() {
        let photos = blob(count: exactPassLimit + 200, firstId: 0, lat: 48.0, lng: 11.0)

        let places = located(groupByDayAndRegion(photos)[0])

        for place in places {
            guard let center = place.center else {
                Issue.record("a located place has no centre")
                continue
            }
            for point in place.photos.compactMap(\.latLng) {
                #expect(haversineMeters(center, point) <= defaultRegionRadiusMeters)
            }
        }
    }

    /// The reported spread must never *understate* how far apart the photos are — a heading
    /// saying "200 m" over a 1.9 km place would be a lie. Overstating is allowed on the leader
    /// pass, which quotes twice the leader distance rather than measuring every pair.
    @Test func theQuotedSpreadIsNeverSmallerThanTheRealOne() {
        let photos = (0 ..< (exactPassLimit + 400)).map { index in
            photo(id: index, lat: 48.0 + latOffset(metres: Double(index % 60) * 15), lng: 11.0)
        }

        for place in located(groupByDayAndRegion(photos)[0]) {
            #expect(place.spreadMeters + 1 >= trueDiameter(of: place))
        }
    }

    /// One photo over the limit with nothing near it still has to come back as its own place,
    /// rather than being folded into whatever cluster happened to be open.
    @Test func aLoneOutlierOnABigDayKeepsItsOwnPlace() {
        let photos = blob(count: exactPassLimit + 50, firstId: 0, lat: 48.0, lng: 11.0)
            + [photo(id: 99999, lat: -33.86, lng: 151.20)] // Sydney

        let places = located(groupByDayAndRegion(photos)[0])
        let outlier = places.first { $0.photos.contains { $0.id == 99999 } }

        #expect(outlier?.photos.count == 1)
        #expect(outlier?.spreadMeters == 0)
    }
}
