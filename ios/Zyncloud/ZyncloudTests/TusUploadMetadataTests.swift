import Foundation
import Testing

@testable import Zyncloud

/// `Upload-Metadata` is a wire format the server parses: comma-separated `key <base64>`
/// pairs, per the TUS spec. A mistake here fails server-side with an error that doesn't
/// point back at this function, so it's worth pinning down.
struct TusUploadMetadataTests {
    private func pairs(_ header: String) -> [String: String] {
        var result: [String: String] = [:]
        for component in header.components(separatedBy: ",") {
            let parts = component.components(separatedBy: " ")
            guard parts.count == 2 else { continue }
            let decoded = Data(base64Encoded: parts[1]).flatMap { String(data: $0, encoding: .utf8) }
            result[parts[0]] = decoded
        }
        return result
    }

    @Test func encodesTheRequiredKeys() {
        let api = APIClient()
        let header = api.tusUploadMetadata(
            filename: "IMG_0001.HEIC",
            mimeType: "image/heic",
            contentId: "ABC-123/L0/001",
        )

        let decoded = pairs(header)
        #expect(decoded["filename"] == "IMG_0001.HEIC")
        #expect(decoded["filetype"] == "image/heic")
        #expect(decoded["contentId"] == "ABC-123/L0/001")
    }

    @Test func everyValueIsBase64Encoded() {
        let api = APIClient()
        let header = api.tusUploadMetadata(filename: "a.jpg", mimeType: "image/jpeg", contentId: "id")

        // The raw values must not appear in the clear — the whole point of base64 here is
        // that filenames may contain commas and spaces, which are the header's delimiters.
        #expect(!header.contains("a.jpg"))
        #expect(!header.contains("image/jpeg"))
        for component in header.components(separatedBy: ",") {
            let parts = component.components(separatedBy: " ")
            #expect(parts.count == 2)
            #expect(Data(base64Encoded: parts[1]) != nil)
        }
    }

    @Test(arguments: [
        "holiday, lisbon.jpg",
        "spaces everywhere.jpg",
        "üñïçødé 📸.heic",
        "comma,,,comma.mov",
    ])
    func delimiterBearingFilenamesRoundTrip(filename: String) {
        let api = APIClient()
        let header = api.tusUploadMetadata(filename: filename, mimeType: "image/jpeg", contentId: "id")
        #expect(pairs(header)["filename"] == filename)
    }

    @Test func albumIdIsOmittedWhenNil() {
        let api = APIClient()
        let header = api.tusUploadMetadata(filename: "a.jpg", mimeType: "image/jpeg", contentId: "id")
        #expect(pairs(header)["albumId"] == nil)
    }

    @Test func albumIdIsIncludedWhenSet() {
        let api = APIClient()
        let header = api.tusUploadMetadata(
            filename: "a.jpg", mimeType: "image/jpeg", contentId: "id", albumId: 42,
        )
        #expect(pairs(header)["albumId"] == "42")
    }

    @Test func authIsOmittedWithoutCredentials() {
        let api = APIClient()
        let header = api.tusUploadMetadata(filename: "a.jpg", mimeType: "image/jpeg", contentId: "id")
        #expect(pairs(header)["auth"] == nil)
    }

    /// The server reads credentials out of Upload-Metadata because tusd does not forward
    /// arbitrary headers to its hooks. Colons are the delimiter here, so a password
    /// containing one must still arrive intact.
    @Test func authCarriesCredentialsWhenSet() {
        let api = APIClient(username: "user@example.com", password: "pass:word")
        let header = api.tusUploadMetadata(filename: "a.jpg", mimeType: "image/jpeg", contentId: "id")
        #expect(pairs(header)["auth"] == "user@example.com:pass:word")
    }

    @Test func authIsOmittedWhenOnlyOneHalfIsPresent() {
        #expect(pairs(APIClient(username: "user@example.com")
            .tusUploadMetadata(filename: "a.jpg", mimeType: "image/jpeg", contentId: "id"))["auth"] == nil)
        #expect(pairs(APIClient(password: "hunter2")
            .tusUploadMetadata(filename: "a.jpg", mimeType: "image/jpeg", contentId: "id"))["auth"] == nil)
    }
}
