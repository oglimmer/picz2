import Foundation
import os

/// - Note: `@unchecked Sendable` — the extension is one process serving one share sheet, so the
///   credential fields are written once at start-up and only read afterwards. Everything that is
///   genuinely touched from the session's delegate queue sits behind ``progressLock``.
final class UploadService: NSObject, @unchecked Sendable {
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
    private var progressHandler: (@Sendable (Double) -> Void)?
    /// Last value handed to ``progressHandler``, in per-mille. `didSendBodyData` fires once per
    /// socket write — thousands of times for a video — so we only forward visible changes.
    private var lastReportedPerMille = -1
    /// Bytes already accepted by the server for the file in flight, so a chunked PATCH reports
    /// `offset + bytesSent` rather than walking the bar backwards to 0 at every chunk.
    private var currentFileOffset: Int64 = 0

    /// Files that already landed in this share sheet. A mixed batch used to report total
    /// failure and a retry re-POSTed them without `contentId`, which duplicated them.
    private var succeededURLs = Set<URL>()
    /// The exact file set of the batch ``succeededURLs`` belongs to. A retry re-sends the very
    /// same items; anything else is a new share and must not inherit the skip list. Comparing
    /// for *disjointness* was not enough — a partly overlapping share would mark the shared
    /// files uploaded without sending a byte.
    private var currentBatchURLs = Set<URL>()

    /// How many times one file may re-HEAD and continue after a failed chunk. Spent per stall,
    /// refilled whenever the server's offset advances.
    private static let maxPatchAttempts = 3

    /// The share sheet went away mid-upload. Reported rather than dropped: a swallowed
    /// completion parks the batch forever with a spinner and no message.
    private static let cancelledError = AppError.cancelled("Upload cancelled")

