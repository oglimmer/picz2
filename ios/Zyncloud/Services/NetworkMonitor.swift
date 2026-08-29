import Combine
import Foundation
import Network
import os

/// The kind of link the phone has, judged by the two flags that actually decide whether an
/// upload is allowed to leave — not by interface type.
///
/// Interface type is the tempting answer and the wrong one: a personal hotspot is Wi-Fi by
/// interface and cellular by cost, and Low Data Mode is neither. `isExpensive` /
/// `isConstrained` are the same pair ``URLRequest/applyNetworkPolicy()`` switches off, so a
/// gate built on them predicts URLSession's answer instead of guessing at it.
enum UploadLink: String, Sendable, Equatable {
    /// No usable path at all: airplane mode, no signal, no Wi-Fi.
    case offline
    /// A link `applyNetworkPolicy()` never refuses — Wi-Fi or Ethernet, full data.
    case unmetered
    /// Expensive (cellular, personal hotspot) or constrained (Low Data Mode). Exactly the set
    /// `allowsCellularAccess = false` turns into a -1009 "the Internet connection appears to
    /// be offline", which is the lie this whole file exists to stop showing the user.
    case metered

    init(satisfied: Bool, isExpensive: Bool, isConstrained: Bool) {
        guard satisfied else {
            self = .offline
            return
        }
        self = (isExpensive || isConstrained) ? .metered : .unmetered
    }
}

/// Why uploads are being held back, in the two lengths the app needs: a short one for the
/// Status tab's row, and a sentence for the sync log.
struct UploadPause: Sendable, Equatable {
    /// Fits in a table cell — "Waiting for Wi‑Fi".
    let status: String
    /// One sentence naming the cause, for the activity log.
    let detail: String
}

/// Whether uploads may run, given the link and the user's Wi‑Fi Only setting.
///
/// Pure, so the truth table is testable without a radio. ``NetworkMonitor`` only supplies the
/// link; every decision is here.
enum UploadNetworkPolicy {
    static func uploadsAllowed(link: UploadLink, wifiOnly: Bool) -> Bool {
        switch link {
        case .offline: false
        case .unmetered: true
        case .metered: !wifiOnly
        }
    }

    /// `nil` when uploads may run.
    static func pause(link: UploadLink, wifiOnly: Bool) -> UploadPause? {
        guard !uploadsAllowed(link: link, wifiOnly: wifiOnly) else { return nil }
        return switch link {
        case .offline:
            UploadPause(
                status: "No network",
                detail: "No usable connection — uploads wait until one is back.",
            )
        case .metered:
            UploadPause(
                status: "Waiting for Wi‑Fi",
                detail: "Wi‑Fi Only is on and this is a mobile or low-data connection — uploads wait for Wi‑Fi.",
            )
        // Unreachable: `uploadsAllowed` already returned true for it.
        case .unmetered: nil
        }
    }
}

/// Watches the link and tells ``SyncCoordinator`` when uploads may run.
///
/// Before this existed the app learned it was on cellular only by *failing*: with Wi‑Fi Only
/// on, `applyNetworkPolicy()` refused the request and URLSession reported -1009, which the
/// sync log rendered as a red "Failed to upload …: The Internet connection appears to be
/// offline". Three of those per asset then tripped the export give-up rule, so a working phone
/// on 5G filled its log with errors about a setting the user had chosen on purpose.
///
/// - Note: `@unchecked Sendable` — ``link`` is main-queue only for SwiftUI, ``storedLink`` is
///   behind ``lock``, and ``onChange`` is written once at start-up before the monitor runs.
final class NetworkMonitor: ObservableObject, @unchecked Sendable {
    static let shared = NetworkMonitor()

    /// For SwiftUI. **Main queue only** — off it, ask ``currentLink``. `nil` until the first
    /// path update lands.
    @Published private(set) var link: UploadLink?

    private let lock = NSLock()
    private var storedLink: UploadLink?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.oglimmer.photosync.network", qos: .utility)
    /// Guarded by ``lock`` — `start()` is called from `SyncCoordinator.start()`, which runs on
    /// whichever queue the app launched it from.
    private var started = false

    /// Called on ``monitorQueue`` when, and only when, the link actually changes. Set once,
    /// before ``start()``.
    var onChange: (@Sendable (UploadLink) -> Void)?

    /// `initialLink` is injectable purely so tests can state a link instead of standing up a
    /// radio — the same rationale as ``Settings/init(defaults:)``. Production uses ``shared``.
    init(initialLink: UploadLink? = nil) {
        storedLink = initialLink
        link = initialLink
    }

    /// The link as it stood a moment ago. Safe from any thread. `nil` means "not measured yet".
    var currentLink: UploadLink? {
        lock.lock()
        defer { lock.unlock() }
        return storedLink
    }

    /// Fails **open**: with no reading yet, uploads go ahead and find out for themselves. A
    /// gate that defaults to "blocked" would turn one broken monitor into an app that silently
    /// never backs anything up, which is far worse than the log noise it replaces.
    func uploadsAllowed(wifiOnly: Bool) -> Bool {
        guard let link = currentLink else { return true }
        return UploadNetworkPolicy.uploadsAllowed(link: link, wifiOnly: wifiOnly)
    }

    /// Why uploads are held back, or `nil` if they are not.
    func pause(wifiOnly: Bool) -> UploadPause? {
        guard let link = currentLink else { return nil }
        return UploadNetworkPolicy.pause(link: link, wifiOnly: wifiOnly)
    }

    /// Idempotent: `SyncCoordinator.start()` runs again on every foreground, and starting a
    /// second `NWPathMonitor` would leak the first.
    func start() {
        lock.lock()
        let alreadyStarted = started
        started = true
        lock.unlock()
        guard !alreadyStarted else { return }

        monitor.pathUpdateHandler = { [weak self] path in
            self?.update(UploadLink(
                satisfied: path.status == .satisfied,
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained,
            ))
        }
        monitor.start(queue: monitorQueue)
    }

    /// Records a new link and, if it differs from the last one, notifies. Called by the path
    /// handler, and directly by tests.
    func update(_ newLink: UploadLink) {
        lock.lock()
        let changed = storedLink != newLink
        storedLink = newLink
        lock.unlock()
        guard changed else { return }

        AppLog.sync.info("Network link is now \(newLink.rawValue, privacy: .public)")
        DispatchQueue.main.async { self.link = newLink }
        onChange?(newLink)
    }
}
