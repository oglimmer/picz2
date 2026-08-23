import Foundation
import Testing
@testable import Zyncloud

/// Found by the B5 device test: the app was `SIGKILL`ed ("code 9: killed") because the background
/// task expiration handlers logged and returned without ever calling `setTaskCompleted`.
struct SingleShotCompletionTests {
    @Test func theActionRunsOnce() {
        var calls: [Bool] = []
        let completion = SingleShotCompletion { calls.append($0) }

        #expect(completion.fire(success: true))
        #expect(calls == [true])
    }

    /// Completing a BGTask twice is a trap. Expiry and a normal finish are separate code paths
    /// that can both reach the completion.
    @Test func laterCallsAreIgnored() {
        var calls: [Bool] = []
        let completion = SingleShotCompletion { calls.append($0) }

        #expect(completion.fire(success: true))
        #expect(!completion.fire(success: false))
        #expect(!completion.fire(success: true))
        #expect(calls == [true])
    }

    /// The whole reason this type exists: whoever gets there first wins, and expiry losing the
    /// race must not mean the task goes uncompleted.
    @Test func expiryWinsWhenItGetsThereFirst() {
        var calls: [Bool] = []
        let completion = SingleShotCompletion { calls.append($0) }

        #expect(completion.fire(success: false))   // expiration handler
        #expect(!completion.fire(success: true))   // sync finishing afterwards
        #expect(calls == [false])
    }

    @Test func itReportsWhetherItHasCompleted() {
        let completion = SingleShotCompletion { _ in }
        #expect(!completion.hasCompleted)
        completion.fire(success: true)
        #expect(completion.hasCompleted)
    }

    /// A plain `Bool` would let two threads both see "not fired yet" and complete the task twice.
    @Test func onlyOneOfManyConcurrentCallersWins() {
        let counter = Counter()
        let completion = SingleShotCompletion { _ in counter.increment() }

        DispatchQueue.concurrentPerform(iterations: 200) { i in
            completion.fire(success: i.isMultiple(of: 2))
        }

        #expect(counter.value == 1)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }
}