    /// Where chunks are cut, never the session's delegate queue.
    private let sliceQueue = DispatchQueue(label: "com.oglimmer.zyncloud.share.slice", qos: .utility)

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
    func checkAuth(completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        let urlString = getApiBaseUrl() + "/auth/check"
        guard let url = URL(string: urlString) else {
            completion(.failure(AppError.api(message: "Could not build the sign-in web address", statusCode: nil)))
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
                completion(.failure(AppError.api(message: "Invalid response", statusCode: nil)))
                return
            }
            guard 200 ... 299 ~= http.statusCode, let data else {
                completion(.failure(AppError.authentication("Your email or password was not accepted.")))
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
    private func fetchUploadToken(completion: @escaping @Sendable () -> Void) {
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
        progress: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (ShareUploadOutcome) -> Void,
    ) {
        let incoming = Set(mediaItems.map(\.url))
        if !ShareRetryBatch.isRetry(of: currentBatchURLs, incoming: incoming) {
            succeededURLs.removeAll()
            currentBatchURLs = incoming
        }
        // One token for the whole share, minted before the first byte moves.
        fetchUploadToken { [weak self] in
            // Resolved once here rather than written `self?` twice: `weak self` is a variable,
            // and reading it again from the inner closure — which runs on a different thread —
            // is the race the compiler flags.
            guard let self else { return }
            self.fetchMaxUploadBytes { limit in
                self.performUpload(
                    mediaItems: mediaItems, albumId: albumId, maxUploadBytes: limit,
                    progress: progress, completion: completion,
                )
            }
        }
    }

    /// Unauthenticated; the same `/api/capabilities` the main app uses. Failure is not an
    /// error — we let the server be the judge, matching ``UploadSizeLimit/check``.
    private func fetchMaxUploadBytes(completion: @escaping @Sendable (Int64?) -> Void) {
        let url = AppConfiguration.apiBaseURL.appendingPathComponent("api/capabilities")
        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
                  let data,
                  let decoded = try? JSONDecoder().decode(ShareCapabilitiesResponse.self, from: data)
            else {
                completion(nil)
                return
            }
            completion(decoded.tus.maxSize)
        }.resume()
    }

    private func performUpload(
        mediaItems: [MediaItem],
        albumId: Int?,
        maxUploadBytes: Int64?,
        progress: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (ShareUploadOutcome) -> Void
    ) {
        // A box rather than three local `var`s. The upload chain is strictly sequential — each
        // file's completion is what starts the next — but every link runs on a different
        // URLSession callback thread, so the compiler sees three variables being read and written
        // from concurrently-executing closures and cannot tell that they never overlap.
        let tally = BatchTally()

        // Sizes are read once, up front: they are both the `Upload-Length` header and the weights
        // the progress bar is drawn from. A share of one 200 MB video and one 2 MB photo must not
        // pretend the photo is half the work.
        let sizes = mediaItems.map { Self.fileSize(of: $0.url) }
        beginProgress(fileSizes: sizes.map { (try? $0.get()) ?? 0 }, handler: progress)

        @Sendable func uploadNext(index: Int) {
            guard index < mediaItems.count else {
                endProgress()
                let outcome = tally.outcome
                DispatchQueue.main.async {
                    completion(outcome)
                }
                return
            }

            let item = mediaItems[index]

            @Sendable func advance(_ result: Result<Void, Error>) {
                switch result {
                case .success:
                    tally.noteUploaded()
                    self.succeededURLs.insert(item.url)
                case let .failure(error):
                    tally.noteFailed(error)
                }
                // Both outcomes retire this file's weight, so a failed item does not park the bar.
                finishProgressItem()
                uploadNext(index: index + 1)
            }

            if succeededURLs.contains(item.url) {
                advance(.success(()))
                return
            }

            switch sizes[index] {
            case let .success(fileSize):
                if case let .tooLarge(size, limit) = UploadSizeLimit.check(
                    size: fileSize, limit: maxUploadBytes,
                ) {
                    let message = UploadSizeLimit.message(
                        filename: item.filename, size: size, limit: limit,
                    )
                    advance(.failure(AppError.api(message: message, statusCode: 413)))
                    return
                }
                uploadFile(
                    item: item, albumId: albumId, fileSize: fileSize,
                    maxUploadBytes: maxUploadBytes, completion: advance,
                )
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

    private func beginProgress(fileSizes: [Int64], handler: @escaping @Sendable (Double) -> Void) {
        progressLock.lock()
        progressTracker = ShareUploadProgress(fileSizes: fileSizes)
        progressHandler = handler
        lastReportedPerMille = -1
        currentFileOffset = 0
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
        progressLock.lock()
        currentFileOffset = 0
        progressLock.unlock()
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
        maxUploadBytes: Int64?,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void,
    ) {
        // Auth via Upload-Metadata is required by the server (D26) — Authorization header is
        // sent too as belt-and-braces, but tusd does not forward arbitrary headers to hooks.
        guard email != nil, password != nil else {
            completion(.failure(AppError.authentication("Not signed in")))
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

        AppLog.upload.info("Creating a TUS upload: \(item.filename) (\(fileSize, privacy: .public) bytes)")
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            if let error {
                AppLog.upload.error("TUS create failed for \(item.filename): \(error.localizedDescription, privacy: .public)")
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(AppError.api(message: "Invalid response", statusCode: nil)))
                return
            }
            switch http.statusCode {
            case 200, 201:
                guard let location = http.value(forHTTPHeaderField: "Location"),
                      let uploadURL = self.resolveLocation(location, against: tusURL)
                else {
                    completion(.failure(AppError.api(message: "The server did not say where to send the file.", statusCode: nil)))
                    return
                }
                // A freshly created TUS resource is empty, so the offset is 0 and a HEAD here
                // would only cost a round-trip. HEAD is the *resume* path.
                self.patchFromOffset(
                    item: item, uploadURL: uploadURL, fileSize: fileSize, offset: 0,
                    attemptsLeft: Self.maxPatchAttempts, completion: completion,
                )
            case 401, 403:
                completion(.failure(AppError.authentication("Your email or password was not accepted.")))
            case 413:
                let message = UploadSizeLimit.message(
                    filename: item.filename, size: fileSize, limit: maxUploadBytes,
                )
                completion(.failure(AppError.api(message: message, statusCode: 413)))
            case 429, 503:
                let retry = http.value(forHTTPHeaderField: "Retry-After") ?? "?"
                completion(.failure(AppError.api(message: "Server busy — try again in \(retry)s", statusCode: http.statusCode)))
            default:
                completion(.failure(AppError.api(message: "The server refused the upload.",
                                                 statusCode: http.statusCode)))
            }
        }.resume()
    }

    private func headAndPatch(
        item: MediaItem,
        uploadURL: URL,
        fileSize: Int64,
        attemptsLeft: Int = 3,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void,
    ) {
        guard attemptsLeft > 0 else {
            completion(.failure(AppError.api(message: "Upload stalled; try again", statusCode: nil)))
            return
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 30
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        if let auth = getAuthorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self else {
                completion(.failure(Self.cancelledError))
                return
            }
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(.failure(AppError.api(message: "Could not check how much had arrived.",
                                                 statusCode: code)))
                return
            }
            let offset = TusChunking.parseOffset(http.value(forHTTPHeaderField: "Upload-Offset")) ?? 0
            self.patchFromOffset(
                item: item, uploadURL: uploadURL, fileSize: fileSize, offset: offset,
                attemptsLeft: attemptsLeft,
                completion: completion,
            )
        }.resume()
    }

    private func patchFromOffset(
        item: MediaItem,
        uploadURL: URL,
        fileSize: Int64,
        offset: Int64,
        attemptsLeft: Int,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void,
    ) {
        guard let range = TusChunking.nextChunk(offset: offset, fileSize: fileSize) else {
            completion(.success(()))
            return
        }

        // Slicing copies up to a chunk of bytes, and this runs from the previous chunk's
        // completion handler — the session's delegate queue. Cut the file off it.
        sliceQueue.async { [weak self] in
            guard let self else {
                completion(.failure(Self.cancelledError))
                return
            }
            let chunkURL: URL
            let wholeFile = range.lowerBound == 0 && range.upperBound == fileSize
            if wholeFile {
                chunkURL = item.url
            } else {
                chunkURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("share-chunk-\(UUID().uuidString)")
                do {
                    try TusChunking.writeSlice(from: item.url, range: range, to: chunkURL)
                } catch {
                    completion(.failure(error))
                    return
                }
            }
            self.sendPatch(
                item: item, uploadURL: uploadURL, fileSize: fileSize, range: range,
                chunkURL: chunkURL, wholeFile: wholeFile, attemptsLeft: attemptsLeft,
                completion: completion,
            )
        }
    }

    /// Sends one prepared chunk. Split from ``patchFromOffset`` only so the slicing above can
    /// happen off the delegate queue.
    private func sendPatch(
        item: MediaItem,
        uploadURL: URL,
        fileSize: Int64,
        range: Range<Int64>,
        chunkURL: URL,
        wholeFile: Bool,
        attemptsLeft: Int,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void,
    ) {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 600
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(range.lowerBound), forHTTPHeaderField: "Upload-Offset")
        request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
        if let auth = getAuthorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        progressLock.lock()
        currentFileOffset = range.lowerBound
        progressLock.unlock()

        // `uploadSession`, not `URLSession.shared` — see the property comment. The completion
        // handler still stands in for `didCompleteWithError`; `didSendBodyData` is delivered
        // alongside it, and that is where the bar gets its numbers.
        let task = uploadSession.uploadTask(with: request, fromFile: chunkURL) { [weak self] _, response, error in
            if !wholeFile {
                try? FileManager.default.removeItem(at: chunkURL)
            }
            guard let self else {
                completion(.failure(Self.cancelledError))
                return
            }
            if let error {
                AppLog.upload.error("TUS PATCH failed for \(item.filename): \(error.localizedDescription, privacy: .public)")
                // The server may still have kept some of this chunk. HEAD and continue.
                self.headAndPatch(
                    item: item, uploadURL: uploadURL, fileSize: fileSize,
                    attemptsLeft: attemptsLeft - 1, completion: completion,
                )
                return
            }
            if let http = response as? HTTPURLResponse {
                if 200 ... 299 ~= http.statusCode {
                    let newOffset = TusChunking.parseOffset(http.value(forHTTPHeaderField: "Upload-Offset"))
                        ?? range.upperBound
                    if newOffset < fileSize {
                        if newOffset <= range.lowerBound {
                            self.headAndPatch(
                                item: item, uploadURL: uploadURL, fileSize: fileSize,
                                attemptsLeft: attemptsLeft - 1, completion: completion,
                            )
                            return
                        }
                        // Bytes landed, so earlier stalls are behind us. Without this refill the
                        // budget is a per-file lifetime cap and a long video dies on its third
                        // dropped chunk out of hundreds.
                        self.patchFromOffset(
                            item: item, uploadURL: uploadURL, fileSize: fileSize, offset: newOffset,
                            attemptsLeft: Self.maxPatchAttempts,
                            completion: completion,
                        )
                    } else {
                        AppLog.upload.info("Upload finished: \(item.filename)")
                        completion(.success(()))
                    }
                } else if http.statusCode == 409 {
                    self.headAndPatch(
                        item: item, uploadURL: uploadURL, fileSize: fileSize,
                        attemptsLeft: attemptsLeft - 1, completion: completion,
                    )
                } else {
                    let msg = "PATCH returned \(http.statusCode)"
                    AppLog.upload.error("TUS PATCH failed for \(item.filename): \(msg, privacy: .public)")
                    completion(.failure(AppError.api(message: msg, statusCode: http.statusCode)))
                }
            } else {
                completion(.failure(AppError.api(message: "Invalid response", statusCode: nil)))
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
        progressLock.lock()
        let offset = currentFileOffset
        progressLock.unlock()
        noteBytesSent(offset + totalBytesSent)
    }
}

/// Whether a second `uploadMediaItems` call is a retry of the batch before it, and may
/// therefore inherit the "already landed, do not re-send" set.
///
/// Only an identical file set counts. Checking merely for *overlap* — or, worse, for
/// disjointness — lets a partly overlapping share inherit the skip list, and the files it
/// shares with the previous batch are then reported as uploaded without a byte being sent.
enum ShareRetryBatch {
    static func isRetry(of previous: Set<URL>, incoming: Set<URL>) -> Bool {
        !previous.isEmpty && previous == incoming
    }
}

/// Result of one share-sheet upload pass. A mixed batch is a partial success, not a
/// total failure — retrying then skips files already in ``UploadService``'s succeeded set.
struct ShareUploadOutcome: Equatable {
    let uploaded: Int
    let failed: Int
    let lastErrorDescription: String?

    var allSucceeded: Bool { failed == 0 }

    var userMessage: String {
        if failed == 0 {
            return "Uploaded \(uploaded) item\(uploaded == 1 ? "" : "s")"
        }
        if uploaded == 0 {
            return lastErrorDescription.map { "Upload failed: \($0)" } ?? "Upload failed"
        }
        let suffix = lastErrorDescription.map { ": \($0)" } ?? ""
        return "Uploaded \(uploaded) of \(uploaded + failed). \(failed) failed\(suffix)"
    }
}

/// `GET /api/capabilities`. Only `tus.maxSize` is used here; the rest of the payload is the
/// main app's concern.
private struct ShareCapabilitiesResponse: Decodable {
    struct Tus: Decodable {
        let maxSize: Int64
    }

    let tus: Tus
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

/// The running result of one share: how many files landed, how many did not, and the first
/// reason one did not.
///
/// A class behind a lock rather than three `var`s in ``UploadService/performUpload``. The upload
/// chain hands control from one file's completion to the next, so no two links ever run at the
/// same time — but they run on different threads, and "never at the same time" is not something
/// the compiler can be shown. The lock costs nothing here and makes the claim true rather than
/// merely believed.
final class BatchTally: @unchecked Sendable {
    private let lock = NSLock()
    private var uploaded = 0
    private var failed = 0
    private var firstError: Error?

    func noteUploaded() {
        lock.lock()
        uploaded += 1
        lock.unlock()
    }

    /// Keeps the **first** error, not the last: it is the one that explains the run.
    func noteFailed(_ error: Error) {
        lock.lock()
        failed += 1
        if firstError == nil { firstError = error }
        lock.unlock()
    }

    var outcome: ShareUploadOutcome {
        lock.lock()
        defer { lock.unlock() }
        return ShareUploadOutcome(
            uploaded: uploaded,
            failed: failed,
            lastErrorDescription: firstError?.localizedDescription,
        )
    }
}
