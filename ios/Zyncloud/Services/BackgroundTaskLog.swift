import Combine
import Foundation

/// Records when background tasks were last **scheduled** and last **run**.
///
/// This exists because of §3.3. The app is scene-based, so UIKit never called
/// `applicationDidEnterBackground`, and background tasks were only ever scheduled at launch —
/// one missed handler and scheduling stopped until a cold launch. Nothing in the code showed
/// that, and no unit test could: the only observable symptom was "sync silently stopped
/// happening", days later. A visible "last scheduled / last run" pair turns that from an
/// invisible failure into an obvious one.
///
/// Scheduling and running are tracked separately on purpose. "Scheduled recently but never run"
/// and "never scheduled at all" are different faults with different causes — the first is iOS
/// declining to give us time, the second is our own wiring being broken again.
/// - Note: `@unchecked Sendable` — this class stores nothing of its own. Every value lives in
///   `UserDefaults`, which is thread-safe, and the SwiftUI notification is hopped to main.
final class BackgroundTaskLog: ObservableObject, @unchecked Sendable {
    static let shared = BackgroundTaskLog()

    enum Kind: String, CaseIterable {
        case refresh
        case processing
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let scheduled = "bgtask.lastScheduledAt"
        static func lastRun(_ kind: Kind) -> String { "bgtask.lastRun.\(kind.rawValue)" }
        static func runCount(_ kind: Kind) -> String { "bgtask.runCount.\(kind.rawValue)" }
    }

    /// Injectable so tests can drive a scratch suite instead of the real preferences.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Recording

    func recordScheduled(at date: Date = Date()) {
        defaults.set(date, forKey: Keys.scheduled)
        notifyChanged()
    }

    func recordRun(_ kind: Kind, at date: Date = Date()) {
        defaults.set(date, forKey: Keys.lastRun(kind))
        defaults.set(runCount(kind) + 1, forKey: Keys.runCount(kind))
        notifyChanged()
    }

    // MARK: - Reading

    var lastScheduled: Date? { defaults.object(forKey: Keys.scheduled) as? Date }

    func lastRun(_ kind: Kind) -> Date? { defaults.object(forKey: Keys.lastRun(kind)) as? Date }

    func runCount(_ kind: Kind) -> Int { defaults.integer(forKey: Keys.runCount(kind)) }

    /// True when tasks have been scheduled but nothing has ever run. On a device this is normal
    /// for a while — iOS decides when to grant time — but it is also exactly what §3.3 looked
    /// like, so it is worth showing rather than hiding.
    var hasScheduledButNeverRun: Bool {
        lastScheduled != nil && Kind.allCases.allSatisfy { lastRun($0) == nil }
    }

    func reset() {
        defaults.removeObject(forKey: Keys.scheduled)
        for kind in Kind.allCases {
            defaults.removeObject(forKey: Keys.lastRun(kind))
            defaults.removeObject(forKey: Keys.runCount(kind))
        }
        notifyChanged()
    }

    private func notifyChanged() {
        // Recording happens on background-task threads; SwiftUI must hear about it on main.
        if Thread.isMainThread {
            objectWillChange.send()
        } else {
            DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
        }
    }
}
