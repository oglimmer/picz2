import Foundation
import Testing

@testable import Zyncloud

/// Contract tests for the JSON the server returns.
///
/// NOTE: these fixtures were written from the client-side models, not captured from a live
/// server. They lock down what the client currently *requires*, which is enough to catch an
/// accidental model change — but replacing them with recorded real responses would make them
/// genuinely authoritative. Worth doing next time someone has the server in front of them.
struct ServerResponseDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Albums

    @Test func decodesAnAlbumsResponse() throws {
        let response = try decode(AlbumsResponse.self, """
        {
          "success": true,
          "albums": [
            {
              "id": 7,
              "name": "Summer 2024",
              "description": "Beach",
              "createdAt": "2024-06-01T10:00:00Z",
              "updatedAt": "2024-06-02T10:00:00Z",
              "displayOrder": 1,
              "fileCount": 12,
              "coverImageFilename": "IMG_0001.jpg",
              "coverImageToken": "tok_cover",
              "shareToken": "tok_share"
            }
          ]
        }
        """)

        #expect(response.success)
        #expect(response.albums.count == 1)
        #expect(response.albums[0].id == 7)
        #expect(response.albums[0].name == "Summer 2024")
        #expect(response.albums[0].fileCount == 12)
        #expect(response.albums[0].imageCount == 12)
    }

    /// Everything but `id` and `name` is optional, so a minimal album must still decode.
    @Test func decodesAnAlbumWithOnlyRequiredFields() throws {
        let album = try decode(Album.self, #"{ "id": 1, "name": "Inbox" }"#)
        #expect(album.id == 1)
        #expect(album.description == nil)
        #expect(album.coverImageToken == nil)
        #expect(album.imageCount == nil)
    }

    // MARK: - Files

    @Test func decodesAFilesResponse() throws {
        let response = try decode(FilesResponse.self, """
        {
          "success": true,
          "count": 1,
          "totalSize": 2048,
          "files": [
            {
              "id": 31,
              "originalName": "IMG_0001.HEIC",
              "filename": "abc.heic",
              "publicToken": "tok_public",
              "size": 2048,
              "mimetype": "image/heic",
              "path": "/data/abc.heic",
              "uploadedAt": "2024-06-01T10:00:00Z",
              "displayOrder": 0,
              "tags": ["beach"],
              "albumId": 7,
              "albumName": "Summer 2024"
            }
          ]
        }
        """)

        #expect(response.files.count == 1)
        #expect(response.files[0].publicToken == "tok_public")
        #expect(response.files[0].tags == ["beach"])
    }

    /// `filename` and `path` are documented as nullable in the model.
    @Test func decodesAFileWithNullableFieldsAbsent() throws {
        let file = try decode(FileInfo.self, """
        {
          "id": 31, "originalName": "IMG_0001.HEIC", "publicToken": "t",
          "size": 2048, "uploadedAt": "2024-06-01T10:00:00Z",
          "tags": [], "albumId": 7
        }
        """)
        #expect(file.filename == nil)
        #expect(file.path == nil)
        #expect(file.tags.isEmpty)
    }

    /// Documents a fragility rather than endorsing it: `tags` is non-optional, so a server
    /// that omits the key for an untagged file breaks the whole album listing. If that ever
    /// happens, the fix is `[String]?` on the model, and this test should be inverted.
    @Test func aFileMissingTagsFailsToDecode() {
        #expect(throws: DecodingError.self) {
            try decode(FileInfo.self, """
            {
              "id": 31, "originalName": "IMG_0001.HEIC", "publicToken": "t",
              "size": 2048, "uploadedAt": "2024-06-01T10:00:00Z", "albumId": 7
            }
            """)
        }
    }

    // MARK: - Capabilities

    @Test func decodesCapabilities() throws {
        let caps = try decode(Capabilities.self, """
        {
          "tus": { "enabled": true, "endpoint": "/files/", "version": "1.0.0", "maxSize": 5368709120 },
          "multipart": { "enabled": true, "endpoint": "/api/upload" }
        }
        """)
        #expect(caps.tus.enabled)
        #expect(caps.tus.endpoint == "/files/")
        #expect(caps.tus.maxSize == 5_368_709_120)
        #expect(caps.multipart.enabled)
    }

    // MARK: - Processing status

    @Test func decodesEveryProcessingStatusAndItsTerminality() throws {
        let cases: [(raw: String, expected: AssetProcessingStatus, isTerminal: Bool)] = [
            ("QUEUED", .queued, false),
            ("PROCESSING", .processing, false),
            ("DONE", .done, true),
            ("FAILED", .failed, true),
            ("DEAD_LETTER", .deadLetter, true),
        ]

        for expectation in cases {
            let response = try decode(AssetProcessingStatusResponse.self, """
            { "id": 1, "processingStatus": "\(expectation.raw)" }
            """)
            #expect(response.processingStatus == expectation.expected)
            #expect(response.processingStatus.isTerminal == expectation.isTerminal)
        }
    }

    @Test func decodesAFailedStatusWithAnErrorDetail() throws {
        let response = try decode(AssetProcessingStatusResponse.self, """
        {
          "id": 99, "processingStatus": "DEAD_LETTER", "attempts": 5,
          "completedAt": "2024-06-01T10:00:00Z", "error": "transcode timed out"
        }
        """)
        #expect(response.attempts == 5)
        #expect(response.error == "transcode timed out")
    }

    @Test func anUnknownProcessingStatusFailsToDecode() {
        #expect(throws: DecodingError.self) {
            try decode(AssetProcessingStatusResponse.self, #"{ "id": 1, "processingStatus": "SKIPPED" }"#)
        }
    }

    /// `lookupAssetByContentId` hits GET /api/assets/by-content but decodes the *status*
    /// model just to read `id`. That couples TUS status polling to a field the endpoint has
    /// no obvious reason to return. If by-content ever answers with a slimmer payload, the
    /// lookup fails, `resolveTusUploadServerId` exhausts its retries, and polling silently
    /// stops — visible only as "Processing status unavailable" log lines.
    @Test func byContentLookupBreaksIfTheResponseOmitsProcessingStatus() {
        #expect(throws: DecodingError.self) {
            try decode(AssetProcessingStatusResponse.self, #"{ "id": 42 }"#)
        }
    }

    // MARK: - Sync / settings / auth

    @Test func decodesUploadedChecksums() throws {
        let response = try decode(SyncChecksumsResponse.self, """
        { "success": true, "count": 2, "checksums": ["aa", "bb"] }
        """)
        #expect(response.checksums == ["aa", "bb"])
    }

    @Test func decodesTargetAlbumIncludingTheClearedCase() throws {
        #expect(try decode(TargetAlbumResponse.self, #"{ "success": true, "albumId": 7 }"#).albumId == 7)
        #expect(try decode(TargetAlbumResponse.self, #"{ "success": true, "albumId": null }"#).albumId == nil)
        #expect(try decode(TargetAlbumResponse.self, #"{ "success": true }"#).albumId == nil)
    }

    @Test func decodesAuthCheck() throws {
        let response = try decode(AuthCheckResponse.self, """
        { "success": true, "email": "user@example.com", "emailVerified": false }
        """)
        #expect(response.success)
        #expect(response.email == "user@example.com")
        #expect(response.emailVerified == false)
    }

    @Test func decodesAnErrorResponse() throws {
        let response = try decode(ErrorResponse.self, #"{ "success": false, "message": "sync is paused" }"#)
        #expect(response.message == "sync is paused")
    }
}
