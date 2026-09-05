import Foundation
import Testing
@testable import Zyncloud

/// The "storage full" banner: the wire shape of `/api/storage-usage`, and the monitor's three
/// rules — the server's `full` is the verdict, a failed fetch keeps the last answer, and a 507
/// puts the banner up before any answer arrives.
struct StorageUsageTests {
    private func decode(_ json: String) throws -> StorageUsage {
        try JSONDecoder().decode(StorageUsage.self, from: Data(json.utf8))
    }

    @Test func `decodes the server's row`() throws {
        let usage = try decode("""
        {"usedBytes": 104857600, "quotaBytes": 104857600, "remainingBytes": 0, "full": true}
        """)
        #expect(usage.full)
        #expect(usage.remainingBytes == 0)
        #expect(usage.summary == "100 MB of 100 MB used")
    }

    /// The numbers say full; the server says not. The server wins, so what is shown cannot drift
    /// from what the upload path enforces.
    @Test func `full is the verdict of the server and not arithmetic`() throws {
        let usage = try decode("""
        {"usedBytes": 100, "quotaBytes": 100, "remainingBytes": 0, "full": false}
        """)
        #expect(!usage.full)
    }

    @MainActor
    @Suite struct Monitor {
        /// A monitor whose server answers from a script, one entry per call, and records how
        /// many times it was asked.
        private final class Script: @unchecked Sendable {
            private let lock = NSLock()
            private var answers: [Result<StorageUsage, Error>]
            private var callCount = 0

            /// How many times the monitor asked.
            var calls: Int {
                lock.lock()
                defer { lock.unlock() }
                return callCount
            }

            init(_ answers: [Result<StorageUsage, Error>]) {
                self.answers = answers
            }

            func next() -> Result<StorageUsage, Error> {
                lock.lock()
                defer { lock.unlock() }
                callCount += 1
                return answers.isEmpty ? .failure(URLError(.badServerResponse)) : answers.removeFirst()
            }
        }

        private static func usage(full: Bool) -> StorageUsage {
            StorageUsage(usedBytes: full ? 100 : 10, quotaBytes: 100, remainingBytes: full ? 0 : 90, full: full)
        }

        private func makeMonitor(_ script: Script, coalesceDelay: TimeInterval = 0.01) -> StorageUsageMonitor {
            StorageUsageMonitor(
                fetch: { completion in completion(script.next()) },
                coalesceDelay: coalesceDelay,
            )
        }

        @Test func `the banner follows the answer of the server`() async {
            let script = Script([.success(Self.usage(full: true)), .success(Self.usage(full: false))])
            let monitor = makeMonitor(script)
            #expect(!monitor.isFull)

            await monitor.refreshNow()
            #expect(monitor.isFull)

            await monitor.refreshNow()
            #expect(!monitor.isFull)
        }

        @Test func `a failed fetch keeps the last answer`() async {
            let script = Script([.success(Self.usage(full: true)), .failure(URLError(.notConnectedToInternet))])
            let monitor = makeMonitor(script)

            await monitor.refreshNow()
            await monitor.refreshNow()

            // The warning was true a moment ago; a dropped connection is no evidence otherwise.
            #expect(monitor.isFull)
        }

        @Test func `a 507 raises the banner before the numbers arrive`() async {
            let script = Script([.success(Self.usage(full: true))])
            let monitor = makeMonitor(script)

            monitor.noteStorageFull()
            #expect(monitor.isFull, "the uploader's evidence is enough to warn on")
            #expect(monitor.usage?.quotaBytes == 0, "no numbers yet, so the banner hides its second line")

            // The coalesced re-ask then replaces the assumption with the real row.
            try? await Task.sleep(for: .milliseconds(200))
            #expect(script.calls == 1)
            #expect(monitor.usage?.quotaBytes == 100)
        }

        @Test func `a burst of changes asks once`() async {
            let script = Script([.success(Self.usage(full: false))])
            let monitor = makeMonitor(script)

            for _ in 0 ..< 5 {
                monitor.refreshSoon()
            }
            try? await Task.sleep(for: .milliseconds(200))

            #expect(script.calls == 1)
        }

        @Test func `stopping forgets the answer`() async {
            let script = Script([.success(Self.usage(full: true))])
            let monitor = makeMonitor(script)
            await monitor.refreshNow()
            #expect(monitor.isFull)

            monitor.stop()

            // A sign-out must not carry one account's warning over to the next.
            #expect(!monitor.isFull)
            #expect(monitor.usage == nil)
        }
    }
}
