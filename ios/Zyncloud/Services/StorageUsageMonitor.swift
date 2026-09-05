import Combine
import Foundation
import os

/// Keeps the answer to one question current: is the account's storage on the site full right now?
///
/// The persistent banner in ``RootView`` reads ``isFull``. It has no close button on purpose, so
/// this is the only thing that takes it down — by asking the server again and being told there is
/// room. Three things trigger a re-ask: the app coming to the foreground, a timer while it is
/// there, and the events that move the meter (an upload finishing, a photo being deleted, a 507).
///
/// The server decides `full`. A network failure keeps the last answer: a blip must not take a true
/// warning down, and an unknown state must not put one up.
@MainActor
final class StorageUsageMonitor: ObservableObject {
    static let shared = StorageUsageMonitor()

    /// How the monitor asks. Injected so a test can answer without a server; the default goes
    /// through the signed-in account's client.
    typealias Fetch = @Sendable (@escaping @Sendable (Result<StorageUsage, Error>) -> Void) -> Void

    @Published private(set) var usage: StorageUsage?

    /// True exactly while uploads to albums on the site's own storage are refused.
    var isFull: Bool {
        usage?.full == true
    }

    /// Long enough not to matter on the server, short enough that a quota raised with SQL, or
    /// space freed from the web app, is noticed while the phone sits on the album screen.
    static let pollInterval: TimeInterval = 60

    private let fetch: Fetch
    /// Uploads arrive in bursts; one re-ask per burst is plenty.
    private let coalesceDelay: TimeInterval
    private var timer: Timer?
    private var pendingRefresh: Task<Void, Never>?
    private var inflight = false

    /// - Parameters:
    ///   - fetch: how to reach `GET /api/storage-usage`. The default reads the client lazily on
    ///     every call, because the signed-in account can change under a long-lived singleton.
    ///   - coalesceDelay: how long ``refreshSoon()`` waits for more events before asking once.
    init(
        fetch: @escaping Fetch = { completion in
            guard let client = APIClientProvider.shared.current else {
                completion(.failure(AppError.api(message: "Not signed in", statusCode: nil)))
                return
            }
            client.fetchStorageUsage(completion: completion)
        },
        coalesceDelay: TimeInterval = 2,
    ) {
        self.fetch = fetch
        self.coalesceDelay = coalesceDelay
    }

    // MARK: - Lifecycle

    /// Begin watching: ask now and keep asking while the app is in the foreground.
    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    /// Stop watching and forget the answer. Called on sign-out: the next account is a different
    /// question, and a banner left over from the last one would be a lie.
    func stop() {
        timer?.invalidate()
        timer = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
        usage = nil
    }

    // MARK: - Asking

    /// Ask the server now, without waiting for the answer.
    func refresh() {
        Task { await refreshNow() }
    }

    /// Ask the server and apply the answer. Overlapping calls collapse into the one in flight.
    func refreshNow() async {
        guard !inflight else { return }
        inflight = true
        defer { inflight = false }

        let result: Result<StorageUsage, Error> = await withCheckedContinuation { continuation in
            fetch { continuation.resume(returning: $0) }
        }
        switch result {
        case let .success(usage):
            self.usage = usage
        case let .failure(error):
            // Keep whatever we knew. See the type comment.
            AppLog.api.warning("Storage usage fetch failed: \(error.localizedDescription)")
        }
    }

    /// Ask soon, once, however many times this is called in the next couple of seconds.
    func refreshSoon() {
        guard pendingRefresh == nil else { return }
        pendingRefresh = Task { @MainActor [weak self, coalesceDelay] in
            try? await Task.sleep(for: .seconds(coalesceDelay))
            guard let self, !Task.isCancelled else { return }
            self.pendingRefresh = nil
            await self.refreshNow()
        }
    }

    /// An uploader was just refused with 507. The banner goes up immediately on that evidence,
    /// and the real numbers follow from the next answer — the user should not have to wait a
    /// poll interval to learn why their photos stopped arriving.
    func noteStorageFull() {
        if usage?.full != true {
            usage = .assumedFull
        }
        refreshSoon()
    }

    // MARK: - Cross-thread entry points

    /// The uploaders finish on URLSession callback threads; these hop to the main actor for them.
    nonisolated static func reportStorageFull() {
        Task { @MainActor in shared.noteStorageFull() }
    }

    nonisolated static func reportUsageChanged() {
        Task { @MainActor in shared.refreshSoon() }
    }
}
