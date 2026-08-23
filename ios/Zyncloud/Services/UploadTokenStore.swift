import Foundation

/// Holds the scoped upload token the TUS path authenticates with (§5.9).
///
/// TUS uploads carry their credentials inside `Upload-Metadata`, because tusd forwards no
/// arbitrary headers to its hooks. That value used to be the account's `email:password`, and
/// tusd writes the metadata of every in-progress upload to a `.info` object in storage — so the
/// real password was being persisted to a place with a different lifetime and a different backup
/// story from the Keychain. A token does not fix the channel; it fixes what travels through it:
/// it authorises starting an upload and nothing else, it expires on its own, and throwing it away
/// costs the user nothing.
///
/// In memory only, deliberately. It is cheap to re-fetch, and a token on disk would be one more
/// copy of a credential lying around — which is the problem this exists to reduce.
final class UploadTokenStore {
    static let shared = UploadTokenStore()

    /// Refresh this long before the token actually lapses.
    ///
    /// A batch of uploads picks up a token and then spends minutes on the wire; renewing only at
    /// the moment of expiry would hand out a token that dies mid-batch.
    static let refreshMargin: TimeInterval = 300

    private let lock = NSLock()
    private var token: String?
    private var expiresAt: Date?
    /// Callers waiting on a fetch that is already in flight. Three uploads run concurrently and
    /// all three start at once; without this they would mint three tokens for one batch.
    private var waiters: [(String?) -> Void] = []
    private var fetching = false

    private init() {
        // A sign-out must not leave a working upload credential behind, and a sign-in as somebody
        // else must not keep uploading into the previous account.
        NotificationCenter.default.addObserver(
            forName: KeychainHelper.credentialsDidChange, object: nil, queue: nil,
        ) { [weak self] _ in
            self?.invalidate()
        }
    }

    /// Whether a cached token is unusable for a request starting now.
    ///
    /// Pure and static so the expiry rule can be tested without a network or a clock.
    static func needsRefresh(token: String?, expiresAt: Date?, now: Date,
                             margin: TimeInterval = refreshMargin) -> Bool
    {
        guard token != nil, let expiresAt else { return true }
        return expiresAt.timeIntervalSince(now) <= margin
    }

    /// Yields a usable token, fetching one if needed.
    ///
    /// Completes with nil when the server has no token endpoint or the request fails. That is not
    /// an error the caller should surface — it means "fall back to the legacy credential path",
    /// which is what an older server still expects.
    func token(api: APIClient, completion: @escaping (String?) -> Void) {
        lock.lock()
        if !UploadTokenStore.needsRefresh(token: token, expiresAt: expiresAt, now: Date()) {
            let cached = token
            lock.unlock()
            completion(cached)
            return
        }
        waiters.append(completion)
        if fetching {
            lock.unlock()
            return
        }
        fetching = true
        lock.unlock()

        api.fetchUploadToken { [weak self] result in
            guard let self else {
                completion(nil)
                return
            }
            lock.lock()
            switch result {
            case let .success(issued):
                token = issued.token
                expiresAt = Date().addingTimeInterval(issued.expiresInSeconds)
            case let .failure(error):
                token = nil
                expiresAt = nil
                print("UploadTokenStore: could not get an upload token (\(error.localizedDescription)); falling back to credentials")
            }
            let answer = token
            let pending = waiters
            waiters.removeAll()
            fetching = false
            lock.unlock()

            for waiter in pending { waiter(answer) }
        }
    }

    /// Drops the cached token. Called on a 401 from the upload create — the server changed its
    /// mind about this token (expired early, revoked by a password change) and the next attempt
    /// must mint a new one rather than replay the dead one.
    func invalidate() {
        lock.lock()
        token = nil
        expiresAt = nil
        lock.unlock()
    }
}

/// `POST /api/upload-tokens`.
///
/// `expiresInSeconds` rather than the absolute timestamp: a phone with a skewed clock would
/// compare the server's instant against its own idea of now and refresh at the wrong moment, or
/// never. A duration is immune to that.
struct UploadTokenResponse: Decodable {
    let token: String
    let expiresInSeconds: TimeInterval
}
