import Foundation
import Testing
@testable import Zyncloud

/// `SyncLogger` used to re-encode its whole 100-entry buffer and write `UserDefaults` on every
/// single log line, on the main thread — one or two per upload, three uploads at a time. That is
/// the write amplification §5.7 removed from `UploadStore`; these cases pin the same shape here.
///
/// Main-actor so `runOnMain` runs inline: the assertions can then read the effect of a call on
/// the line after it, with no waiting.
@MainActor
struct SyncLoggerTests {
    /// Hardcoded rather than read off the type: the key is `private`, and `@testable` does not
    /// reach that. Same approach as `SettingsTests`.
    private static let logsKey = "sync_logs"

    private func withScratchDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "test.synclogger.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    private func storedLogs(in defaults: UserDefaults) -> [SyncLogEntry]? {
        guard let data = defaults.data(forKey: Self.logsKey) else { return nil }
        return try? JSONDecoder().decode([SyncLogEntry].self, from: data)
    }

    // MARK: - Coalescing

    /// The whole point. A burst of entries must not each pay for a serialisation — with the save
    /// delay parked far enough out that its timer cannot fire during the test, nothing should
    /// have reached `UserDefaults` yet.
    @Test func aBurstOfEntriesDoesNotWriteOncePerEntry() {
        withScratchDefaults { defaults in
            let logger = SyncLogger(defaults: defaults, saveDelay: 600)
            for index in 0 ..< 20 {
                logger.logUploadSuccess(assetId: "asset-\(index)")
            }
            #expect(logger.logs.count == 20)
            #expect(defaults.data(forKey: Self.logsKey) == nil)
        }
    }

    /// …and the entries are not lost by not being written: the flush the app performs when it
    /// backgrounds persists everything the burst added, in one write.
    @Test func flushingPersistsThePendingBurst() {
        withScratchDefaults { defaults in
            let logger = SyncLogger(defaults: defaults, saveDelay: 600)
            for index in 0 ..< 20 {
                logger.logUploadSuccess(assetId: "asset-\(index)")
            }
            logger.flushPendingWrites()
            #expect(storedLogs(in: defaults)?.count == 20)
        }
    }

    @Test func flushingWithNothingLoggedIsHarmless() {
        withScratchDefaults { defaults in
            let logger = SyncLogger(defaults: defaults, saveDelay: 600)
            logger.flushPendingWrites()
            #expect(storedLogs(in: defaults)?.isEmpty == true)
        }
    }

    // MARK: - Round trip

    /// A background-only launch builds a fresh instance, so history that did not survive the
    /// write would read as an empty Log tab on every cold start.
    @Test func persistedLogsAreReadBackByTheNextInstance() {
        withScratchDefaults { defaults in
            let first = SyncLogger(defaults: defaults, saveDelay: 600)
            first.logUploadFailure(assetId: "abcdef123456", error: "HTTP 500")
            first.flushPendingWrites()

            let second = SyncLogger(defaults: defaults, saveDelay: 600)
            #expect(second.logs.count == 1)
            #expect(second.logs.first?.success == false)
            #expect(second.logs.first?.message.contains("HTTP 500") == true)
        }
    }

    /// Newest first, because that is the order the Log tab renders.
    @Test func theNewestEntryIsFirst() {
        withScratchDefaults { defaults in
            let logger = SyncLogger(defaults: defaults, saveDelay: 600)
            logger.logUploadSuccess(assetId: "older")
            logger.logUploadSuccess(assetId: "newer")
            #expect(logger.logs.first?.message.contains("newer") == true)
        }
    }

    // MARK: - The cap

    /// The buffer is bounded, which is what keeps a single write cheap however long the app runs.
    @Test func theBufferIsCappedAtOneHundredEntries() {
        withScratchDefaults { defaults in
            let logger = SyncLogger(defaults: defaults, saveDelay: 600)
            for index in 0 ..< 150 {
                logger.logUploadSuccess(assetId: "asset-\(index)")
            }
            logger.flushPendingWrites()
            #expect(logger.logs.count == 100)
            #expect(storedLogs(in: defaults)?.count == 100)
        }
    }

    /// Clearing has to reach the stored copy too, or the entries come back on the next launch.
    @Test func clearingEmptiesThePersistedBuffer() {
        withScratchDefaults { defaults in
            let logger = SyncLogger(defaults: defaults, saveDelay: 600)
            logger.logUploadSuccess(assetId: "asset")
            logger.flushPendingWrites()
            #expect(storedLogs(in: defaults)?.count == 1)

            logger.clearLogs()
            logger.flushPendingWrites()
            #expect(storedLogs(in: defaults)?.isEmpty == true)
        }
    }
}
