import Foundation
import Testing

@testable import Zyncloud

/// "Find Duplicates". The cases mirror the web's `useDuplicateMode.test.ts`, so an album finds the
/// same copies in the browser and on the phone.
struct DuplicateNamesTests {
    private func photo(id: Int, name: String, mimetype: String = "image/jpeg") -> Photo {
        Photo(
            id: id,
            originalName: name,
            filename: "\(id).jpg",
            publicToken: "tok\(id)",
            size: 1234,
            mimetype: mimetype,
            path: nil,
            uploadedAt: "2026-09-01T10:00:00Z",
            displayOrder: id,
            tags: [],
            albumId: 7,
            albumName: "Trip",
        )
    }

    private func card(id: Int, headline: String) -> Photo {
        var entry = photo(id: id, name: headline, mimetype: "application/x-picz-text-card")
        entry.kind = "TEXT_CARD"
        entry.headline = headline
        return entry
    }

    // MARK: - The rule

    @Test func `shows only photos sharing a name and picks every copy but the first`() {
        let photos = [
            photo(id: 1, name: "a.jpg"), photo(id: 2, name: "b.jpg"), photo(id: 3, name: "a.jpg"),
            photo(id: 4, name: "a.jpg"), photo(id: 5, name: "c.jpg"),
        ]
        #expect(DuplicateNames.duplicates(in: photos).map(\.id) == [1, 3, 4])
        #expect(DuplicateNames.extraCopies(in: photos) == [3, 4])
    }

    @Test func `a JPEG and a HEIC of the same name are one photo`() {
        let photos = [
            photo(id: 1, name: "IMG_1.HEIC"), photo(id: 2, name: "IMG_1.jpg"),
            photo(id: 3, name: "IMG_2.jpeg"), photo(id: 4, name: "IMG_2.heif"),
            photo(id: 5, name: "IMG_3.heic"), photo(id: 6, name: "IMG_4.heic"),
        ]
        #expect(DuplicateNames.duplicates(in: photos).map(\.id) == [1, 2, 3, 4])
        #expect(DuplicateNames.extraCopies(in: photos) == [2, 4])
    }

    /// A Live Photo's video carries its still's name. Deleting it as a "copy" would break the pair.
    @Test func `a Live Photo's video and other formats are left alone`() {
        let photos = [
            photo(id: 1, name: "IMG_1.HEIC"), photo(id: 2, name: "IMG_1.MOV", mimetype: "video/quicktime"),
            photo(id: 3, name: "IMG_2.png"), photo(id: 4, name: "IMG_2.jpg"),
        ]
        #expect(DuplicateNames.duplicates(in: photos).isEmpty)
    }

    @Test func `two text cards with the same headline are no duplicates`() {
        let photos = [card(id: 1, headline: "Day 1"), card(id: 2, headline: "Day 1")]
        #expect(DuplicateNames.duplicates(in: photos).isEmpty)
    }

    @Test func `the FullSizeRender name is never flagged`() {
        let photos = [
            photo(id: 1, name: "FullSizeRender.heic"), photo(id: 2, name: "fullsizerender.HEIC"),
            photo(id: 3, name: "FullSizeRender.jpg"),
        ]
        #expect(DuplicateNames.duplicates(in: photos).isEmpty)
        #expect(DuplicateNames.extraCopies(in: photos).isEmpty)
    }

    @Test func `a name without an extension is compared as it is`() {
        #expect(DuplicateNames.key(for: "scan") == "scan")
        #expect(DuplicateNames.key(for: ".heic") == ".heic")
        #expect(DuplicateNames.key(for: "trip.v2.HEIC") == "trip.v2.jpg")
    }

    // MARK: - The screen's mode

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
    @Test func `finding duplicates picks the extra copies and All stays inside them`() {
        let model = viewModel([
            photo(id: 1, name: "IMG_1.heic"), photo(id: 2, name: "IMG_2.jpg"), photo(id: 3, name: "IMG_1.jpg"),
        ])
        model.beginFindingDuplicates()
        #expect(model.isFindingDuplicates)
        #expect(model.isSelecting)
        #expect(model.selectedPhotoIds == [3])

        model.selectAllPhotos()
        #expect(model.selectedPhotoIds == [1, 3])

        model.endSelecting()
        #expect(!model.isFindingDuplicates)
        #expect(!model.isSelecting)
        #expect(model.selectedPhotoIds.isEmpty)
    }

    @MainActor
    @Test func `an album with no duplicates says so and opens nothing`() {
        let model = viewModel([photo(id: 1, name: "a.jpg"), photo(id: 2, name: "b.jpg")])
        model.beginFindingDuplicates()
        #expect(!model.isFindingDuplicates)
        #expect(!model.isSelecting)
        #expect(model.alertState?.title == "No Duplicates")
    }
}
