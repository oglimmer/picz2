import Foundation
import Testing
@testable import Zyncloud

/// §5.9 — the expiry rule behind the scoped upload token.
///
/// The refresh decision is the part worth pinning: too eager and every batch mints a token, too
/// lazy and a token dies mid-upload and the asset is reported as a permanent failure.
struct UploadTokenStoreTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func noTokenMeansRefresh() {
        #expect(UploadTokenStore.needsRefresh(token: nil, expiresAt: now.addingTimeInterval(3600), now: now))
    }

    @Test func aTokenWithNoKnownExpiryIsNotTrusted() {
        #expect(UploadTokenStore.needsRefresh(token: "zut_abc", expiresAt: nil, now: now))
    }

    @Test func aFreshTokenIsReused() {
        #expect(!UploadTokenStore.needsRefresh(token: "zut_abc",
                                               expiresAt: now.addingTimeInterval(3600), now: now))
    }

    @Test func anExpiredTokenIsRefreshed() {
        #expect(UploadTokenStore.needsRefresh(token: "zut_abc",
                                              expiresAt: now.addingTimeInterval(-1), now: now))
    }

    /// The margin is the whole point: a batch picks up a token and then spends minutes on the
    /// wire, so a token that is *technically* still valid but expires during the upload has to
    /// count as stale before the upload starts.
    @Test func aTokenInsideTheRefreshMarginCountsAsStale() {
        let margin = UploadTokenStore.refreshMargin
        #expect(UploadTokenStore.needsRefresh(token: "zut_abc",
                                              expiresAt: now.addingTimeInterval(margin - 1), now: now))
        #expect(!UploadTokenStore.needsRefresh(token: "zut_abc",
                                               expiresAt: now.addingTimeInterval(margin + 1), now: now))
    }

    @Test func theMarginIsInclusiveAtTheBoundary() {
        // Exactly at the margin refreshes rather than gambling on the round trip being instant.
        #expect(UploadTokenStore.needsRefresh(
            token: "zut_abc",
            expiresAt: now.addingTimeInterval(UploadTokenStore.refreshMargin), now: now
        ))
    }
}
