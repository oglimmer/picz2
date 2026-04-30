import CryptoKit
import Foundation
import Photos

final class Uploader: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    static let shared = Uploader()

    private let sessionId = "com.oglimmer.photosync.upload"
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
        case clientError       // non-retryable 4xx (except 429)
        case transport         // network / session error, system will retry
        case backpressure(TimeInterval) // HTTP 429/503, with retry delay
    }
    var onTaskFinished: ((String, UploadOutcome) -> Void)?

    override private init() { super.init() }

    func configureSession(with identifier: String? = nil) {
        let id = identifier ?? sessionId
        let config = URLSessionConfiguration.background(withIdentifier: id)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false // Set to false for more reliable, predictable uploads
        config.allowsCellularAccess = !Settings.shared.wifiOnly
        config.allowsExpensiveNetworkAccess = !Settings.shared.wifiOnly
        config.allowsConstrainedNetworkAccess = !Settings.shared.wifiOnly
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// Get asset IDs for all active upload tasks in the background URLSession
    func getActiveUploadAssetIds() -> Set<String> {
        var activeIds = Set<String>()
        let semaphore = DispatchSemaphore(value: 0)

        session?.getAllTasks { tasks in
            for task in tasks {
                // Extract asset ID from taskDescription (format: "assetId|fileURL|multipartURL|checksum")
                if let desc = task.taskDescription,
                   let assetId = desc.components(separatedBy: "|").first
                {
                    activeIds.insert(assetId)
                }
            }
            semaphore.signal()
        }

        // Wait for async task enumeration to complete (with timeout)
        _ = semaphore.wait(timeout: .now() + 2)
        return activeIds
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

        let ext: String
        let mime: String
        switch resource.type {
        case .video, .fullSizeVideo: ext = "mov"; mime = "video/quicktime"
        default: ext = "jpg"; mime = "image/jpeg"
        }

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

    func queueUpload(asset: PHAsset, api: APIClient, completion: ((Result<Void, Error>) -> Void)? = nil) {
        // Mark as uploading BEFORE export to prevent race conditions
        UploadStore.shared.markAsUploading(asset.localIdentifier)

        exportAssetToTempFile(asset) { result in
            switch result {
            case let .failure(error):
                UploadStore.shared.removeFromUploading(asset.localIdentifier)
                completion?(.failure(error))
            case let .success(exp):
                do {
                    // Store checksum mapping immediately
                    UploadStore.shared.storeChecksumMapping(checksum: exp.checksum, localId: asset.localIdentifier)

                    let request = api.makeUploadRequest(for: asset, filename: exp.filename, mimeType: exp.mimeType)

                    // Extract boundary from Content-Type header
                    guard let contentType = request.value(forHTTPHeaderField: "Content-Type"),
                          let boundary = contentType.components(separatedBy: "boundary=").last
                    else {
                        UploadStore.shared.removeFromUploading(asset.localIdentifier)
                        completion?(.failure(NSError(domain: "Uploader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract boundary"])))
                        return
                    }

                    // Create multipart body (streamed) with contentId and write to temp file for background upload
                    let multipartURL = self.fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("multipart")
                    try api.writeMultipartBody(to: multipartURL,
                                               fileURL: exp.fileURL,
                                               filename: exp.filename,
                                               mimeType: exp.mimeType,
                                               boundary: boundary,
                                               contentId: asset.localIdentifier)

                    let task = self.session.uploadTask(with: request, fromFile: multipartURL)
                    // Store localIdentifier, file paths, and checksum for cleanup and tracking
                    task.taskDescription = [asset.localIdentifier, exp.fileURL.path, multipartURL.path, exp.checksum].joined(separator: "|")
                    task.resume()
                    completion?(.success(()))
                } catch {
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
                SyncCoordinator.shared.onUploadedOne(assetId: assetId)
                SyncLogger.shared.logUploadSuccess(assetId: assetId)
                let serverAssetId = bufferedBody.flatMap(parseServerAssetId(from:))
                onTaskFinished?(assetId, .success(serverAssetId: serverAssetId))
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
    private func parseServerAssetId(from data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let file = json["file"] as? [String: Any],
              let id = file["id"] as? Int
        else { return nil }
        return id
    }

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)) {
            return seconds
        }
        // HTTP-date form — not expected from our server; fall through to default
        return nil
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        onAllBackgroundEventsComplete?(session.configuration.identifier ?? "")
    }
}
