import Foundation
import Testing

@testable import Zyncloud

/// Guards the split between "show this as an image" and "play this as a video".
///
/// Tapping a video used to render "Failed": the detail view asked for
/// `/api/i/{token}?size=large`, and a video has no `large` derivative, so the server answered
/// with the video's own bytes — which `UIImage(data:)` cannot decode.
@MainActor
struct VideoPreviewTests {
    private func file(mimetype: String?) -> FileInfo {
        FileInfo(
            id: 1,
            originalName: "clip.mov",
            filename: "clip.mov",
            publicToken: "tok123",
            size: 42,
            mimetype: mimetype,
            path: nil,
            uploadedAt: "2026-08-23T10:00:00Z",
            displayOrder: nil,
            tags: [],
            albumId: 7,
            albumName: "Trip",
        )
    }

    @Test func recognisesVideoMimeTypes() {
        #expect(file(mimetype: "video/mp4").isVideo)
        #expect(file(mimetype: "VIDEO/QUICKTIME").isVideo)
        #expect(!file(mimetype: "image/jpeg").isVideo)
        #expect(!file(mimetype: nil).isVideo)
    }

    @Test func videoURLCarriesNoSizeParameter() throws {
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
        let viewModel = AlbumDetailViewModel(album: album)

        let url = try #require(viewModel.videoURL(for: file(mimetype: "video/mp4")))

        #expect(url.path.hasSuffix("/api/i/tok123"))
        // A size would ask for an image derivative the video does not have.
        #expect(url.query == nil)
    }
}
