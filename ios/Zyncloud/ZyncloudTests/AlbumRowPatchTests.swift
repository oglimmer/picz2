import Testing
@testable import Zyncloud

/// What keeps the album grid honest after the detail screen changes an album.
///
/// The grid pushes an `Album` **value** into the detail screen, so a publish made down there is
/// invisible up here until the row is replaced. These are the rules that replacement follows.
@MainActor
struct AlbumRowPatchTests {
    private func album(id: Int, published: Bool?) -> Album {
        var album = Album(
            id: id,
            name: "Trip \(id)",
            description: nil,
            createdAt: nil,
            updatedAt: nil,
            displayOrder: nil,
            fileCount: nil,
            coverImageFilename: nil,
            coverImageToken: nil,
            shareToken: "tok\(id)",
        )
        album.published = published
        return album
    }

    @Test func `replacing A row swaps in the newer album`() {
        let viewModel = AlbumsViewModel(apiClient: nil)
        viewModel.albums = [album(id: 1, published: false), album(id: 2, published: false)]

        viewModel.replace(album(id: 2, published: true))

        #expect(viewModel.albums[0].isPublished == false)
        #expect(viewModel.albums[1].isPublished == true)
    }

    @Test func `replacing keeps the row in place`() {
        let viewModel = AlbumsViewModel(apiClient: nil)
        viewModel.albums = [album(id: 1, published: false), album(id: 2, published: false)]

        viewModel.replace(album(id: 1, published: true))

        #expect(viewModel.albums.map(\.id) == [1, 2])
    }

    /// The album was deleted while the detail screen was open. Nothing to patch, and nothing
    /// added back — a re-appearing row would be worse than a missing one.
    @Test func `replacing an album that is gone adds nothing`() {
        let viewModel = AlbumsViewModel(apiClient: nil)
        viewModel.albums = [album(id: 1, published: false)]

        viewModel.replace(album(id: 99, published: true))

        #expect(viewModel.albums.map(\.id) == [1])
    }

    /// The detail screen only announces a change after the server answers, so nothing is
    /// published up to the list before that.
    @Test func `the detail screen announces no change until the server answers`() {
        let viewModel = AlbumDetailViewModel(album: album(id: 3, published: false), apiClient: nil)

        #expect(viewModel.revisedAlbum == nil)
        #expect(viewModel.isPublished == false)
    }
}
