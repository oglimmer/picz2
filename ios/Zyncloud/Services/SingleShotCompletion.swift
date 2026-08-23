import Foundation

/// Runs an action **exactly once**, whoever gets there first.
///
/// Written for `BGTask.setTaskCompleted(success:)`, which has two failure modes in opposite
/// directions and a race between them:
///
/// - Never calling it after the expiration handler fires makes iOS terminate the app. That is a
///   `SIGKILL` — Xcode reports "Debug session ended with code 9: killed" — and it also costs the
///   app future background time.
/// - Calling it twice is a programming error the system traps on.
///
/// The normal finish and the expiration handler can both reach the completion at the same moment
/// on different threads, so "have we finished?" needs a lock rather than a plain `Bool`.
final class SingleShotCompletion {
    private let lock = NSLock()
    private var hasFired = false
    private let action: (Bool) -> Void

    init(_ action: @escaping (Bool) -> Void) {
        self.action = action
    }

    /// Runs the action if it has not run yet. Returns whether this call was the one that ran it,
    /// which is what makes the behaviour testable without a real `BGTask`.
    @discardableResult
    func fire(success: Bool) -> Bool {
        lock.lock()
        if hasFired {
            lock.unlock()
            return false
        }
        hasFired = true
        lock.unlock()

        action(success)
        return true
    }

    var hasCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasFired
    }
}
