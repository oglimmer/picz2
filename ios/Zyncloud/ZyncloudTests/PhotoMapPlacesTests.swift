import Foundation
import Testing

@testable import Zyncloud

/// Turning an album into map pins. A port of `PhotoMap.vue`'s bucketing, so an album drops the
/// same number of pins in the browser and on the phone.
struct PhotoMapPlacesTests {
    private func photo(id: Int, lat: Double? = nil, lng: Double? = nil) -> Photo {
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
            tags: [],
            albumId: 7,
            albumName: "Trip",
        )
        file.gpsLatitude = lat
        file.gpsLongitude = lng
        return file
    }

    // MARK: - What can be on a map at all

    /// A location lives only in the original, so plenty of photos have none — they are not on the
    /// map rather than being on it at (0, 0), which is in the Atlantic.
    @Test func photosWithoutBothCoordinatesAreNotOnTheMap() {
        let located = PhotoMapPlaces.located(in: [
            photo(id: 1, lat: 50.1109, lng: 8.6821),
            photo(id: 2),
            photo(id: 3, lat: 50.1109),
            photo(id: 4, lng: 8.6821),
        ])

        #expect(located.map(\.id) == [1])
    }

    // MARK: - Bucketing

    /// The key rounds to four decimals — about 11 m — so a burst shot from one spot is one pin
    /// instead of a smear of overlapping ones.
    @Test func photosInTheSameCellShareOnePin() {
        let places = PhotoMapPlaces.places(from: [
            photo(id: 1, lat: 50.111_10, lng: 8.682_10),
            photo(id: 2, lat: 50.111_14, lng: 8.682_13),
        ])

        #expect(places.count == 1)
        #expect(places[0].photos.map(\.id) == [1, 2])
    }

    @Test func photosInDifferentCellsGetTheirOwnPins() {
        let places = PhotoMapPlaces.places(from: [
            photo(id: 1, lat: 50.1111, lng: 8.6821),
            photo(id: 2, lat: 50.1113, lng: 8.6821),
        ])

        #expect(places.count == 2)
    }

    /// The key decides what shares a pin; it is not itself a position. Dropping the pin on the
    /// rounded value would move every pin by up to 5 m for no reason.
    @Test func apinSitsOnTheFirstPhotosRealCoordinates() {
        let places = PhotoMapPlaces.places(from: [
            photo(id: 1, lat: 50.111_14, lng: 8.682_13),
            photo(id: 2, lat: 50.111_10, lng: 8.682_10),
        ])

        #expect(places[0].latitude == 50.111_14)
        #expect(places[0].longitude == 8.682_13)
    }

    /// The map re-shelves the album, it does not re-sort it — between pins and inside them.
    @Test func pinsAndTheirPhotosKeepTheAlbumsOrder() {
        let places = PhotoMapPlaces.places(from: [
            photo(id: 1, lat: 50.5000, lng: 8.0),
            photo(id: 2, lat: 50.1000, lng: 8.0),
            photo(id: 3, lat: 50.5000, lng: 8.0),
        ])

        #expect(places.count == 2)
        #expect(places[0].photos.map(\.id) == [1, 3])
        #expect(places[1].photos.map(\.id) == [2])
    }

    @Test func analbumWithNoLocatedPhotosHasNoPins() {
        #expect(PhotoMapPlaces.places(from: [photo(id: 1), photo(id: 2)]).isEmpty)
    }

    /// Keys must not pick up a decimal comma on a device set to a locale that uses one — the
    /// bucketing would still be self-consistent, but the value is a key and keys should not vary
    /// by who is holding the phone.
    @Test func thekeyIsFormattedWithADecimalPoint() {
        #expect(PhotoMapPlaces.key(latitude: 50.1111, longitude: 8.6821) == "50.1111,8.6821")
    }

    // MARK: - What a pin says

    /// A lone pin reading "1" is noise, and three digits is where a marker glyph starts to clip.
    @Test(arguments: [(1, "📷"), (2, "2"), (99, "99"), (100, "99+"), (1500, "99+")])
    func theglyphCountsOnlyWhenThereIsSomethingToCount(count: Int, glyph: String) {
        #expect(PhotoMapPlaces.glyph(forPhotoCount: count) == glyph)
    }

    @Test func thetitleReadsAsEnglish() {
        #expect(PhotoMapPlaces.title(forPhotoCount: 1) == "1 photo")
        #expect(PhotoMapPlaces.title(forPhotoCount: 4) == "4 photos")
    }

    // MARK: - The album's saved framing

    @Test func analbumWithAllFourFieldsHasASavedView() {
        var album = self.album()
        album.mapCenterLat = 50.1
        album.mapCenterLng = 8.6
        album.mapSpanLat = 0.05
        album.mapSpanLng = 0.08

        #expect(album.savedMapView == SavedMapView(
            centerLat: 50.1,
            centerLng: 8.6,
            spanLat: 0.05,
            spanLng: 0.08,
        ))
    }

    /// A half-saved view would centre the map on null island, which is why the server refuses to
    /// store one — the client must not invent one either.
    @Test func apartlySetViewIsNoView() {
        var album = self.album()
        album.mapCenterLat = 50.1
        album.mapCenterLng = 8.6

        #expect(album.savedMapView == nil)
        #expect(self.album().savedMapView == nil)
    }

    private func album() -> Album {
        Album(
            id: 7,
            name: "Trip",
            description: nil,
            createdAt: nil,
            updatedAt: nil,
            displayOrder: nil,
            fileCount: nil,
            coverImageFilename: nil,
            coverImageToken: nil,
            shareToken: nil,
        )
    }
}
