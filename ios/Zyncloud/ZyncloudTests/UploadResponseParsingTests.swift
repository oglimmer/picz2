import Foundation
import Testing

@testable import Zyncloud

/// The two response parsers on `Uploader`. Both are deliberately lenient — anything they
/// can't read degrades to a sensible default rather than failing the upload — so the tests
/// pin down exactly where that line sits.
struct UploadResponseParsingTests {
    private let uploader = Uploader.shared

    private func response(headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/api/upload")!,
            statusCode: 503,
            httpVersion: "HTTP/1.1",
            headerFields: headers,
        )!
    }

    // MARK: - Retry-After

    @Test func readsRetryAfterInSeconds() {
        #expect(uploader.parseRetryAfter(from: response(headers: ["Retry-After": "30"])) == 30)
        #expect(uploader.parseRetryAfter(from: response(headers: ["Retry-After": "0"])) == 0)
        #expect(uploader.parseRetryAfter(from: response(headers: ["Retry-After": "600"])) == 600)
    }

    @Test func toleratesSurroundingWhitespace() {
        #expect(uploader.parseRetryAfter(from: response(headers: ["Retry-After": "  45  "])) == 45)
    }

    @Test func returnsNilWhenTheHeaderIsAbsent() {
        #expect(uploader.parseRetryAfter(from: response(headers: [:])) == nil)
    }

    /// RFC 9110 also allows an HTTP-date. The server isn't expected to send one, and the
    /// parser deliberately returns nil so callers fall back to their 30 s default rather
    /// than misreading the date as a duration. Documented here so the behaviour is a
    /// decision rather than an oversight.
    @Test func returnsNilForTheHttpDateForm() {
        let value = "Wed, 21 Oct 2015 07:28:00 GMT"
        #expect(uploader.parseRetryAfter(from: response(headers: ["Retry-After": value])) == nil)
    }

    @Test(arguments: ["", "soon", "30s", "-", "NaN", "nan", "inf", "-inf", "-1", "-0.5"])
    func returnsNilForUnparseableValues(value: String) {
        #expect(uploader.parseRetryAfter(from: response(headers: ["Retry-After": value])) == nil)
    }

    // MARK: - Server asset id

    @Test func readsTheAssetIdFromAnUploadResponse() throws {
        let body = Data(#"{ "success": true, "file": { "id": 4321, "originalName": "IMG_0001.jpg" } }"#.utf8)
        #expect(uploader.parseServerAssetId(from: body) == 4321)
    }

    /// A nil here disables processing-status polling for that asset but still records the
    /// upload as a success — so every malformed shape must degrade, never crash.
    @Test(arguments: [
        "",
        "not json at all",
        #"{ }"#,
        #"{ "file": null }"#,
        #"{ "file": {} }"#,
        #"{ "file": { "id": "4321" } }"#,
        #"{ "file": { "id": null } }"#,
        #"{ "id": 4321 }"#,
        #"[ { "file": { "id": 4321 } } ]"#,
    ])
    func returnsNilForAnyShapeItCannotRead(json: String) {
        #expect(uploader.parseServerAssetId(from: Data(json.utf8)) == nil)
    }

    /// Background relaunches can deliver a truncated body; it must not trap.
    @Test func returnsNilForATruncatedBody() {
        let truncated = Data(#"{ "success": true, "file": { "id": 43"#.utf8)
        #expect(uploader.parseServerAssetId(from: truncated) == nil)
    }
}
