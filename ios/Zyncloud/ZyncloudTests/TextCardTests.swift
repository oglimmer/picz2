import Foundation
import Testing

@testable import Zyncloud

/// Text cards (D86): an album entry that carries a chapter heading instead of pixels.
///
/// The rules under test are the two that decide what the grid draws — what makes an entry a card,
/// and which photo it borrows its blurred background from.
struct TextCardTests {
    private func photo(id: Int) -> Photo {
        Photo(
            id: id,
            originalName: "IMG_\(id).jpg",
            filename: "IMG_\(id).jpg",
            publicToken: "tok\(id)",
            size: 1234,
            mimetype: "image/jpeg",
            path: "originals/IMG_\(id).jpg",
            uploadedAt: "2026-09-01T10:00:00Z",
            displayOrder: id,
            tags: [],
            albumId: 7,
            albumName: "Trip",
        )
    }

    private func card(id: Int, headline: String = "Day one", body: String? = nil) -> Photo {
        var entry = photo(id: id)
        entry.kind = "TEXT_CARD"
        entry.headline = headline
        entry.bodyText = body
        return entry
    }

    // MARK: - What makes a card a card

    @Test func `the kind field decides, not the mime type`() {
        #expect(card(id: 1).isTextCard)
        #expect(!photo(id: 2).isTextCard)
    }

    /// A row from a server that predates the field has to read as a photo. The other way round
    /// would draw text over a picture that then never gets rendered at all.
    @Test func `an entry with no kind is A photo`() {
        var older = photo(id: 1)
        older.kind = nil
        #expect(!older.isTextCard)
    }

    @Test func `an unknown kind is A photo too`() {
        var future = photo(id: 1)
        future.kind = "SOMETHING_NEW"
        #expect(!future.isTextCard)
    }

    @Test func `the heading falls back to the row name`() {
        var bare = card(id: 1)
        bare.headline = nil
        #expect(bare.cardHeadline == "IMG_1.jpg")
        #expect(card(id: 2, headline: "Over the pass").cardHeadline == "Over the pass")
    }

    // MARK: - Which photo the card sits in front of

