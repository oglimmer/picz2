import Foundation

class UploadService: NSObject {
    static let shared = UploadService()

    private var email: String?
    private var password: String?

    /// Scoped upload token for the TUS metadata (§5.9), fetched once per share and kept only in
    /// memory. The extension's lifetime is one share sheet, so there is nothing to expire here —
    /// the point is simply that the account password no longer travels in `Upload-Metadata`,
    /// which tusd writes to a `.info` object in storage for the life of the upload.
    private var uploadToken: String?

    /// Byte-level progress for the share currently in flight, plus the closure to report it to.
    /// Written when a share starts, read on ``uploadSession``'s delegate queue — hence the lock.
    private let progressLock = NSLock()
    private var progressTracker: ShareUploadProgress?
    private var progressHandler: ((Double) -> Void)?
    /// Last value handed to ``progressHandler``, in per-mille. `didSendBodyData` fires once per
    /// socket write — thousands of times for a video — so we only forward visible changes.
    private var lastReportedPerMille = -1

    /// The PATCH session. It cannot be `URLSession.shared`: a shared session has no delegate, so
    /// `didSendBodyData` is never delivered and the progress bar can only move once per file.
    private lazy var uploadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "UploadService.progress"
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

    override private init() { super.init() }

    /// Base URL for the JSON API surface (auth, albums). Distinct from the TUS upload
    /// endpoint, which lives under /files/ and is reached via ``AppConfiguration/tusEndpointURL``.
    func getApiBaseUrl() -> String {
        AppConfiguration.apiBaseURL.appendingPathComponent("api").absoluteString
    }

    func setCredentials(email: String, password: String) {
        self.email = email
        self.password = password
    }

    func clearCredentials() {
        email = nil
        password = nil
        uploadToken = nil
    }

