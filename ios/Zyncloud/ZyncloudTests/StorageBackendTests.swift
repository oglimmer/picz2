import Foundation
import Testing
@testable import Zyncloud

/// "Bring your own storage": the wire contract for `/api/storage-backends`, plus the two rules
/// the UI depends on — the site's own storage is never editable, and the secret key never comes
/// back from the server.
struct StorageBackendTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func `decodes the system default`() throws {
        let backend = try decode(StorageBackend.self, """
        {
          "id": 1,
          "name": "Default storage",
          "systemDefault": true,
          "endpoint": null,
          "region": "us-east-1",
          "bucket": null,
          "accessKey": null,
          "pathStyleAccess": true,
          "albumCount": 4,
          "createdAt": "2026-08-30T10:00:00Z"
        }
        """)

        #expect(backend.systemDefault)
        // Its endpoint and credentials live in the server's configuration, never in the row, so
        // the client must be happy with nulls here rather than treating them as a broken record.
        #expect(backend.endpoint == nil)
        #expect(backend.subtitle == "Provided by this site")
    }

    @Test func `decodes A user backend`() throws {
        let backend = try decode(StorageBackend.self, """
        {
          "id": 5,
          "name": "My Hetzner bucket",
          "systemDefault": false,
          "endpoint": "https://s3.example.com",
          "region": "eu-central-1",
          "bucket": "my-photos",
          "accessKey": "AKIAEXAMPLE",
          "pathStyleAccess": true,
          "albumCount": 0,
          "createdAt": "2026-08-30T10:00:00Z"
        }
        """)

        #expect(backend.name == "My Hetzner bucket")
        #expect(backend.subtitle == "https://s3.example.com · my-photos")
        #expect(backend.albumCount == 0)
    }

    /// The secret key is write-only on the server. If it ever appeared in a response the model
    /// would have nowhere to put it — this asserts the model has no such field to begin with.
    @Test func `a response carrying A secret key is ignored rather than stored`() throws {
        let backend = try decode(StorageBackend.self, """
        {
          "id": 5,
          "name": "Leaky",
          "systemDefault": false,
          "endpoint": "https://s3.example.com",
          "region": "us-east-1",
          "bucket": "b",
          "accessKey": "AKIA",
          "secretKey": "should-never-be-here",
          "pathStyleAccess": false,
          "albumCount": 0,
          "createdAt": null
        }
        """)

        #expect(backend.pathStyleAccess == false)
        let mirrored = Mirror(reflecting: backend).children.compactMap(\.label)
        #expect(!mirrored.contains("secretKey"))
    }

    @Test func `decodes A failed connection test`() throws {
        let result = try decode(StorageBackendTestResult.self, """
        { "ok": false, "failedStep": "write", "message": "Access Denied" }
        """)

        #expect(!result.ok)
        #expect(result.failedStep == "write")
        #expect(result.message == "Access Denied")
    }

    /// An empty secret is omitted from the body entirely: the server reads "absent" as "keep the
    /// stored key", and an empty string would read as an attempt to set a blank one.
    @Test func `an empty secret is omitted from the encoded body`() throws {
        let body = StorageBackendBody(
            name: "b",
            endpoint: "https://s3.example.com",
            region: "us-east-1",
            bucket: "bucket",
            accessKey: "AKIA",
            secretKey: nil,
            pathStyleAccess: true,
        )

        let json = try String(decoding: JSONEncoder().encode(body), as: UTF8.self)

        #expect(!json.contains("secretKey"))
    }

    /// An album from a server that predates per-album storage carries neither field, and must
    /// still decode — the picker simply has nothing to show for it.
    @Test func `an album without storage fields still decodes`() throws {
        let album = try decode(Album.self, #"{ "id": 1, "name": "Inbox" }"#)

        #expect(album.storageBackendId == nil)
        #expect(album.storageBackendName == nil)
    }

    @Test func `an album carries its storage`() throws {
        let album = try decode(Album.self, """
        { "id": 1, "name": "Inbox", "storageBackendId": 5, "storageBackendName": "My bucket" }
        """)

        #expect(album.storageBackendId == 5)
        #expect(album.storageBackendName == "My bucket")
    }

    // MARK: - Provider presets

    /// Every preset has to be usable as-is: a template you cannot edit into a real URL, or a
    /// missing hint, is a field the user is left guessing at.
    @Test func `every preset is complete`() {
        for provider in StorageProvider.all {
            #expect(!provider.label.isEmpty)
            #expect(provider.endpointTemplate.hasPrefix("https://"))
            #expect(!provider.regionHint.isEmpty)
            #expect(!provider.keysHint.isEmpty)
        }
    }

    /// AWS is the one provider that wants virtual-hosted addressing; everyone else here needs
    /// path-style, and getting it backwards produces a signature error that names neither.
    @Test func `only amazon defaults to virtual hosted addressing`() {
        for provider in StorageProvider.all {
            #expect(provider.pathStyleAccess == (provider.id != "aws"))
        }
    }

    /// The reason the guess matches on the domain suffix and not the prefix: "https://s3." starts
    /// both the Amazon and the Backblaze template, so a prefix match would file every B2 bucket
    /// under AWS and show it the wrong hints and the wrong addressing default.
    @Test(arguments: [
        ("https://s3.eu-central-1.amazonaws.com", "aws"),
        ("https://s3.eu-central-003.backblazeb2.com", "backblaze"),
        ("https://s3.eu-central-1.wasabisys.com", "wasabi"),
        ("https://s3.fr-par.scw.cloud", "scaleway"),
        ("https://abc123.r2.cloudflarestorage.com", "r2"),
        ("https://fsn1.your-objectstorage.com", "hetzner"),
        ("https://fra1.digitaloceanspaces.com", "digitalocean"),
    ])
    func `guesses the provider from its endpoint`(endpoint: String, expected: String) {
        #expect(StorageProvider.guess(fromEndpoint: endpoint).id == expected)
    }

    /// A trailing slash is what a person pastes out of a browser bar; it must not change the answer.
    @Test func `a trailing slash does not confuse the guess`() {
        #expect(StorageProvider.guess(fromEndpoint: "https://fsn1.your-objectstorage.com/").id == "hetzner")
    }

    /// An endpoint nobody recognises falls back to the generic preset rather than to whichever
    /// provider happens to be listed first, whose hints would simply be wrong.
    @Test func `an unknown endpoint falls back to other`() {
        #expect(StorageProvider.guess(fromEndpoint: "https://minio.mycompany.internal").id == "other")
        #expect(StorageProvider.guess(fromEndpoint: "").id == "other")
    }
}
