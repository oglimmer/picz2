import Foundation

/// Hands out the ``APIClient`` for whoever is signed in.
///
/// Six view models, the sync coordinator and the TUS uploader each used to do this themselves:
/// read the keychain, build a client, hold on to it. That meant nine copies of the same four
/// lines, nine chances for one of them to keep a stale client after a sign-out — and no seam at
/// all for a test, because the client was built inside the view model's `init` where nothing
/// could reach it.
///
/// Two ways to ask, because the callers genuinely want different things:
///
/// * ``current`` is nil when nobody is signed in. Screens want that — they can say "please sign
///   in" instead of firing a request that is certain to come back 401.
/// * ``clientOrAnonymous`` always answers. Background upload paths want that: they run without a
///   screen to put a message on, and a 401 they can log is more useful than a silent no-op.
/// - Note: `@unchecked Sendable` — every access to the one piece of mutable state, ``cached``,
///   goes through ``lock``. The compiler cannot see that, so it is asserted here.
final class APIClientProvider: @unchecked Sendable {
    static let shared = APIClientProvider()

    /// The keychain read is a synchronous call into `securityd`, and the upload path asks for a
    /// client several times per photo, so the answer is cached.
    ///
    /// Locked because callers are on three different threads: view models on the main queue,
    /// the coordinator on its own sync queue, the uploaders on URLSession callback threads.
    private let lock = NSLock()
    private var cached: APIClient?
    private var observer: NSObjectProtocol?

    private init() {
        // The cache is only safe because of this: sign-in, sign-out and the legacy-format
        // migration all post `credentialsDidChange`, so a signed-out session cannot go on
        // holding an authenticated client.
        observer = NotificationCenter.default.addObserver(
            forName: KeychainHelper.credentialsDidChange, object: nil, queue: nil,
        ) { [weak self] _ in
            self?.invalidate()
        }
    }

    /// The client for the stored credentials, or nil when there are none.
    var current: APIClient? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        guard let credentials = KeychainHelper.shared.load() else { return nil }
        let client = APIClient(username: credentials.username, password: credentials.password)
        cached = client
        return client
    }

    /// A client either way — unauthenticated when nobody is signed in.
    var clientOrAnonymous: APIClient {
        current ?? APIClient()
    }

    /// Drops the cached client. Called for you when the stored credentials change; exposed so a
    /// test that writes to the keychain directly can force the next read to go and look.
    func invalidate() {
        lock.lock()
        cached = nil
        lock.unlock()
    }
}