    func getAuthorizationHeader() -> String? {
        guard let email, let password else { return nil }
        let creds = "\(email):\(password)"
        guard let data = creds.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    /// Verify credentials via /auth/check
    func checkAuth(completion: @escaping (Result<String, Error>) -> Void) {
        let urlString = getApiBaseUrl() + "/auth/check"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "UploadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid auth URL"])))
            return
        }
        var request = URLRequest(url: url)
        if let auth = getAuthorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "UploadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])))
                return
            }
            guard 200 ... 299 ~= http.statusCode, let data else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(.failure(NSError(domain: "UploadService", code: code, userInfo: [NSLocalizedDescriptionKey: "Auth failed"])))
                return
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let email = obj["email"] as? String {
                completion(.success(email))
            } else {
                completion(.success(""))
            }
        }.resume()
    }

    /// Upload media items via TUS, sequentially, reporting per-file progress.
    /// The legacy `auth` metadata value — the account's own `email:password`.
    private var legacyAuthValue: String? {
        guard let email, let password else { return nil }
        return "\(email):\(password)"
    }

    /// Mints a scoped upload token, if the server offers them.
    ///
    /// Failure is not an error: an older server has no such endpoint, and the upload proceeds on
    /// the legacy credential value instead.
    private func fetchUploadToken(completion: @escaping () -> Void) {
        guard let url = URL(string: getApiBaseUrl() + "/upload-tokens"),
              let authorization = getAuthorizationHeader()
        else {
            completion()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            defer { completion() }
            guard let self,
                  let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
                  let data,
                  let decoded = try? JSONDecoder().decode(ShareUploadTokenResponse.self, from: data)
            else { return }
            uploadToken = decoded.token
        }.resume()
    }

    func upload(
        mediaItems: [MediaItem],
        albumId: Int? = nil,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Int, Error>) -> Void,
    ) {
        // One token for the whole share, minted before the first byte moves.
        fetchUploadToken { [weak self] in
            self?.performUpload(mediaItems: mediaItems, albumId: albumId,
                               progress: progress, completion: completion)
        }
    }

    private func performUpload(
        mediaItems: [MediaItem],
        albumId: Int?,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        var uploadedCount = 0
        var failedError: Error?

        // Sizes are read once, up front: they are both the `Upload-Length` header and the weights
        // the progress bar is drawn from. A share of one 200 MB video and one 2 MB photo must not
        // pretend the photo is half the work.
        let sizes = mediaItems.map { Self.fileSize(of: $0.url) }
        beginProgress(fileSizes: sizes.map { (try? $0.get()) ?? 0 }, handler: progress)

        func uploadNext(index: Int) {
            guard index < mediaItems.count else {
                endProgress()
                DispatchQueue.main.async {
                    if let error = failedError {
                        completion(.failure(error))
                    } else {
                        completion(.success(uploadedCount))
                    }
                }
                return
            }

            let item = mediaItems[index]

            func advance(_ result: Result<Void, Error>) {
                switch result {
                case .success: uploadedCount += 1
                case let .failure(error): if failedError == nil { failedError = error }
                }
                // Both outcomes retire this file's weight, so a failed item does not park the bar.
                finishProgressItem()
                uploadNext(index: index + 1)
            }

            switch sizes[index] {
            case let .success(fileSize):
                uploadFile(item: item, albumId: albumId, fileSize: fileSize, completion: advance)
            case let .failure(error):
                advance(.failure(error))
            }
        }

        uploadNext(index: 0)
    }

    private static func fileSize(of url: URL) -> Result<Int64, Error> {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return .success((attrs[.size] as? NSNumber)?.int64Value ?? 0)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Progress plumbing

    private func beginProgress(fileSizes: [Int64], handler: @escaping (Double) -> Void) {
        progressLock.lock()
        progressTracker = ShareUploadProgress(fileSizes: fileSizes)
        progressHandler = handler
        lastReportedPerMille = -1
        progressLock.unlock()
    }

    private func endProgress() {
        progressLock.lock()
        progressTracker = nil
        progressHandler = nil
        progressLock.unlock()
    }

    /// Called from `didSendBodyData` with the running total for the file in flight.
    fileprivate func noteBytesSent(_ totalBytesSentForCurrentFile: Int64) {
        emitProgress { $0.noteBytesSent(totalBytesSentForCurrentFile) }
    }

    private func finishProgressItem() {
        emitProgress { $0.finishCurrentItem() }
    }

    private func emitProgress(_ mutate: (inout ShareUploadProgress) -> Void) {
        progressLock.lock()
        guard var tracker = progressTracker, let handler = progressHandler else {
            progressLock.unlock()
            return
        }
        mutate(&tracker)
        progressTracker = tracker
        let fraction = tracker.fraction
        let perMille = Int(fraction * 1000)
        guard perMille != lastReportedPerMille else {
            progressLock.unlock()
            return
        }
        lastReportedPerMille = perMille
        progressLock.unlock()

        DispatchQueue.main.async { handler(fraction) }
    }

    private func uploadFile(
        item: MediaItem,
        albumId: Int?,
        fileSize: Int64,
        completion: @escaping (Result<Void, Error>) -> Void,
    ) {
        // Auth via Upload-Metadata is required by the server (D26) — Authorization header is
        // sent too as belt-and-braces, but tusd does not forward arbitrary headers to hooks.
        guard email != nil, password != nil else {
            completion(.failure(NSError(domain: "UploadService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])))
            return
        }

        let tusURL = AppConfiguration.tusEndpointURL
        var request = URLRequest(url: tusURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(fileSize), forHTTPHeaderField: "Upload-Length")
        request.setValue(buildUploadMetadata(item: item, albumId: albumId), forHTTPHeaderField: "Upload-Metadata")
        if let auth = getAuthorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        print("📤 Creating TUS upload: \(item.filename) (\(fileSize) bytes)")
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            if let error {
                print("❌ TUS create failed: \(item.filename) - \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "UploadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])))
                return
            }
            switch http.statusCode {
            case 200, 201:
                guard let location = http.value(forHTTPHeaderField: "Location"),
                      let uploadURL = self.resolveLocation(location, against: tusURL)
                else {
                    completion(.failure(NSError(domain: "UploadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Location header"])))
                    return
                }
                self.patchUpload(item: item, uploadURL: uploadURL, completion: completion)
            case 401, 403:
                completion(.failure(NSError(domain: "UploadService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Authentication failed"])))
            case 429, 503:
                let retry = http.value(forHTTPHeaderField: "Retry-After") ?? "?"
                completion(.failure(NSError(domain: "UploadService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server busy (retry after \(retry)s)"])))
            default:
                let body = "POST /files/ returned \(http.statusCode)"
                completion(.failure(NSError(domain: "UploadService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])))
            }
        }.resume()
    }

    private func patchUpload(
        item: MediaItem,
        uploadURL: URL,
        completion: @escaping (Result<Void, Error>) -> Void,
    ) {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 600
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue("0", forHTTPHeaderField: "Upload-Offset")
        request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
        if let auth = getAuthorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        // `uploadSession`, not `URLSession.shared` — see the property comment. The completion
        // handler still stands in for `didCompleteWithError`; `didSendBodyData` is delivered
        // alongside it, and that is where the bar gets its numbers.
        let task = uploadSession.uploadTask(with: request, fromFile: item.url) { _, response, error in
            if let error {
                print("❌ TUS PATCH failed: \(item.filename) - \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse {
                if 200 ... 299 ~= http.statusCode {
                    print("✅ Upload successful: \(item.filename)")
                    completion(.success(()))
                } else {
                    let msg = "PATCH returned \(http.statusCode)"
                    print("❌ TUS PATCH failed: \(item.filename) - \(msg)")
                    completion(.failure(NSError(domain: "UploadService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])))
                }
            } else {
                completion(.failure(NSError(domain: "UploadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])))
            }
        }
        task.resume()
    }

    /// Build the TUS Upload-Metadata header. Each value is base64-encoded per the spec.
    /// We omit ``contentId`` deliberately: a user re-sharing the same photo through the share
    /// sheet expects a new asset (matching the legacy multipart endpoint), not a 409 dedupe.
    private func buildUploadMetadata(item: MediaItem, albumId: Int?) -> String {
        var parts: [(String, String)] = [
            ("filename", item.filename),
            ("filetype", contentType(for: item)),
        ]
        if let albumId {
            parts.append(("albumId", String(albumId)))
        }
        // Prefer the scoped token; fall back to the account credentials only when the server
        // has no token endpoint (§5.9).
        if let auth = uploadToken ?? legacyAuthValue {
            parts.append(("auth", auth))
        }
        return parts
            .map { key, value in
                let b64 = Data(value.utf8).base64EncodedString()
                return "\(key) \(b64)"
            }
            .joined(separator: ",")
    }

    private func contentType(for item: MediaItem) -> String {
        let ext = item.url.pathExtension.lowercased()
        return item.type == .image ? "image/\(ext)" : "video/\(ext)"
    }

    private func resolveLocation(_ location: String, against base: URL) -> URL? {
        if let abs = URL(string: location), abs.scheme != nil { return abs }
        return URL(string: location, relativeTo: base)?.absoluteURL
    }
}

// MARK: - URLSessionTaskDelegate

extension UploadService: URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didSendBodyData _: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend _: Int64
    ) {
        // Uploads run strictly one at a time (`uploadNext`), so the task firing here is always
        // the file the tracker considers current — no task-to-item bookkeeping is needed.
        noteBytesSent(totalBytesSent)
    }
}

/// Byte-weighted progress across the files of one share.
///
/// Split out from ``UploadService`` because it is the part with the arithmetic worth testing:
/// weighting, clamping, and the rule that a file leaving the queue always retires its weight.
struct ShareUploadProgress {
    /// Bytes per file, in upload order. A zero-byte or unmeasurable file still gets weight 1 so
    /// it can move the bar when it finishes, rather than being invisible.
    private let weights: [Int64]
    private let totalBytes: Int64
    private var completedIndex = 0
    private var completedBytes: Int64 = 0
    private var currentSent: Int64 = 0

    init(fileSizes: [Int64]) {
        weights = fileSizes.map { max(1, $0) }
        totalBytes = weights.reduce(0, +)
    }

    /// 0.0 … 1.0. Empty shares read as 0 — there is nothing to wait for, but claiming "done"
    /// before the completion handler runs would be a lie.
    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        let sent = completedBytes + min(currentSent, currentWeight)
        return min(1.0, Double(sent) / Double(totalBytes))
    }

    private var currentWeight: Int64 {
        completedIndex < weights.count ? weights[completedIndex] : 0
    }

    /// `totalBytesSent` for the file in flight — an absolute count, not a delta. A retried body
    /// restarts that count from zero; we keep the high-water mark so the bar never walks backwards.
    mutating func noteBytesSent(_ totalForCurrentFile: Int64) {
        currentSent = max(currentSent, totalForCurrentFile)
    }

    /// The current file is done — uploaded, or failed and given up on. Either way its whole
    /// weight is now behind us, so the bar lands exactly on the file boundary.
    mutating func finishCurrentItem() {
        guard completedIndex < weights.count else { return }
        completedBytes += weights[completedIndex]
        completedIndex += 1
        currentSent = 0
    }
}

/// `POST /api/upload-tokens`. Only the token is read here — the extension lives for one share,
/// so it never needs to reason about expiry.
private struct ShareUploadTokenResponse: Decodable {
    let token: String
}

// MediaItem struct for type safety
struct MediaItem {
    let url: URL
    let type: MediaType
    let filename: String

    enum MediaType {
        case image
        case video
    }
}
