import Foundation
import Testing

@testable import Zyncloud

/// `writeMultipartBody` streams the request body to disk so large videos never sit in
/// memory. It hand-rolls the multipart framing, so the byte layout is asserted exactly —
/// a missing CRLF is the kind of thing a server rejects with a generic 400.
struct MultipartBodyTests {
    private let boundary = "Boundary-TEST"

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeBody(
        fileContents: Data,
        filename: String = "IMG_0001.jpg",
        mimeType: String = "image/jpeg",
        contentId: String?,
    ) throws -> Data {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("source.bin")
        try fileContents.write(to: source)
        let destination = dir.appendingPathComponent("body.multipart")

        try APIClient().writeMultipartBody(
            to: destination,
            fileURL: source,
            filename: filename,
            mimeType: mimeType,
            boundary: boundary,
            contentId: contentId,
        )
        return try Data(contentsOf: destination)
    }

    @Test func framesTheFilePartExactly() throws {
        let body = try writeBody(fileContents: Data("PHOTO".utf8), contentId: nil)

        let expected = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"IMG_0001.jpg\"\r\n"
            + "Content-Type: image/jpeg\r\n\r\n"
            + "PHOTO\r\n"
            + "--\(boundary)--\r\n"
        #expect(body == Data(expected.utf8))
    }

    @Test func framesTheContentIdPartBeforeTheFile() throws {
        let body = try writeBody(fileContents: Data("PHOTO".utf8), contentId: "ABC-123/L0/001")

        let expected = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"contentId\"\r\n\r\n"
            + "ABC-123/L0/001\r\n"
            + "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"IMG_0001.jpg\"\r\n"
            + "Content-Type: image/jpeg\r\n\r\n"
            + "PHOTO\r\n"
            + "--\(boundary)--\r\n"
        #expect(body == Data(expected.utf8))
    }

    /// The file is streamed in 64 KB chunks; this crosses several chunk boundaries and
    /// includes bytes that are not valid UTF-8, which is what real photo data looks like.
    @Test func preservesBinaryContentAcrossChunkBoundaries() throws {
        var payload = Data()
        for i in 0 ..< (64 * 1024 * 2 + 1234) {
            payload.append(UInt8(i % 256))
        }

        let body = try writeBody(fileContents: payload, contentId: nil)

        let header = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"IMG_0001.jpg\"\r\n"
            + "Content-Type: image/jpeg\r\n\r\n"
        let trailer = "\r\n--\(boundary)--\r\n"

        #expect(body.count == header.utf8.count + payload.count + trailer.utf8.count)
        let start = header.utf8.count
        #expect(Data(body[start ..< (start + payload.count)]) == payload)
    }

    @Test func handlesAnEmptyFile() throws {
        let body = try writeBody(fileContents: Data(), contentId: nil)

        let expected = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"IMG_0001.jpg\"\r\n"
            + "Content-Type: image/jpeg\r\n\r\n"
            + "\r\n"
            + "--\(boundary)--\r\n"
        #expect(body == Data(expected.utf8))
    }

    /// Uploads are retried, and the destination is a fresh UUID path each time — but the
    /// overwrite branch exists, so it should not append to a stale body.
    @Test func overwritesAnExistingDestinationFile() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("source.bin")
        try Data("PHOTO".utf8).write(to: source)
        let destination = dir.appendingPathComponent("body.multipart")
        try Data(repeating: 0xFF, count: 4096).write(to: destination)

        try APIClient().writeMultipartBody(
            to: destination,
            fileURL: source,
            filename: "IMG_0001.jpg",
            mimeType: "image/jpeg",
            boundary: boundary,
            contentId: nil,
        )

        let body = try Data(contentsOf: destination)
        #expect(!body.contains(0xFF))
        #expect(body.count < 4096)
    }

    @Test func mimeTypeAndFilenameAppearInTheHeaders() throws {
        let body = try writeBody(
            fileContents: Data("MOVIE".utf8),
            filename: "IMG_0002.mov",
            mimeType: "video/quicktime",
            contentId: nil,
        )
        let text = try #require(String(data: body, encoding: .utf8))
        #expect(text.contains("filename=\"IMG_0002.mov\""))
        #expect(text.contains("Content-Type: video/quicktime"))
    }
}