    @MainActor
    private func viewModel(_ entries: [Photo]) -> AlbumDetailViewModel {
        let album = Album(
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
        let model = AlbumDetailViewModel(album: album, apiClient: nil)
        model.photos = entries
        return model
    }

    @MainActor
    @Test func `the background is the next actual picture`() {
        let model = viewModel([card(id: 1), photo(id: 2), photo(id: 3)])
        #expect(model.backgroundPhoto(for: model.photos[0])?.id == 2)
    }

    @MainActor
    @Test func `other cards are stepped over to reach A picture`() {
        let model = viewModel([card(id: 1), card(id: 2), photo(id: 3)])
        #expect(model.backgroundPhoto(for: model.photos[0])?.id == 3)
    }

    @MainActor
    @Test func `A card at the end of the album gets no background`() {
        let model = viewModel([photo(id: 1), card(id: 2)])
        #expect(model.backgroundPhoto(for: model.photos[1]) == nil)
    }

    @MainActor
    @Test func `A photo never gets A background`() {
        let model = viewModel([photo(id: 1), photo(id: 2)])
        #expect(model.backgroundPhoto(for: model.photos[0]) == nil)
    }

    // MARK: - Day and place are inherited from the next photo

    private func photo(id: Int, taken: String?, lat: Double?, lng: Double?) -> Photo {
        var entry = photo(id: id)
        entry.exifDateTimeOriginal = taken
        entry.captureUtcOffsetSeconds = 7200
        entry.gpsLatitude = lat
        entry.gpsLongitude = lng
        return entry
    }

    @Test func `A card takes the day and place of the photo after it`() {
        let entries = withInheritedDayAndPlace([
            card(id: 1),
            photo(id: 2, taken: "2026-05-04T09:00:00Z", lat: 48.137, lng: 11.575),
        ])

        #expect(entries[0].exifDateTimeOriginal == "2026-05-04T09:00:00Z")
        #expect(entries[0].captureUtcOffsetSeconds == 7200)
        #expect(entries[0].gpsLatitude == 48.137)
        #expect(entries[0].gpsLongitude == 11.575)
        // Still a card, and still carrying its own words.
        #expect(entries[0].isTextCard)
        #expect(entries[0].headline == "Day one")
    }

    /// So a card lands in the day section of the chapter it introduces rather than in the
    /// trailing "unknown" one, which is the whole point of the inheritance.
    @Test func `the card and its photo end up in one day section`() {
        let groups = groupByDayAndRegion(withInheritedDayAndPlace([
            card(id: 1),
            photo(id: 2, taken: "2026-05-04T09:00:00Z", lat: 48.137, lng: 11.575),
        ]))

        #expect(groups.count == 1)
        #expect(groups[0].id != "unknown")
        #expect(groups[0].clusters.count == 1)
        #expect(groups[0].clusters[0].photos.map(\.id) == [1, 2])
    }

    @Test func `A run of cards all reach the same photo`() {
        let entries = withInheritedDayAndPlace([
            card(id: 1),
            card(id: 2),
            photo(id: 3, taken: "2026-05-04T09:00:00Z", lat: 48.137, lng: 11.575),
        ])

        #expect(entries[0].gpsLatitude == 48.137)
        #expect(entries[1].gpsLatitude == 48.137)
    }

    /// A photo with no EXIF date still has an upload time, and that is the instant
    /// `captureInstant` would use for it — so it is the one the card borrows.
    @Test func `the upload time stands in when the camera left no date`() {
        var undated = photo(id: 2, taken: nil, lat: nil, lng: nil)
        undated.captureUtcOffsetSeconds = nil
        let entries = withInheritedDayAndPlace([card(id: 1), undated])

        #expect(entries[0].exifDateTimeOriginal == undated.uploadedAt)
    }

    /// Nothing follows it, so there is nothing honest to borrow. It keeps the trailing bucket.
    @Test func `A card at the end of the album inherits nothing`() {
        let entries = withInheritedDayAndPlace([
            photo(id: 1, taken: "2026-05-04T09:00:00Z", lat: 48.137, lng: 11.575),
            card(id: 2),
        ])

        #expect(entries[1].exifDateTimeOriginal == nil)
        #expect(entries[1].gpsLatitude == nil)
    }

    /// The borrowed place must not reach the map: a card is not somewhere anybody stood.
    @Test func `the borrowed place does not touch the original rows`() {
        let original = [card(id: 1), photo(id: 2, taken: "2026-05-04T09:00:00Z", lat: 48.1, lng: 11.5)]
        _ = withInheritedDayAndPlace(original)

        #expect(original[0].gpsLatitude == nil)
        #expect(original[0].latLng == nil)
    }

    // MARK: - Bulk actions leave cards alone

    @MainActor
    @Test func `A selected card is not rotated or enhanced`() {
        let model = viewModel([photo(id: 1), card(id: 2), photo(id: 3)])
        model.selectedPhotoIds = [1, 2, 3]

        // Both counts are the ones the confirmation prints, so neither may include the card.
        #expect(model.selectedStillCount == 2)
        #expect(model.selectedEnhanceablePhotos.map(\.id) == [1, 3])
    }

    @MainActor
    @Test func `A selection of only cards leaves both buttons off`() {
        let model = viewModel([card(id: 1), card(id: 2)])
        model.selectedPhotoIds = [1, 2]

        #expect(!model.selectionHasRotatablePhoto)
        #expect(!model.selectionHasEnhanceablePhoto)
    }

    // MARK: - The wire

    @Test func `decodes A text card row`() throws {
        let response = try JSONDecoder().decode(FilesResponse.self, from: Data("""
        {
          "success": true,
          "files": [
            {
              "id": 42,
              "originalName": "Day three",
              "filename": "text-card-9f2c",
              "publicToken": "tok42",
              "size": 0,
              "mimetype": "application/x-picz-text-card",
              "path": null,
              "uploadedAt": "2026-09-07T10:00:00Z",
              "displayOrder": 4,
              "tags": ["trip"],
              "albumId": 7,
              "albumName": "Trip",
              "processingStatus": "DONE",
              "kind": "TEXT_CARD",
              "headline": "Day three",
              "bodyText": "Over the pass in the rain."
            }
          ]
        }
        """.utf8))

        let entry = try #require(response.files.first)
        #expect(entry.isTextCard)
        #expect(entry.headline == "Day three")
        #expect(entry.bodyText == "Over the pass in the rain.")
        // DONE from birth, so the grid never puts a spinner on a card.
        #expect(entry.isThumbnailReady)
        #expect(!entry.isVideo)
    }

    /// A photo row carries none of the three fields. It must still decode, and it must not come
    /// out claiming to be a card.
    @Test func `decodes A photo row from A server that sends the card fields`() throws {
        let entry = try JSONDecoder().decode(Photo.self, from: Data("""
        {
          "id": 1,
          "originalName": "IMG_0001.jpg",
          "filename": "IMG_0001.jpg",
          "publicToken": "tok1",
          "size": 1234,
          "mimetype": "image/jpeg",
          "path": "originals/IMG_0001.jpg",
          "uploadedAt": "2026-09-07T10:00:00Z",
          "displayOrder": 0,
          "tags": [],
          "albumId": 7,
          "albumName": "Trip",
          "kind": "PHOTO"
        }
        """.utf8))

        #expect(!entry.isTextCard)
        #expect(entry.headline == nil)
        #expect(entry.bodyText == nil)
    }
}
