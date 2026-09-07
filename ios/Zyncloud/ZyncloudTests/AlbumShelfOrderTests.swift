import Testing
@testable import Zyncloud

/// Dragging one album tile onto another puts the shelf in a new order. These are the rules that
/// move follows, before any of it reaches the server.
@MainActor
struct AlbumShelfOrderTests {
    private func album(id: Int) -> Album {
        Album(
            id: id,
            name: "Trip \(id)",
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

    private var shelf: [Album] {
        [album(id: 1), album(id: 2), album(id: 3), album(id: 4)]
    }

    @Test func `a tile dropped further down takes that tile's place`() {
        let moved = AlbumsViewModel.shelf(shelf, moving: 1, onto: 3)
        #expect(moved?.map(\.id) == [2, 3, 1, 4])
    }

    @Test func `a tile dropped further up takes that tile's place`() {
        let moved = AlbumsViewModel.shelf(shelf, moving: 4, onto: 1)
        #expect(moved?.map(\.id) == [4, 1, 2, 3])
    }

    @Test func `dropping a tile onto itself is not A move`() {
        #expect(AlbumsViewModel.shelf(shelf, moving: 2, onto: 2) == nil)
    }

    /// The payload is the album id as text, so anything at all can arrive on the grid. An id
    /// that is not on the shelf is ignored rather than guessed at.
    @Test func `an unknown id is not A move`() {
        #expect(AlbumsViewModel.shelf(shelf, moving: 99, onto: 1) == nil)
        #expect(AlbumsViewModel.shelf(shelf, moving: 1, onto: 99) == nil)
    }

    /// The new order is on screen before the server has answered, so the drag does not feel like
    /// it snapped back.
    @Test func `the moved order shows at once`() {
        let viewModel = AlbumsViewModel(apiClient: nil)
        viewModel.albums = shelf

        viewModel.moveAlbum(draggedId: 3, onto: 1)

        #expect(viewModel.albums.map(\.id) == [3, 1, 2, 4])
    }
}
