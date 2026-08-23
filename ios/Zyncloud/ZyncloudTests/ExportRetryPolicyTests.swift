import Testing
@testable import Zyncloud

/// Covers §5.4 — an asset whose export can never succeed being re-queued every 10 s for as
/// long as the app runs.
struct ExportRetryPolicyTests {
    @Test func retriesUpToTheCapThenGivesUp() {
        var policy = ExportRetryPolicy(maxAttempts: 3)

        #expect(policy.recordFailure(for: "asset-1") == .retry(attempt: 1))
        #expect(policy.recordFailure(for: "asset-1") == .retry(attempt: 2))
        #expect(policy.recordFailure(for: "asset-1") == .giveUp(afterAttempts: 3))
    }

    /// The bug: without a cap this never stopped. Hammer it well past the threshold and
    /// confirm it never returns to retrying.
    @Test func neverRetriesAgainOnceItHasGivenUpOnARunOfFailures() {
        var policy = ExportRetryPolicy(maxAttempts: 3)
        _ = policy.recordFailure(for: "bad")
        _ = policy.recordFailure(for: "bad")
        #expect(policy.recordFailure(for: "bad") == .giveUp(afterAttempts: 3))

        // A fresh run of failures starts over — the asset was never marked uploaded, so a
        // later scan is entitled to try again — but each run still terminates.
        #expect(policy.recordFailure(for: "bad") == .retry(attempt: 1))
        #expect(policy.recordFailure(for: "bad") == .retry(attempt: 2))
        #expect(policy.recordFailure(for: "bad") == .giveUp(afterAttempts: 3))
    }

    @Test func aSuccessfulHandoffClearsEarlierFailures() {
        var policy = ExportRetryPolicy(maxAttempts: 3)
        _ = policy.recordFailure(for: "flaky")
        _ = policy.recordFailure(for: "flaky")
        #expect(policy.failureCount(for: "flaky") == 2)

        policy.recordSuccess(for: "flaky")
        #expect(policy.failureCount(for: "flaky") == 0)

        // A transient failure that eventually worked must not push a later one over the cap.
        #expect(policy.recordFailure(for: "flaky") == .retry(attempt: 1))
    }

    @Test func assetsAreCountedIndependently() {
        var policy = ExportRetryPolicy(maxAttempts: 3)
        _ = policy.recordFailure(for: "a")
        _ = policy.recordFailure(for: "a")
        #expect(policy.recordFailure(for: "b") == .retry(attempt: 1))
        #expect(policy.recordFailure(for: "a") == .giveUp(afterAttempts: 3))
        #expect(policy.recordFailure(for: "b") == .retry(attempt: 2))
    }

    @Test func givingUpForgetsTheAssetSoALaterScanStartsClean() {
        var policy = ExportRetryPolicy(maxAttempts: 2)
        _ = policy.recordFailure(for: "gone")
        #expect(policy.recordFailure(for: "gone") == .giveUp(afterAttempts: 2))
        #expect(policy.failureCount(for: "gone") == 0)
    }

    @Test func resetClearsEveryAsset() {
        var policy = ExportRetryPolicy(maxAttempts: 3)
        _ = policy.recordFailure(for: "a")
        _ = policy.recordFailure(for: "b")

        policy.reset()

        #expect(policy.failureCount(for: "a") == 0)
        #expect(policy.failureCount(for: "b") == 0)
    }

    /// A cap of 1 means "one failure and stop" — no retry at all. Guards against an
    /// off-by-one that would make the first failure retry forever.
    @Test func aCapOfOneGivesUpImmediately() {
        var policy = ExportRetryPolicy(maxAttempts: 1)
        #expect(policy.recordFailure(for: "x") == .giveUp(afterAttempts: 1))
    }

    @Test func theProductionDefaultIsThreeAttempts() {
        #expect(ExportRetryPolicy().maxAttempts == 3)
    }
}
