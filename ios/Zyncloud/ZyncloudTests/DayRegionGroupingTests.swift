import Foundation
import Testing

@testable import Zyncloud

/// The "By Day & Place" shelving. A port of the web app's grouping, so the same album has to
/// break into the same sections here as it does there.
struct DayRegionGroupingTests {
    private func photo(
        id: Int,
        takenAt: String? = nil,
        uploadedAt: String = "2026-05-04T12:00:00Z",
        offsetSeconds: Int? = nil,
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
            uploadedAt: uploadedAt,
            displayOrder: nil,
            tags: [],
            albumId: 7,
            albumName: "Trip",
        )
        file.exifDateTimeOriginal = takenAt
        file.captureUtcOffsetSeconds = offsetSeconds
        file.gpsLatitude = lat
        file.gpsLongitude = lng
        return file
    }

    /// 1 degree of latitude is about 111.2 km, so this converts a wanted distance into a shift
    /// that does not depend on longitude.
    private func latOffset(metres: Double) -> Double {
        metres / 111_195.0
    }

    // MARK: - Days

    /// The day is the one the camera saw, not the one the phone showing it is in. The same
    /// instant lands on either side of midnight depending on where the shutter fired.
    @Test func theCaptureOffsetDecidesTheDay() {
        let groups = groupByDayAndRegion([
            photo(id: 1, takenAt: "2026-05-04T23:00:00Z", offsetSeconds: 7200), // UTC+2 → 01:00 on the 5th
            photo(id: 2, takenAt: "2026-05-04T23:00:00Z", offsetSeconds: -14400), // UTC-4 → 19:00 on the 4th
        ])

        #expect(Set(groups.map(\.id)) == ["2026-05-05", "2026-05-04"])
        #expect(groups.allSatisfy { $0.count == 1 })
    }

    /// A photo carrying no offset of its own borrows the one most of the album was shot at — a
    /// trip is one place, and the viewer's timezone is a worse guess than its neighbours'.
    @Test func aMissingOffsetBorrowsTheAlbums() {
        let groups = groupByDayAndRegion([
            photo(id: 1, takenAt: "2026-05-04T23:00:00Z", offsetSeconds: 7200),
            photo(id: 2, takenAt: "2026-05-04T23:30:00Z", offsetSeconds: 7200),
            photo(id: 3, takenAt: "2026-05-04T23:15:00Z", offsetSeconds: nil),
        ])

        #expect(groups.count == 1)
        #expect(groups.first?.id == "2026-05-05")
        #expect(groups.first?.count == 3)
    }

    /// No usable date at all is its own trailing group rather than a wrong day.
    @Test func anUnreadableDateLandsInTheUnknownGroup() {
        let groups = groupByDayAndRegion([
            photo(id: 1, takenAt: "2026-05-04T10:00:00Z", offsetSeconds: 0),
            photo(id: 2, uploadedAt: "not a date"),
        ])

        #expect(groups.map(\.id) == ["2026-05-04", "unknown"])
        #expect(groups.last?.date == nil)
    }

    /// The album's own order decides which day comes first. The grouping re-shelves, it does
    /// not re-sort.
    @Test func daysKeepTheAlbumsOrder() {
        let groups = groupByDayAndRegion([
            photo(id: 1, takenAt: "2026-05-06T10:00:00Z", offsetSeconds: 0),
            photo(id: 2, takenAt: "2026-05-04T10:00:00Z", offsetSeconds: 0),
        ])

        #expect(groups.map(\.id) == ["2026-05-06", "2026-05-04"])
    }

    // MARK: - Places

    @Test func photosInOneSpotAreOnePlace() {
        let groups = groupByDayAndRegion([
            photo(id: 1, takenAt: "2026-05-04T10:00:00Z", offsetSeconds: 0, lat: 48.0, lng: 11.0),
            photo(id: 2, takenAt: "2026-05-04T10:05:00Z", offsetSeconds: 0,
                  lat: 48.0 + latOffset(metres: 100), lng: 11.0),
        ])

        #expect(groups.first?.clusters.count == 1)
        #expect(groups.first?.clusters.first?.photos.count == 2)
        #expect(groups.first?.clusters.first?.located == true)
    }

    @Test func photosMilesApartAreTwoPlaces() {
        let groups = groupByDayAndRegion([
            photo(id: 1, takenAt: "2026-05-04T10:00:00Z", offsetSeconds: 0, lat: 48.0, lng: 11.0),
            photo(id: 2, takenAt: "2026-05-04T14:00:00Z", offsetSeconds: 0, lat: 49.0, lng: 11.0),
        ])

        #expect(groups.first?.clusters.count == 2)
    }

    /// The whole reason for complete linkage: three photos in a line, each 1.5 km from the
    /// next, must not chain into one 3 km "place" when the cap is 2 km.
    @Test func placesDoNotChainPastTheRadius() {
        let groups = groupByDayAndRegion(
            [
                photo(id: 1, takenAt: "2026-05-04T10:00:00Z", offsetSeconds: 0, lat: 48.0, lng: 11.0),
                photo(id: 2, takenAt: "2026-05-04T10:30:00Z", offsetSeconds: 0,
                      lat: 48.0 + latOffset(metres: 1500), lng: 11.0),
                photo(id: 3, takenAt: "2026-05-04T11:00:00Z", offsetSeconds: 0,
                      lat: 48.0 + latOffset(metres: 3000), lng: 11.0),
            ],
            radiusMeters: 2000,
        )

        let clusters = groups.first?.clusters ?? []
        #expect(clusters.count == 2)
        #expect(clusters.reduce(0) { $0 + $1.photos.count } == 3)
        // Whatever the split, no finished place may be wider than the cap.
        #expect(clusters.allSatisfy { $0.spreadMeters <= 2000 })
    }

    /// Photos with no coordinates get their own bucket at the end of their day, not a made-up
    /// position.
    @Test func photosWithNoLocationGetTheirOwnBucketLast() {
        let groups = groupByDayAndRegion([
            photo(id: 1, takenAt: "2026-05-04T10:00:00Z", offsetSeconds: 0),
            photo(id: 2, takenAt: "2026-05-04T11:00:00Z", offsetSeconds: 0, lat: 48.0, lng: 11.0),
        ])

        let clusters = groups.first?.clusters ?? []
        #expect(clusters.count == 2)
        #expect(clusters.first?.located == true)
        #expect(clusters.last?.located == false)
        #expect(clusters.last?.center == nil)
    }

    // MARK: - Labels

    @Test func distancesReadAsMetresThenKilometres() {
        #expect(formatDistance(0) == "0 m")
        #expect(formatDistance(824) == "820 m")
        #expect(formatDistance(1234) == "1.2 km")
    }

    @Test func haversineMatchesAKnownSpan() {
        let metres = haversineMeters(
            LatLng(lat: 48.0, lng: 11.0),
            LatLng(lat: 48.0 + latOffset(metres: 1000), lng: 11.0),
        )
        #expect(abs(metres - 1000) < 5)
    }
}
