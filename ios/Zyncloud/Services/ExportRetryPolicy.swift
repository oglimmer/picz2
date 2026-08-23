import Foundation

/// Decides how many times a failing asset export is worth retrying.
///
/// Extracted from `SyncCoordinator` so the give-up rule is a pure, testable decision
/// rather than a counter buried in an upload completion handler. The bug it exists for:
/// a permanently un-exportable asset (iCloud original unavailable, corrupt resource) was
/// re-appended to the queue every 10 s with no cap, for as long as the app ran.
struct ExportRetryPolicy {
    enum Decision: Equatable {
        case retry(attempt: Int)
        case giveUp(afterAttempts: Int)
    }

    let maxAttempts: Int

    private var failures: [String: Int] = [:]

    init(maxAttempts: Int = 3) {
        self.maxAttempts = maxAttempts
    }

    /// Records one failure for `id` and says whether it is worth another go.
    mutating func recordFailure(for id: String) -> Decision {
        let attempt = (failures[id] ?? 0) + 1
        failures[id] = attempt

        guard attempt < maxAttempts else {
            // Forget it on the way out: the asset is never marked uploaded, so a later
            // scan is free to start over from a clean slate.
            failures.removeValue(forKey: id)
            return .giveUp(afterAttempts: attempt)
        }
        return .retry(attempt: attempt)
    }

    /// A handoff succeeded — an earlier transient failure (an iCloud original that arrived
    /// on the second attempt) must not count toward a later give-up.
    mutating func recordSuccess(for id: String) {
        failures.removeValue(forKey: id)
    }

    mutating func reset() {
        failures.removeAll()
    }

    /// Consecutive failures recorded for `id` so far. Exposed for tests and diagnostics.
    func failureCount(for id: String) -> Int {
        failures[id] ?? 0
    }
}
