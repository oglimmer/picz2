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

    func getActiveUploadAssetIds() -> Set<String> {
        var activeIds = Set<String>()
        let semaphore = DispatchSemaphore(value: 0)
        session?.getAllTasks { tasks in
            for task in tasks {
                if let desc = task.taskDescription,
                   let assetId = desc.components(separatedBy: "|").first
                {
                    activeIds.insert(assetId)
                }
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
        return activeIds
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

        var request = URLRequest(url: tusURL)
        request.httpMethod = "POST"
        request.applyNetworkPolicy()
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(fileSize), forHTTPHeaderField: "Upload-Length")
        request.setValue(
            api.tusUploadMetadata(filename: exp.filename, mimeType: exp.mimeType,
                                  contentId: asset.localIdentifier),
            forHTTPHeaderField: "Upload-Metadata"
        )
        api.addBasicAuth(to: &request)

        let assetId = asset.localIdentifier
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            if let error {
                SyncLogger.shared.logUploadFailure(assetId: assetId, error: error.localizedDescription)
                UploadStore.shared.removeFromUploading(assetId)
                completion?(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
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
                SyncLogger.shared.logUploadDeduped(assetId: assetId)
                UploadStore.shared.markUploaded(assetId, checksum: exp.checksum)
                self.onTaskFinished?(assetId, .success(serverAssetId: nil))
                completion?(.success(()))
            case 413:
                // The local check above did not catch it — capabilities were never fetched, or
                // the cap was lowered since. Same outcome, same message, limit left unstated
                // when we genuinely do not know it.
                self.refuseForSize(asset: asset, exp: exp, size: fileSize,
                                   limit: maxUploadBytes, completion: completion)
            case 429, 503:
                let retry = self.parseRetryAfter(from: http) ?? 30
                SyncLogger.shared.logUploadDeferred(assetId: assetId, retryAfter: retry)
                UploadStore.shared.removeFromUploading(assetId)
                self.onTaskFinished?(assetId, .backpressure(retry))
                completion?(.success(()))
            default:
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
        try? fileManager.removeItem(at: exp.fileURL)
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

    /// Builds the comma-separated ``Upload-Metadata`` header per the TUS spec. Each value is
    /// base64-encoded; the server decodes when populating ``Event.Upload.MetaData`` for hooks.
    func tusUploadMetadata(filename: String, mimeType: String, contentId: String, albumId: Int? = nil) -> String {
        var parts: [(String, String)] = [
            ("filename", filename),
            ("filetype", mimeType),
            ("contentId", contentId),
        ]
        if let albumId {
            parts.append(("albumId", String(albumId)))
        }
        if let username, let password {
            parts.append(("auth", "\(username):\(password)"))
        }
        return parts
            .map { key, value in
                let b64 = Data(value.utf8).base64EncodedString()
                return "\(key) \(b64)"
            }
            .joined(separator: ",")
    }
}
