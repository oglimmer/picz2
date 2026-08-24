import CryptoKit
import Foundation
import Photos

final class Uploader: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    static let shared = Uploader()

    let sessionId = "com.oglimmer.photosync.upload"
    private(set) var session: URLSession!
    private let fileManager = FileManager.default

    // Buffered response bodies, keyed by URLSessionTask.taskIdentifier, used to
    // extract the server-side asset id from the upload 202 response so the
    // SyncCoordinator can poll /api/assets/{id}/status afterwards. Mutated
    // only on the URLSession's delegate queue (single-threaded per session).
    private var responseBodyByTaskId: [Int: Data] = [:]

    // Called by AppDelegate when background session finished delivering events
    var onAllBackgroundEventsComplete: ((String) -> Void)?

    // Fires for every task that finished (success, failure, backpressure).
    // SyncCoordinator uses this to free a concurrency slot and re-enqueue
    // on HTTP 503 with the honored Retry-After delay. The server-side asset
    // id (when parseable from the 2xx body) rides along on .success so the
    // coordinator can spin up status polling for it.
    enum UploadOutcome {
        case success(serverAssetId: Int?)
        case deduped           // server already holds this contentId; no bytes were sent
        case clientError       // non-retryable 4xx (except 429)
        case transport         // network / session error, system will retry
        case backpressure(TimeInterval) // HTTP 429/503, with retry delay
    }
    var onTaskFinished: ((String, UploadOutcome) -> Void)?

    override private init() { super.init() }

    /// Creates the background session, once. Call from the main thread.
    ///
    /// URLSession does not support two live sessions sharing a background identifier: the
    /// second one orphans the first's delegate, so in-flight uploads lose the callback that
    /// frees their queue slot and deletes their temp files. This used to happen on every
    /// foreground, because SyncCoordinator.start() runs on each scenePhase change.
    ///
    /// Wi‑Fi Only is deliberately NOT set here — a background configuration is immutable
    /// after creation, so the toggle is applied per request via `applyNetworkPolicy()`.
    func configureSession(with identifier: String? = nil) {
        let id = identifier ?? sessionId
        if let session, session.configuration.identifier == id { return }

        let config = URLSessionConfiguration.background(withIdentifier: id)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false // Set to false for more reliable, predictable uploads
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

    struct ExportResult {
        let fileURL: URL
        let filename: String
        let mimeType: String
        let checksum: String
    }

    func exportAssetToTempFile(_ asset: PHAsset, completion: @escaping (Result<ExportResult, Error>) -> Void) {
        let resources = PHAssetResource.assetResources(for: asset)
        // Prefer full size resource, else the first.
        guard let resource = resources.first(where: {
            $0.type == .fullSizePhoto || $0.type == .fullSizeVideo
        }) ?? resources.first else {
            completion(.failure(AppError.photoLibrary("No resources found for asset")))
            return
        }

        // Ask the resource what it is instead of assuming "not a video means JPEG" — an iPhone
        // photo is HEIC, and mislabelling it only worked because the server re-checks the
        // filename extension. See ``ExportFormat``.
        let format = ExportFormat.forResource(
            type: resource.type,
            uniformTypeIdentifier: resource.uniformTypeIdentifier,
        )
        let ext = format.fileExtension
        let mime = format.mimeType

        let filename = (resource.originalFilename as NSString).pathExtension.isEmpty ? "\(UUID().uuidString).\(ext)" : resource.originalFilename
        let tempDir = fileManager.temporaryDirectory
        let targetURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)

        let opts = PHAssetResourceRequestOptions()
        opts.isNetworkAccessAllowed = true

        PHAssetResourceManager.default().writeData(for: resource, toFile: targetURL, options: opts) { error in
            if let error {
                completion(.failure(error))
                return
            }

            // Compute SHA-256 checksum (streamed)
            do {
                let checksum = try self.sha256(ofFileAt: targetURL)
                completion(.success(ExportResult(fileURL: targetURL, filename: filename, mimeType: mime, checksum: checksum)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func sha256(ofFileAt url: URL) throws -> String {
        let chunkSize = 64 * 1024
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while true {
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// - Parameter albumId: the album the asset must land in. Nil — the background-sync case —
    ///   leaves the choice to the server, which uses the account's target album.
    func queueUpload(asset: PHAsset, api: APIClient, albumId: Int? = nil,
                     completion: ((Result<Void, Error>) -> Void)? = nil)
    {
        // Mark as uploading BEFORE export to prevent race conditions
        UploadStore.shared.markAsUploading(asset.localIdentifier)

        exportAssetToTempFile(asset) { result in
            switch result {
            case let .failure(error):
                UploadStore.shared.removeFromUploading(asset.localIdentifier)
                completion?(.failure(error))
            case let .success(exp):
                // Declared out here so the failure paths below can delete it. Both files are
                // full-size copies of the asset living under a UUID in tmp; if we return without
                // handing them to a URLSession task, nothing else has a reference and nothing
                // ever reclaims the space (§5.6). On the success path the task owns them until
                // didCompleteWithError removes them.
                let multipartURL = self.fileManager.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension("multipart")
                func discardTempFiles() {
                    try? self.fileManager.removeItem(at: exp.fileURL)
                    try? self.fileManager.removeItem(at: multipartURL)
                }

                do {
                    // Store checksum mapping immediately
                    UploadStore.shared.storeChecksumMapping(checksum: exp.checksum, localId: asset.localIdentifier)

                    var request = api.makeUploadRequest(for: asset, filename: exp.filename, mimeType: exp.mimeType)
                    request.applyNetworkPolicy()

                    // Extract boundary from Content-Type header
                    guard let contentType = request.value(forHTTPHeaderField: "Content-Type"),
                          let boundary = contentType.components(separatedBy: "boundary=").last
                    else {
                        discardTempFiles()
                        UploadStore.shared.removeFromUploading(asset.localIdentifier)
                        completion?(.failure(NSError(domain: "Uploader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract boundary"])))
                        return
                    }

                    // Create multipart body (streamed) with contentId and write to temp file for background upload
                    try api.writeMultipartBody(to: multipartURL,
                                               fileURL: exp.fileURL,
                                               filename: exp.filename,
                                               mimeType: exp.mimeType,
                                               boundary: boundary,
                                               contentId: asset.localIdentifier,
                                               albumId: albumId)

                    let task = self.session.uploadTask(with: request, fromFile: multipartURL)
                    // Store localIdentifier, file paths, and checksum for cleanup and tracking
                    // Index 4 is the album asked for, so the completion can tell a real upload
                    // from a duplicate the server answered with a file in some other album.
                    task.taskDescription = [
                        asset.localIdentifier,
                        exp.fileURL.path,
                        multipartURL.path,
                        exp.checksum,
                        albumId.map(String.init) ?? "",
                    ].joined(separator: "|")
                    task.resume()
                    completion?(.success(()))
                } catch {
                    // writeMultipartBody throws part-way through: both the export and whatever
                    // was written of the multipart body have to go.
                    discardTempFiles()
                    UploadStore.shared.removeFromUploading(asset.localIdentifier)
                    completion?(.failure(error))
                }
            }
        }
    }

    // MARK: - URLSession Delegate

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Background URLSessionUploadTask is a URLSessionDataTask; the 202
        // response body is delivered here in chunks. Buffer it so the
        // didCompleteWithError path can parse out the server-side asset id.
        responseBodyByTaskId[dataTask.taskIdentifier, default: Data()].append(data)
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let bufferedBody = responseBodyByTaskId.removeValue(forKey: task.taskIdentifier)

        defer {
            // Clean up temp files if present in taskDescription
            if let desc = task.taskDescription {
                let components = desc.components(separatedBy: "|")
                // Clean up original asset file (index 1) and multipart file (index 2)
                if components.count > 1 {
                    try? fileManager.removeItem(atPath: components[1])
                }
                if components.count > 2 {
                    try? fileManager.removeItem(atPath: components[2])
                }
            }
        }

        // Extract task info
        guard let desc = task.taskDescription else { return }
        let components = desc.components(separatedBy: "|")
        guard let assetId = components.first else { return }

        // Handle transport error — system will retry background tasks automatically
        if let error {
            let errorMessage = error.localizedDescription
            SyncLogger.shared.logUploadFailure(assetId: assetId, error: errorMessage)
            UploadStore.shared.removeFromUploading(assetId)
            onTaskFinished?(assetId, .transport)
            return
        }

        // Check HTTP response
        if let http = task.response as? HTTPURLResponse {
            let code = http.statusCode
            if (200 ... 299).contains(code) {
                let checksum = components.count > 3 ? components[3] : nil
                UploadStore.shared.markUploaded(assetId, checksum: checksum)
                let serverAssetId = bufferedBody.flatMap(parseServerAssetId(from:))

                // The server dedupes by contentId across the whole account, and answers a
                // duplicate with the row it already had — which sits in whatever album it was
                // first filed under. So a 2xx naming a different album than the one we asked
                // for means nothing was stored and nothing will appear here. Reporting that as
                // a plain success is why an upload could silently do nothing.
                let requestedAlbumId = components.count > 4 ? Int(components[4]) : nil
                let storedAlbumId = bufferedBody.flatMap(parseServerAlbumId(from:))
                if let requestedAlbumId, let storedAlbumId, storedAlbumId != requestedAlbumId {
                    SyncLogger.shared.logUploadDeduped(assetId: assetId)
                    onTaskFinished?(assetId, .deduped)
                } else {
                    SyncCoordinator.shared.onUploadedOne(assetId: assetId)
                    SyncLogger.shared.logUploadSuccess(assetId: assetId)
                    onTaskFinished?(assetId, .success(serverAssetId: serverAssetId))
                }
            } else if code == 429 || code == 503 {
                // Server backpressure — expected signal, not a failure. Log as
                // informational so the user doesn't see a red error entry.
                let retryAfter = parseRetryAfter(from: http) ?? 30
                SyncLogger.shared.logUploadDeferred(assetId: assetId, retryAfter: retryAfter)
                UploadStore.shared.removeFromUploading(assetId)
                onTaskFinished?(assetId, .backpressure(retryAfter))
            } else {
                SyncLogger.shared.logUploadFailure(assetId: assetId, error: "HTTP \(code)")
                UploadStore.shared.removeFromUploading(assetId)
                onTaskFinished?(assetId, .clientError)
            }
        } else {
            // Non-HTTP upload (unlikely) — assume success
            let checksum = components.count > 3 ? components[3] : nil
            UploadStore.shared.markUploaded(assetId, checksum: checksum)
            SyncCoordinator.shared.onUploadedOne(assetId: assetId)
            SyncLogger.shared.logUploadSuccess(assetId: assetId)
            onTaskFinished?(assetId, .success(serverAssetId: nil))
        }
    }

    // Pulls `file.id` out of the upload 202 body. Defensive: any decoding
    // failure (truncated body in background relaunch, server schema change)
    // falls back to nil and just disables polling for that asset.
    func parseServerAssetId(from data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let file = json["file"] as? [String: Any],
              let id = file["id"] as? Int
        else { return nil }
        return id
    }

    // Pulls `file.albumId` out of the upload 202 body. Same defensive contract as
    // ``parseServerAssetId(from:)``: anything unexpected reads as nil, which makes the caller
    // treat the upload as an ordinary success rather than inventing a duplicate.
    func parseServerAlbumId(from data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let file = json["file"] as? [String: Any],
              let albumId = file["albumId"] as? Int
        else { return nil }
        return albumId
    }

    func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        // TimeInterval() happily parses "NaN", "inf" and negatives. Any of those would
        // flow into a retry deadline, so reject them and let the caller apply its own
        // default rather than scheduling a nonsense delay.
        if let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)),
           seconds.isFinite, seconds >= 0 {
            return seconds
        }
        // HTTP-date form — not expected from our server; fall through to default
        return nil
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        onAllBackgroundEventsComplete?(session.configuration.identifier ?? "")
    }
}
