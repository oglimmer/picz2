import Foundation
import Testing
@testable import Zyncloud

/// §6 step 8 — the two routing decisions, as truth tables.
///
/// Both were the site of shipped bugs: §3.1 handed TUS background sessions to `Uploader`, so the
/// system completion handler for the *default* upload path was never called; and the path
/// selection has a third state that is easy to collapse into a boolean by mistake.
struct UploadRoutingTests {
    private func caps(tusEnabled: Bool, maxSize: Int64 = 524_288_000) -> Capabilities {
        Capabilities(
            tus: TusCapability(
                enabled: tusEnabled,
                endpoint: "https://example.com/files/",
                version: "1.0.0",
                maxSize: maxSize
            ),
            multipart: MultipartCapability(enabled: true, endpoint: "/api/upload")
        )
    }

    /// Album-screen TUS uploads must be looked up in the album they were sent to, not the
    /// background-sync target. `nil` override is the background-sync case.
    @Test func lookupUsesTheOverrideWhenThereIsOne() {
        #expect(UploadRouting.lookupAlbumId(override: 37, fallback: 1) == 37)
        #expect(UploadRouting.lookupAlbumId(override: nil, fallback: 1) == 1)
        #expect(UploadRouting.lookupAlbumId(override: nil, fallback: 9) == 9)
    }

    // MARK: - Path selection: the full truth table

    /// The server alone decides. There is no client-side opt-out any more.
    @Test(arguments: [
        (true, UploadPath.tus),
        (false, UploadPath.multipart),
    ])
    func pathFollowsTheServerCapability(serverEnabled: Bool, expected: UploadPath) {
        #expect(UploadRouting.selectPath(capabilities: caps(tusEnabled: serverEnabled)) == expected)
    }

    /// The third state, and the one most likely to be lost in a refactor: on the first drain
    /// after a cold launch nothing has been fetched yet. That is "we have not asked", not
    /// "the server said no" — but it still goes multipart rather than stalling the batch.
    @Test func capabilitiesNotYetLoadedFallsBackToMultipart() {
        #expect(UploadRouting.selectPath(capabilities: nil) == .multipart)
    }

    /// Only `tus.enabled` decides. A server that advertises TUS with an odd size limit is still
    /// a server that advertises TUS — size handling belongs to the uploader, not the router.
    @Test func theAdvertisedSizeLimitDoesNotAffectRouting() {
        #expect(UploadRouting.selectPath(capabilities: caps(tusEnabled: true, maxSize: 0)) == .tus)
        #expect(UploadRouting.selectPath(capabilities: caps(tusEnabled: false, maxSize: .max)) == .multipart)
    }

    // MARK: - Background session routing

    /// The §3.1 regression itself: a TUS identifier must reach TusUploader. Handing it to
    /// Uploader built a second URLSession on an identifier TusUploader already owned and left
    /// the TUS completion handler permanently uncalled.
    @Test func aTusIdentifierRoutesToTus() {
        let route = UploadRouting.route(
            forSessionIdentifier: "com.oglimmer.photosync.tus",
            tusSessionId: "com.oglimmer.photosync.tus",
            multipartSessionId: "com.oglimmer.photosync.upload"
        )
        #expect(route == .tus)
    }

    @Test func aMultipartIdentifierRoutesToMultipart() {
        let route = UploadRouting.route(
            forSessionIdentifier: "com.oglimmer.photosync.upload",
            tusSessionId: "com.oglimmer.photosync.tus",
            multipartSessionId: "com.oglimmer.photosync.upload"
        )
        #expect(route == .multipart)
    }

    /// An identifier from an older build must still be handled, not dropped. iOS requires the
    /// completion handler for every identifier it hands back to be invoked; ignoring one is the
    /// same "reduced background time" penalty §3.1 caused.
    @Test func anUnknownIdentifierIsStillHandledRatherThanDropped() {
        let route = UploadRouting.route(
            forSessionIdentifier: "com.oglimmer.photosync.fromAnOlderBuild",
            tusSessionId: "com.oglimmer.photosync.tus",
            multipartSessionId: "com.oglimmer.photosync.upload"
        )
        #expect(route == .multipart)
    }

    /// Matching is exact. A prefix relationship between the two identifiers must not let one
    /// swallow the other.
    @Test func matchingIsExactNotByPrefix() {
        let route = UploadRouting.route(
            forSessionIdentifier: "com.oglimmer.photosync.tus.extra",
            tusSessionId: "com.oglimmer.photosync.tus",
            multipartSessionId: "com.oglimmer.photosync.upload"
        )
        #expect(route != .tus)
    }

    @Test func matchingIsCaseSensitive() {
        let route = UploadRouting.route(
            forSessionIdentifier: "COM.OGLIMMER.PHOTOSYNC.TUS",
            tusSessionId: "com.oglimmer.photosync.tus",
            multipartSessionId: "com.oglimmer.photosync.upload"
        )
        #expect(route != .tus)
    }

    // MARK: - The invariant behind §3.2

    /// The two uploaders must never share a background session identifier. URLSession does not
    /// support two sessions on one identifier: the second orphans the first's delegate, and
    /// in-flight uploads lose the callback that frees their queue slot and deletes their temp
    /// file. That is the origin of the stuck `uploads.uploading.ids` entries.
    @Test func theTwoUploadersUseDistinctSessionIdentifiers() {
        #expect(TusUploader.shared.sessionId != Uploader.shared.sessionId)
    }

    /// Routing the real, production identifiers — not hand-written copies — so a change to
    /// either constant that broke the pairing would fail here.
    @Test func theProductionIdentifiersRouteToTheirOwnUploaders() {
        let tusId = TusUploader.shared.sessionId
        let multipartId = Uploader.shared.sessionId

        #expect(
            UploadRouting.route(forSessionIdentifier: tusId, tusSessionId: tusId, multipartSessionId: multipartId)
                == .tus
        )
        #expect(
            UploadRouting.route(forSessionIdentifier: multipartId, tusSessionId: tusId, multipartSessionId: multipartId)
                == .multipart
        )
    }
}
