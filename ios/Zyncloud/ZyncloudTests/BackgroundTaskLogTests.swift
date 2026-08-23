import Foundation
import Testing
@testable import Zyncloud

/// §6 step 10 — the observability that would have made §3.3 visible. Background tasks were only
/// ever scheduled at launch, and the sole symptom was sync quietly stopping days later.
struct BackgroundTaskLogTests {
    private func withScratchLog(_ body: (BackgroundTaskLog, UserDefaults) throws -> Void) rethrows {
        let name = "test.bgtasklog.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(BackgroundTaskLog(defaults: defaults), defaults)
    }

    @Test func aFreshInstallHasNeverScheduledOrRun() {
        withScratchLog { log, _ in
            #expect(log.lastScheduled == nil)
            #expect(log.lastRun(.refresh) == nil)
            #expect(log.lastRun(.processing) == nil)
            #expect(log.runCount(.refresh) == 0)
            #expect(!log.hasScheduledButNeverRun)
        }
    }

    @Test func schedulingIsRecorded() {
        withScratchLog { log, _ in
            let when = Date(timeIntervalSince1970: 1_700_000_000)
            log.recordScheduled(at: when)
            #expect(log.lastScheduled == when)
        }
    }

    @Test func eachTaskKindIsTrackedSeparately() {
        withScratchLog { log, _ in
            let when = Date(timeIntervalSince1970: 1_700_000_000)
            log.recordRun(.refresh, at: when)

            #expect(log.lastRun(.refresh) == when)
            // The whole point of splitting them: one running does not imply the other did.
            #expect(log.lastRun(.processing) == nil)
        }
    }

    @Test func runsAreCounted() {
        withScratchLog { log, _ in
            log.recordRun(.processing)
            log.recordRun(.processing)
            log.recordRun(.refresh)

            #expect(log.runCount(.processing) == 2)
            #expect(log.runCount(.refresh) == 1)
        }
    }

    @Test func theLatestRunReplacesTheEarlierOne() {
        withScratchLog { log, _ in
            let first = Date(timeIntervalSince1970: 1_700_000_000)
            let second = Date(timeIntervalSince1970: 1_700_003_600)
            log.recordRun(.refresh, at: first)
            log.recordRun(.refresh, at: second)

            #expect(log.lastRun(.refresh) == second)
            #expect(log.runCount(.refresh) == 2)
        }
    }

    /// The §3.3 signature: we asked, iOS never came back. Distinct from "we never asked",
    /// which is the bug itself.
    @Test func scheduledButNeverRunIsItsOwnState() {
        withScratchLog { log, _ in
            log.recordScheduled()
            #expect(log.hasScheduledButNeverRun)

            log.recordRun(.refresh)
            #expect(!log.hasScheduledButNeverRun)
        }
    }

    @Test func neverScheduledIsNotReportedAsScheduledButNeverRun() {
        withScratchLog { log, _ in
            // Nothing scheduled at all — that is the broken-wiring case, not the waiting case.
            #expect(!log.hasScheduledButNeverRun)
        }
    }

    @Test func eitherKindRunningClearsTheWaitingState() {
        withScratchLog { log, _ in
            log.recordScheduled()
            log.recordRun(.processing)
            #expect(!log.hasScheduledButNeverRun)
        }
    }

    @Test func stateSurvivesARestart() {
        let name = "test.bgtasklog.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let first = BackgroundTaskLog(defaults: defaults)
        first.recordScheduled(at: when)
        first.recordRun(.refresh, at: when)

        // A background-task-only launch builds a fresh instance; the history must still be there,
        // otherwise the screen reads "Never" on every cold start and tells you nothing.
        let second = BackgroundTaskLog(defaults: defaults)
        #expect(second.lastScheduled == when)
        #expect(second.lastRun(.refresh) == when)
        #expect(second.runCount(.refresh) == 1)
    }

    @Test func resetClearsEverything() {
        withScratchLog { log, _ in
            log.recordScheduled()
            log.recordRun(.refresh)
            log.recordRun(.processing)

            log.reset()

            #expect(log.lastScheduled == nil)
            #expect(log.lastRun(.refresh) == nil)
            #expect(log.runCount(.processing) == 0)
        }
    }
}
