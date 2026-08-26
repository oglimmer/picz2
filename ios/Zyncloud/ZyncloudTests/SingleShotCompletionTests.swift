import Foundation
import Testing
@testable import Zyncloud

/// Found by the B5 device test: the app was `SIGKILL`ed ("code 9: killed") because the background
/// task expiration handlers logged and returned without ever calling `setTaskCompleted`.
/// Records what the completion was called with.
///
/// A class behind a lock rather than a local `var calls: [Bool]`: ``SingleShotCompletion`` takes
/// a `@Sendable` action, because in production it is called from a background-task expiration
/// handler, and a `@Sendable` closure cannot write to a local variable of the test that made it.
private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [Bool] = []

    func append(_ value: Bool) {
        lock.lock()
        calls.append(value)
        lock.unlock()
    }

    var recorded: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

struct SingleShotCompletionTests {
    @Test func theActionRunsOnce() {
        let calls = CallLog()
        let completion = SingleShotCompletion { calls.append($0) }

        #expect(completion.fire(success: true))
        #expect(calls.recorded == [true])
    }

    /// Completing a BGTask twice is a trap. Expiry and a normal finish are separate code paths
    /// that can both reach the completion.
    @Test func laterCallsAreIgnored() {
        let calls = CallLog()
        let completion = SingleShotCompletion { calls.append($0) }

        #expect(completion.fire(success: true))
        #expect(!completion.fire(success: false))
        #expect(!completion.fire(success: true))
        #expect(calls.recorded == [true])
    }

    /// The whole reason this type exists: whoever gets there first wins, and expiry losing the
    /// race must not mean the task goes uncompleted.
    @Test func expiryWinsWhenItGetsThereFirst() {
        let calls = CallLog()
        let completion = SingleShotCompletion { calls.append($0) }

        #expect(completion.fire(success: false))   // expiration handler
        #expect(!completion.fire(success: true))   // sync finishing afterwards
        #expect(calls.recorded == [false])
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
