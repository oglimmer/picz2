import Foundation
import Testing

@testable import Zyncloud

/// Asking the server for a derivative it has not made yet answers `202 Accepted` with an empty
/// body. That status code sits inside the 2xx range, so the client read it as a successful
/// response whose bytes happened not to decode — which is why every freshly uploaded photo
/// showed a red "Failed" icon while its thumbnail was merely still being generated. The gate is
/// the file list's own `processingStatus`, mirroring what the web gallery does.
struct ProcessingStatusGatingTests {
    private func file(status: String?) throws -> FileInfo {
        let statusField = status.map { "\"processingStatus\": \"\($0)\"," } ?? ""
        let json = """
        {
            "id": 1, "originalName": "IMG_0001.HEIC", "filename": "IMG_0001.jpg",
            "publicToken": "abc", "size": 100, "mimetype": "image/jpeg", "path": null,
            "uploadedAt": "2026-08-24T20:04:20.278643Z", "displayOrder": 0,
            \(statusField)
            "tags": [], "albumId": 37, "albumName": "test13"
        }
        """
        return try JSONDecoder().decode(FileInfo.self, from: Data(json.utf8))
    }

    // MARK: - Readiness

    @Test(arguments: [
        ("DONE", true),
        ("QUEUED", false),
        ("PROCESSING", false),
        ("FAILED", false),
        ("DEAD_LETTER", false),
    ])
    func onlyDoneCountsAsReady(status: String, ready: Bool) throws {
        let decoded = try file(status: status)
        #expect(decoded.isThumbnailReady == ready)
    }

    /// Rows written before the server carried a status have none. The web gallery shows those
    /// rather than suppressing them, and so does this — a missing status must never hide a
    /// photo that has been sitting there for a year.
    @Test func anAbsentStatusReadsAsReady() throws {
        let decoded = try file(status: nil)
        #expect(decoded.isThumbnailReady)
    }

    // MARK: - Give-up

    /// "Not ready yet" and "never going to be ready" drive different tiles, and only the first
    /// is worth polling — a poll on a DEAD_LETTER asset would run until its deadline every time
    /// the album is opened.
    @Test(arguments: [
        ("FAILED", true),
        ("DEAD_LETTER", true),
        ("QUEUED", false),
        ("PROCESSING", false),
        ("DONE", false),
    ])
    func onlyTheTerminalFailuresCountAsFailed(status: String, failed: Bool) throws {
        let decoded = try file(status: status)
        #expect(decoded.processingFailed == failed)
    }

    @Test func anAbsentStatusIsNotAFailure() throws {
        let decoded = try file(status: nil)
        #expect(!decoded.processingFailed)
    }

    // MARK: - Decoding robustness

    /// The field is decoded as a raw string on purpose. Decoding it straight into the enum
    /// would throw on a value this build has not heard of — and a throw here fails the decode
    /// of the *whole album*, so one new server status would empty the gallery.
    @Test func anUnknownStatusDoesNotFailTheDecode() throws {
        let unknown = try file(status: "TRANSCODING")
        #expect(unknown.processingStatus == "TRANSCODING")
        #expect(unknown.processing == nil)
        // Unrecognised means "not DONE", so it waits rather than showing a broken picture.
        #expect(!unknown.isThumbnailReady)
        #expect(!unknown.processingFailed)
    }

    @Test func aFileListDecodesWithTheStatusPresent() throws {
        let json = """
        {"success": true, "count": 1, "totalSize": 100, "files": [
            {"id": 6726, "originalName": "a.heic", "filename": "a.jpg", "publicToken": "t",
             "size": 100, "mimetype": "image/jpeg", "path": null,
             "uploadedAt": "2026-08-24T20:04:20.278643Z", "displayOrder": 27,
             "tags": [], "albumId": 37, "albumName": "test13", "processingStatus": "QUEUED"}
        ]}
        """
        let response = try JSONDecoder().decode(FilesResponse.self, from: Data(json.utf8))
        #expect(response.files.count == 1)
        #expect(response.files[0].processing == .queued)
        #expect(!response.files[0].isThumbnailReady)
    }
}
