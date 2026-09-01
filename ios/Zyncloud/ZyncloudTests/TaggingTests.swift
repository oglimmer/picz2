import Foundation
import Testing

@testable import Zyncloud

/// The rules the tag screens read their ticks from.
///
/// All three are pure — no server — but each one decides what a tap does, so a wrong answer
/// here means a tap that adds when the user meant remove.
@MainActor
struct TaggingTests {
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

    private func photo(id: Int, tags: [String]) -> FileInfo {
        FileInfo(
            id: id,
            originalName: "shot\(id).jpg",
            filename: "shot\(id).jpg",
            publicToken: "tok\(id)",
            size: 42,
            mimetype: "image/jpeg",
            path: nil,
            uploadedAt: "2026-08-23T10:00:00Z",
            displayOrder: nil,
            tags: tags,
            albumId: 7,
            albumName: "Trip",
        )
    }

    /// What the bulk sheet reads to decide whether a tap adds or removes.
    @Test func selectionStateCountsTheWholeSelection() {
        let viewModel = AlbumDetailViewModel(album: album())
        viewModel.photos = [
            photo(id: 1, tags: ["beach"]),
            photo(id: 2, tags: ["beach", "sunset"]),
            photo(id: 3, tags: []),
        ]

        viewModel.selectedPhotoIds = [1, 2]
        #expect(viewModel.selectionState(of: "beach") == .all)
        #expect(viewModel.selectionState(of: "sunset") == .some)
        #expect(viewModel.selectionState(of: "hike") == .none)

        viewModel.selectedPhotoIds = [1, 2, 3]
        #expect(viewModel.selectionState(of: "beach") == .some)
    }

    /// Nothing picked is not "every picked photo has it" — a sheet reading `.all` there would
    /// offer to remove a tag from no photos at all.
    @Test func anEmptySelectionCarriesNothing() {
        let viewModel = AlbumDetailViewModel(album: album())
        viewModel.photos = [photo(id: 1, tags: ["beach"])]
        viewModel.selectedPhotoIds = []

        #expect(viewModel.selectionState(of: "beach") == .none)
    }

    /// The album's accepted-tag list is written back whole, and the server drops the `all`
    /// system id from it — so it must not be sent, or the list sent back would never match.
    @Test func enabledTagIdsLeaveOutTheSystemTags() {
        let viewModel = AlbumDetailViewModel(album: album())
        viewModel.albumTags = [
            Tag(id: 1, name: "all", createdAt: nil),
            Tag(id: 2, name: "beach", createdAt: nil),
            Tag(id: 3, name: "sunset", createdAt: nil),
        ]

        #expect(viewModel.enabledTagIds == [2, 3])
    }
}
