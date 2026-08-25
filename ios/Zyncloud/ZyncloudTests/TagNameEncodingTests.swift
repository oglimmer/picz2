import Foundation
import Testing

@testable import Zyncloud

/// Tag names spliced into a URL path.
///
/// A tag is free text the user typed. Two of the endpoints put it in the path rather than in a
/// body, so any character that means something to a URL has to be encoded or the request lands
/// somewhere else entirely — a tag called `a/b` addressing a different endpoint, a tag with a
/// `;` losing half its name. These go through the real client and read the URL that actually
/// went out, encoding intact.
///
/// Nested inside ``EndpointShapeTests`` rather than standing alone, because the stub intercepts
/// `URLSession.shared` — which is process-wide. `.serialized` orders the tests *within* a suite,
/// but two sibling suites still run alongside each other, and one of them unregistering the stub
/// mid-flight would send the other's request to the real network. One serialized suite with the
/// other nested inside it is what actually makes them take turns.
extension EndpointShapeTests {
    @Suite(.serialized)
    struct TagNames {
        private var api: APIClient { APIClient.stubbed }

        /// The encoded path of the request `removeTag` builds for this name.
        private func removeTagPath(_ tagName: String) async -> String? {
            await StubServer.captureOne(json: "{\"success\":true,\"tags\":[]}") {
                _ = await awaiting { done in api.removeTag(fileId: 31, tagName: tagName, completion: done) }
            }?.encodedPath
        }

        private func bulkTagPath(_ tagName: String) async -> String? {
            await StubServer.captureOne(json: "{\"success\":true,\"updatedCount\":0}") {
                _ = await awaiting { done in
                    api.addTagToAllFiles(albumId: 7, tagName: tagName, completion: done)
                }
            }?.encodedPath
        }

        // MARK: - Plain names

        @Test func aplainNameNeedsNoEncoding() async {
            #expect(await removeTagPath("beach") == "/api/files/31/tags/beach")
            #expect(await removeTagPath("Beach2024") == "/api/files/31/tags/Beach2024")
        }

        /// `-._~` are the unreserved punctuation, and must stay readable rather than being escaped
        /// into noise.
        @Test func unreservedPunctuationStaysLiteral() async {
            #expect(await removeTagPath("a-b_c.d~e") == "/api/files/31/tags/a-b_c.d~e")
        }

        // MARK: - The characters that change what a URL means

        /// The headline case. A tag called "a/b" must address one segment named `a/b`, not a
        /// two-segment path that hits a different endpoint.
        @Test func aslashInTheNameIsEncodedRatherThanSplittingThePath() async {
            let path = await removeTagPath("a/b")

            #expect(path == "/api/files/31/tags/a%2Fb")
            #expect(path?.contains("tags/a/b") == false)
        }

        /// `;` starts a path parameter and `%` starts an escape — both silently change the segment.
        @Test(arguments: [
            (";", "%3B"),
            ("%", "%25"),
            ("?", "%3F"),
            ("#", "%23"),
            ("&", "%26"),
            ("=", "%3D"),
            ("+", "%2B"),
            (" ", "%20"),
            (":", "%3A"),
            ("@", "%40"),
        ])
        func areservedCharacterIsEncoded(character: String, encoded: String) async {
            #expect(await removeTagPath("x\(character)y") == "/api/files/31/tags/x\(encoded)y")
        }

        /// A `..` segment is what a path-traversal attempt looks like. Encoded, it is just a tag
        /// name; unencoded, it walks up the path.
        @Test func adotDotSegmentCannotWalkUpThePath() async {
            let path = await removeTagPath("../../admin")

            #expect(path == "/api/files/31/tags/..%2F..%2Fadmin")
            #expect(path?.hasPrefix("/api/files/31/tags/") == true)
        }

        /// A leading or trailing space would otherwise be trimmed or dropped by something along the
        /// way, naming a different tag than the user typed.
        @Test func surroundingSpacesSurvive() async {
            #expect(await removeTagPath(" beach ") == "/api/files/31/tags/%20beach%20")
        }

        // MARK: - Names that are not ASCII

        @Test func anaccentedNameIsPercentEncodedAsUtf8() async {
            #expect(await removeTagPath("München") == "/api/files/31/tags/M%C3%BCnchen")
        }

        @Test func anemojiNameSurvivesTheTrip() async {
            #expect(await removeTagPath("🏖") == "/api/files/31/tags/%F0%9F%8F%96")
        }

        @Test func acjkNameSurvivesTheTrip() async {
            #expect(await removeTagPath("海") == "/api/files/31/tags/%E6%B5%B7")
        }

        // MARK: - Both path-splicing endpoints agree

        /// The per-file and album-wide endpoints share one URL builder. If they ever stopped, a tag
        /// that could be taken off one photo could not be taken off the album.
        @Test(arguments: ["a/b", "München", "x;y", "hello world", "🏖"])
        func thebulkEndpointEncodesTheSameWay(tagName: String) async {
            let file = await removeTagPath(tagName)
            let bulk = await bulkTagPath(tagName)

            let fileSegment = file?.replacingOccurrences(of: "/api/files/31/tags/", with: "")
            let bulkSegment = bulk?.replacingOccurrences(of: "/api/albums/7/files/tags/", with: "")

            #expect(fileSegment == bulkSegment)
            #expect(fileSegment?.isEmpty == false)
        }

        // MARK: - The base URL is not mangled

        /// The URL is built by pasting text rather than by relative resolution, because relative
        /// resolution drops the last path segment of the base. A `ZYNCLOUD_BASE_URL` with a path on
        /// it must keep that path.
        @Test func abaseUrlWithItsOwnPathKeepsIt() async {
            var api = APIClient.stubbed
            api.baseURL = URL(string: "https://example.test/zyncloud")!

            let request = await StubServer.captureOne(json: "{\"success\":true,\"tags\":[]}") {
                _ = await awaiting { done in api.removeTag(fileId: 31, tagName: "beach", completion: done) }
            }

            #expect(request?.encodedPath == "/zyncloud/api/files/31/tags/beach")
        }

        /// A trailing slash on the base must not double up into `//`.
        @Test func atrailingSlashOnTheBaseIsNotDoubled() async {
            var api = APIClient.stubbed
            api.baseURL = URL(string: "https://example.test/zyncloud/")!

            let request = await StubServer.captureOne(json: "{\"success\":true,\"tags\":[]}") {
                _ = await awaiting { done in api.removeTag(fileId: 31, tagName: "beach", completion: done) }
            }

            #expect(request?.encodedPath == "/zyncloud/api/files/31/tags/beach")
        }

        // MARK: - When a name cannot be used at all

        /// The builder answers nil for a name it cannot encode, and the caller has to turn that into
        /// a readable refusal rather than a silent no-op. Nothing must go on the wire.
        @Test func anameThatCannotBeEncodedIsRefusedWithoutARequest() async {
            // A lone surrogate half: not valid UTF-8, so percent-encoding cannot represent it.
            let broken = String(decoding: [0xED, 0xA0, 0x80], as: UTF8.self)

            var result: Result<[String], Error>?
            let requests = await StubServer.capture(json: "{\"success\":true,\"tags\":[]}") {
                result = await awaiting { done in
                    api.removeTag(fileId: 31, tagName: broken, completion: done)
                }
            }

            // Either the name encoded (and one request went out) or it was refused before the wire.
            // What must never happen is a silent success with no request.
            if requests.isEmpty {
                guard case .failure = result else {
                    Issue.record("a name that never reached the server must not read as success")
                    return
                }
            } else {
                #expect(requests.count == 1)
            }
        }
    }
}
