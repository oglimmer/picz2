import Foundation
import Photos

/// Phase 5 — TUS resumable uploads. Drop-in alternative to ``Uploader`` selected at runtime by
/// ``SyncCoordinator`` based on ``Settings/useTus`` and the server-advertised capabilities
/// (``APIClient/fetchCapabilities``).
///
/// V1 scope (R2 prep):
///   * Foreground ``POST /files/`` to create the upload (small request, headers only).
///   * Background ``PATCH /files/{id}`` carrying the entire file from offset 0.
///   * Pre-create dedupe (HTTP 409) and backpressure (HTTP 503) surface as the same callback
///     outcomes the multipart ``Uploader`` already produces, so ``SyncCoordinator`` doesn't
///     need parallel handling logic.
///
/// V2 scope (intentionally deferred — needs Xcode + device verification):
///   * Cross-launch resume via ``HEAD /files/{id}`` to discover the server-side offset, then
///     PATCH from there using a sliced temp file. Today, an interrupted PATCH that's
///     resurrected after an app relaunch restarts from offset 0 (same as multipart). The big
///     resume win — recovering from a long network outage — already works automatically via
///     the background ``URLSession`` on the same task.
final class TusUploader: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    static let shared = TusUploader()

    let sessionId = "com.oglimmer.photosync.tus"
    private(set) var session: URLSession!
    private let fileManager = FileManager.default

    /// Mirrors ``Uploader/UploadOutcome`` so ``SyncCoordinator`` can route either uploader's
    /// completions through the same handler. Kept as a sibling enum (rather than a shared
    /// top-level type) to keep this scaffolding additive.
    enum UploadOutcome {
        case success(serverAssetId: Int?)
        case clientError
        case transport
        case backpressure(TimeInterval)
    }

    var onTaskFinished: ((String, UploadOutcome) -> Void)?
    var onAllBackgroundEventsComplete: ((String) -> Void)?

    override private init() { super.init() }

    /// Creates the background session, once. Call from the main thread.
    /// See ``Uploader/configureSession(with:)`` for why this is idempotent and why the
    /// Wi‑Fi Only setting is applied per request instead of on the configuration.
    func configureSession(with identifier: String? = nil) {
        let id = identifier ?? sessionId
        if let session, session.configuration.identifier == id { return }

        let config = URLSessionConfiguration.background(withIdentifier: id)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// Enumerates the assets that still have a live task in this background session.
    ///
    /// Asynchronous on purpose. `getAllTasks` answers on a background queue, and this used to
    /// bridge that with `DispatchSemaphore.wait(timeout: .now() + 2)` — on the main thread, and
    /// `SyncCoordinator.start()` called it for *both* uploaders on every activation, so the app
    /// could freeze for up to four seconds every time it came to the foreground. Two seconds is
    /// the timeout rather than the expected cost, but re-attaching to a background session after
    /// a relaunch is genuinely slow, and the launch screen is the worst place to spend it.
    func getActiveUploadAssetIds(completion: @escaping (Set<String>) -> Void) {
        guard let session else {
            completion([])
            return
        }
        session.getAllTasks { tasks in
            // taskDescription format: "assetId|fileURL|…"
            completion(Set(tasks.compactMap { $0.taskDescription?.components(separatedBy: "|").first }))
        }
    }

    /// - Parameter maxUploadBytes: the server's advertised `tus.maxSize`, or nil when
    ///   capabilities have not been fetched yet. Only used to refuse a file locally with a
    ///   readable reason instead of a 413 — never to relax anything the server enforces.
    func queueUpload(
        asset: PHAsset,
        api: APIClient,
        maxUploadBytes: Int64? = nil,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        UploadStore.shared.markAsUploading(asset.localIdentifier)
        Uploader.shared.exportAssetToTempFile(asset) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(error):
                UploadStore.shared.removeFromUploading(asset.localIdentifier)
                completion?(.failure(error))
            case let .success(exp):
                UploadStore.shared.storeChecksumMapping(checksum: exp.checksum, localId: asset.localIdentifier)
                self.createUpload(api: api, asset: asset, exp: exp,
                                  maxUploadBytes: maxUploadBytes, completion: completion)
            }
        }
    }

    private func createUpload(
        api: APIClient,
        asset: PHAsset,
        exp: Uploader.ExportResult,
        maxUploadBytes: Int64?,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        let tusURL = api.tusEndpointURL()
        let fileSize: Int64
        do {
            let attrs = try fileManager.attributesOfItem(atPath: exp.fileURL.path)
            fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            discardExport(exp)
            UploadStore.shared.removeFromUploading(asset.localIdentifier)
            completion?(.failure(error))
            return
        }

        // Refuse oversized files here rather than letting tusd do it. The server's answer is a
        // bare 413 with no numbers in it, and it arrives only after the whole asset has been
        // exported to disk — so checking the size we already computed costs nothing and is the
        // only way the user learns which file is missing and by how much (D43).
        if case let .tooLarge(size, limit) = UploadSizeLimit.check(size: fileSize, limit: maxUploadBytes) {
            refuseForSize(asset: asset, exp: exp, size: size, limit: limit, completion: completion)
            return
        }

        // Authenticate the upload with a scoped token rather than the account password (§5.9).
        // A nil token means the server has no token endpoint — an older deployment — and
        // `performCreate` falls back to the legacy credential value.
        UploadTokenStore.shared.token(api: api) { [weak self] token in
            self?.performCreate(api: api, asset: asset, exp: exp, fileSize: fileSize,
                                tusURL: tusURL, authValue: token, maxUploadBytes: maxUploadBytes,
                                mayRetryWithFreshToken: token != nil, completion: completion)
        }
    }

    /// Sends `POST /files/` and routes the answer. Split out of ``createUpload`` so a 401 can
    /// mint a new token and run exactly the same request again without recomputing the export.
    private func performCreate(
        api: APIClient,
        asset: PHAsset,
        exp: Uploader.ExportResult,
        fileSize: Int64,
        tusURL: URL,
        authValue: String?,
        maxUploadBytes: Int64?,
        mayRetryWithFreshToken: Bool,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        var request = URLRequest(url: tusURL)
        request.httpMethod = "POST"
        request.applyNetworkPolicy()
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(fileSize), forHTTPHeaderField: "Upload-Length")
        request.setValue(
            api.tusUploadMetadata(filename: exp.filename, mimeType: exp.mimeType,
                                  contentId: asset.localIdentifier, auth: authValue),
            forHTTPHeaderField: "Upload-Metadata"
        )
        api.addBasicAuth(to: &request)

        let assetId = asset.localIdentifier
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            if let error {
                self.discardExport(exp)
                SyncLogger.shared.logUploadFailure(assetId: assetId, error: error.localizedDescription)
                UploadStore.shared.removeFromUploading(assetId)
                completion?(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                self.discardExport(exp)
                SyncLogger.shared.logUploadFailure(assetId: assetId, error: "no response from server")
                UploadStore.shared.removeFromUploading(assetId)
                completion?(.failure(NSError(domain: "TusUploader", code: -1,
                                             userInfo: [NSLocalizedDescriptionKey: "no http response"])))
                return
            }
            switch http.statusCode {
            case 200, 201:
                guard let location = http.value(forHTTPHeaderField: "Location"),
                      let uploadURL = self.resolveLocation(location, against: tusURL)
                else {
                    self.discardExport(exp)
                    SyncLogger.shared.logUploadFailure(assetId: assetId, error: "missing Location header")
                    UploadStore.shared.removeFromUploading(assetId)
                    completion?(.failure(NSError(domain: "TusUploader", code: -1,
                                                 userInfo: [NSLocalizedDescriptionKey: "missing Location header"])))
                    return
                }
                self.startPatch(asset: asset, exp: exp, uploadURL: uploadURL, api: api, completion: completion)
            case 409:
                // Pre-create dedupe — server already has a row for this contentId. Treat as
                // success so SyncCoordinator stops retrying.
                self.discardExport(exp)
                SyncLogger.shared.logUploadDeduped(assetId: assetId)
                UploadStore.shared.markUploaded(assetId, checksum: exp.checksum)
                self.onTaskFinished?(assetId, .success(serverAssetId: nil))
                completion?(.success(()))
            case 401 where mayRetryWithFreshToken:
                // The token was refused — expired early, or revoked by a password change. Mint a
                // new one and run the same create again, once. Without this the asset would be
                // reported as a permanent client error and skipped until the next scan, for what
                // is really a routine credential rotation.
                UploadTokenStore.shared.invalidate()
                UploadTokenStore.shared.token(api: api) { [weak self] fresh in
                    guard let self else { return }
                    print("TusUploader: upload token refused, retrying with a fresh one")
                    self.performCreate(api: api, asset: asset, exp: exp, fileSize: fileSize,
                                       tusURL: tusURL, authValue: fresh,
                                       maxUploadBytes: maxUploadBytes,
                                       mayRetryWithFreshToken: false, completion: completion)
                }
            case 413:
                // The local check above did not catch it — capabilities were never fetched, or
                // the cap was lowered since. Same outcome, same message, limit left unstated
                // when we genuinely do not know it.
                self.refuseForSize(asset: asset, exp: exp, size: fileSize,
                                   limit: maxUploadBytes, completion: completion)
            case 429, 503:
                let retry = self.parseRetryAfter(from: http) ?? 30
                // Safe to delete: a deferred asset is re-queued and re-exported from the photo
                // library when its turn comes round again, not resumed from this file.
                self.discardExport(exp)
                SyncLogger.shared.logUploadDeferred(assetId: assetId, retryAfter: retry)
                UploadStore.shared.removeFromUploading(assetId)
                self.onTaskFinished?(assetId, .backpressure(retry))
                completion?(.success(()))
            default:
                self.discardExport(exp)
                SyncLogger.shared.logUploadFailure(assetId: assetId, error: "HTTP \(http.statusCode)")
                UploadStore.shared.removeFromUploading(assetId)
                self.onTaskFinished?(assetId, .clientError)
                completion?(.failure(NSError(domain: "TusUploader", code: http.statusCode,
                                             userInfo: [NSLocalizedDescriptionKey: "POST /files/ returned \(http.statusCode)"])))
            }
        }.resume()
    }

    private func startPatch(
        asset: PHAsset,
        exp: Uploader.ExportResult,
        uploadURL: URL,
        api: APIClient,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PATCH"
        request.applyNetworkPolicy()
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue("0", forHTTPHeaderField: "Upload-Offset")
        request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
        api.addBasicAuth(to: &request)

        let task = session.uploadTask(with: request, fromFile: exp.fileURL)
        task.taskDescription = [
            asset.localIdentifier,
            exp.fileURL.path,
            uploadURL.absoluteString,
            exp.checksum,
        ].joined(separator: "|")
        task.resume()
        completion?(.success(()))
    }

    /// Deletes the exported copy of an asset that will not be uploaded after all.
    ///
    /// Every `createUpload` path that returns without handing the file to a URLSession task has
    /// to call this. The success path does not: the task owns the file until
    /// `didCompleteWithError` removes it. Exports are full-size originals — a handful of
    /// abandoned videos is gigabytes of the user's storage that nothing else will ever reclaim,
    /// since these live under a UUID in tmp with no other reference to them (§5.6).
    private func discardExport(_ exp: Uploader.ExportResult) {
        try? fileManager.removeItem(at: exp.fileURL)
    }

    /// Ends an upload that can never succeed at its current size.
    ///
    /// Deliberately reports `.clientError` and completes the hand-off with `.success`, mirroring
    /// the 409-dedupe path: `.failure` here would route into SyncCoordinator's export-retry
    /// branch and re-queue the asset every ten seconds, which is precisely the spin §5.4 removed.
    /// The asset is **not** marked uploaded — its bytes are not on the server — only recorded as
    /// refused at this limit, so a later, larger cap picks it up again.
    private func refuseForSize(
        asset: PHAsset,
        exp: Uploader.ExportResult,
        size: Int64,
        limit: Int64?,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        let assetId = asset.localIdentifier
        discardExport(exp)
        SyncLogger.shared.logUploadSkippedTooLarge(filename: exp.filename, size: size, limit: limit)
        UploadStore.shared.markSkippedTooLarge(
            assetId,
            limit: limit ?? UploadSizeLimit.impliedLimit(forRefusedSize: size)
        )
        onTaskFinished?(assetId, .clientError)
        completion?(.success(()))
    }

    private func resolveLocation(_ location: String, against base: URL) -> URL? {
        if let abs = URL(string: location), abs.scheme != nil { return abs }
        return URL(string: location, relativeTo: base)?.absoluteURL
    }

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        // See Uploader.parseRetryAfter: "NaN"/"inf"/negatives parse successfully and
        // must not become a retry deadline.
        guard let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)),
              seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }

    // MARK: - URLSession Delegate

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            if let desc = task.taskDescription {
                let comps = desc.components(separatedBy: "|")
                if comps.count > 1 {
                    try? fileManager.removeItem(atPath: comps[1])
                }
            }
        }
        guard let desc = task.taskDescription else { return }
        let comps = desc.components(separatedBy: "|")
        guard let assetId = comps.first else { return }
        let checksum = comps.count > 3 ? comps[3] : nil

        if let error {
            SyncLogger.shared.logUploadFailure(assetId: assetId, error: error.localizedDescription)
            UploadStore.shared.removeFromUploading(assetId)
            onTaskFinished?(assetId, .transport)
            return
        }
        if let http = task.response as? HTTPURLResponse {
            let code = http.statusCode
            if (200 ... 299).contains(code) {
                UploadStore.shared.markUploaded(assetId, checksum: checksum)
                SyncCoordinator.shared.onUploadedOne(assetId: assetId)
                SyncLogger.shared.logUploadSuccess(assetId: assetId)
                // The PATCH response carries TUS headers only — the server-side asset id is
                // resolved out-of-band by SyncCoordinator (lookup by contentId) when status
                // polling is integrated. nil here is fine: it just disables polling for now.
                onTaskFinished?(assetId, .success(serverAssetId: nil))
            } else if code == 429 || code == 503 {
                let retry = parseRetryAfter(from: http) ?? 30
                SyncLogger.shared.logUploadDeferred(assetId: assetId, retryAfter: retry)
                UploadStore.shared.removeFromUploading(assetId)
                onTaskFinished?(assetId, .backpressure(retry))
            } else {
                SyncLogger.shared.logUploadFailure(assetId: assetId, error: "HTTP \(code)")
                UploadStore.shared.removeFromUploading(assetId)
                onTaskFinished?(assetId, .clientError)
            }
        } else {
            UploadStore.shared.markUploaded(assetId, checksum: checksum)
            SyncCoordinator.shared.onUploadedOne(assetId: assetId)
            SyncLogger.shared.logUploadSuccess(assetId: assetId)
            onTaskFinished?(assetId, .success(serverAssetId: nil))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        onAllBackgroundEventsComplete?(session.configuration.identifier ?? "")
    }
}

