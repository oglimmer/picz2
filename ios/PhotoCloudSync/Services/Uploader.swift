import CryptoKit
import Foundation
import Photos

final class Uploader: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    static let shared = Uploader()

    private let sessionId = "com.oglimmer.photosync.upload"
    private(set) var session: URLSession!
    private let fileManager = FileManager.default

    // Called by AppDelegate when background session finished delivering events
    var onAllBackgroundEventsComplete: ((String) -> Void)?

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

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
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

        // Handle error
        if let error {
            let errorMessage = error.localizedDescription
            SyncLogger.shared.logUploadFailure(assetId: assetId, error: errorMessage)
            UploadStore.shared.removeFromUploading(assetId)
            return // System will retry background tasks automatically based on policy
        }

        // Check HTTP response
        let success: Bool
        if let http = task.response as? HTTPURLResponse {
            success = (200 ... 299).contains(http.statusCode)
            if !success {
                let errorMessage = "HTTP \(http.statusCode)"
                SyncLogger.shared.logUploadFailure(assetId: assetId, error: errorMessage)
                UploadStore.shared.removeFromUploading(assetId)
                return
            }
        } else {
            success = true // Non-HTTP upload (unlikely) — assume success
        }

        if success {
            let checksum = components.count > 3 ? components[3] : nil
            UploadStore.shared.markUploaded(assetId, checksum: checksum)
            SyncCoordinator.shared.onUploadedOne(assetId: assetId)
            SyncLogger.shared.logUploadSuccess(assetId: assetId)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        onAllBackgroundEventsComplete?(session.configuration.identifier ?? "")
    }
}