// MARK: - APIClient helpers (Phase 5)

extension APIClient {
    /// URL the iOS client POSTs to for TUS upload creation. Hardcoded to "/files/" until the
    /// SyncCoordinator integration step caches and consults ``Capabilities/tus/endpoint``.
    func tusEndpointURL() -> URL {
        baseURL.appendingPathComponent("files/")
    }

    /// The legacy `auth` value: the account's own `email:password`.
    ///
    /// Only used when the server has no token endpoint (§5.9). tusd persists upload metadata to a
    /// `.info` object in storage, so this writes the real password to disk — which is exactly why
    /// ``UploadTokenStore`` exists and why this is the fallback rather than the default.
    var legacyAuthMetadataValue: String? {
        guard let username, let password else { return nil }
        return "\(username):\(password)"
    }

    /// Builds the comma-separated ``Upload-Metadata`` header per the TUS spec. Each value is
    /// base64-encoded; the server decodes when populating ``Event.Upload.MetaData`` for hooks.
    ///
    /// - Parameter auth: the credential the server's pre-create hook authenticates with — a
    ///   scoped upload token normally, ``legacyAuthMetadataValue`` against an older server.
    func tusUploadMetadata(filename: String, mimeType: String, contentId: String,
                           albumId: Int? = nil, auth: String? = nil) -> String
    {
        var parts: [(String, String)] = [
            ("filename", filename),
            ("filetype", mimeType),
            ("contentId", contentId),
        ]
        if let albumId {
            parts.append(("albumId", String(albumId)))
        }
        if let auth = auth ?? legacyAuthMetadataValue {
            parts.append(("auth", auth))
        }
        return parts
            .map { key, value in
                let b64 = Data(value.utf8).base64EncodedString()
                return "\(key) \(b64)"
            }
            .joined(separator: ",")
    }
}
