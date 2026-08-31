import Foundation
import os
import Photos

/// Phase 5 — TUS resumable uploads. Drop-in alternative to ``Uploader`` selected at runtime by
/// ``SyncCoordinator`` based on the server-advertised capabilities
/// (``APIClient/fetchCapabilities``).
///
/// V1 shipped a single PATCH of the whole file from offset 0. Traefik's 60s `readTimeout`
/// killed anything that took longer, and the next attempt started from byte 0 again. Chunked
/// PATCH from the server's `Upload-Offset` (via HEAD) is what actually resumes.
/// - Note: `@unchecked Sendable` — same reasoning as ``Uploader``: the delegate callbacks arrive
///   on the session's own serial delegate queue.
final class TusUploader: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate,
    URLSessionDownloadDelegate, @unchecked Sendable
{
    static let shared = TusUploader()

    let sessionId = "com.oglimmer.photosync.tus"
    /// Assigned once by ``configureSession()`` before any callback can arrive, then never again.
    private(set) nonisolated(unsafe) var session: URLSession!
    private let fileManager = FileManager.default

    /// Mirrors ``Uploader/UploadOutcome`` so ``SyncCoordinator`` can route either uploader's
    /// completions through the same handler. Kept as a sibling enum (rather than a shared
    /// top-level type) to keep this scaffolding additive.
    enum UploadOutcome {
        case success(serverAssetId: Int?)
        case deduped
        case clientError
        case transport
        case backpressure(TimeInterval)
    }

    var onTaskFinished: ((String, UploadOutcome) -> Void)?
    var onAllBackgroundEventsComplete: ((String) -> Void)?

    /// Consecutive transport-error resumes per asset. Cleared every time the server's offset
    /// actually advances — the budget is for a chunk that keeps dying on the ingress, not for a
    /// 500-chunk video that hits three bad moments in an hour.
    private let resumeBudget = TusResumeBudget()

    /// Where chunks are cut. Never the URLSession delegate queue: a 4 MiB copy there blocks
    /// every other callback the session owes us.
    private let sliceQueue = DispatchQueue(label: "com.oglimmer.photosync.tus.slice", qos: .utility)

    /// What a create POST needs that ``TusTask`` cannot carry across a relaunch.
    ///
    /// The `PHAsset`, the export record and the caller's completion are live objects, and
    /// `taskDescription` is a string. So they are held here for the lifetime of the process and
    /// looked up when the task finishes. After a relaunch the lookup misses, which
    /// ``handleCreateFinished`` treats as its degraded path rather than as an error.
    private struct PendingCreate {
        let api: APIClient
        let asset: PHAsset
        let exp: Uploader.ExportResult
        let fileSize: Int64
        let tusURL: URL
        let maxUploadBytes: Int64?
        let albumId: Int?
        let mayRetryWithFreshToken: Bool
        let completion: (@Sendable (Result<Void, Error>) -> Void)?
    }

    /// Guards ``pendingCreates`` and ``createBodies``. Both are written from whichever thread
    /// starts an upload and read from the session's delegate queue.
    private let createLock = NSLock()
    private var pendingCreates: [String: PendingCreate] = [:]
    /// Response bytes of in-flight create POSTs, keyed by task identifier. Only a 507 has a body
    /// worth reading, but the delegate cannot know the status code while the bytes arrive.
    private var createBodies: [Int: Data] = [:]

    private func rememberPendingCreate(_ create: PendingCreate, for assetId: String) {
        createLock.lock()
        pendingCreates[assetId] = create
        createLock.unlock()
    }

    private func takePendingCreate(for assetId: String) -> PendingCreate? {
        createLock.lock()
        defer { createLock.unlock() }
        return pendingCreates.removeValue(forKey: assetId)
    }

    private func appendCreateBody(_ data: Data, for taskIdentifier: Int) {
        createLock.lock()
        createBodies[taskIdentifier, default: Data()].append(data)
        createLock.unlock()
    }

    private func takeCreateBody(for taskIdentifier: Int) -> Data? {
        createLock.lock()
        defer { createLock.unlock() }
        return createBodies.removeValue(forKey: taskIdentifier)
    }

    override private init() {
        super.init()
    }

    /// Creates the background session, once. Call from the main thread.
    /// See ``Uploader/configureSession(with:)`` for why this is idempotent and why the
    /// Wi‑Fi Only setting is applied per request instead of on the configuration.
    func configureSession(with identifier: String? = nil) {
        let id = identifier ?? sessionId
        if let session, session.configuration.identifier == id {
            return
        }

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
    func getActiveUploadAssetIds(completion: @escaping @Sendable (Set<String>) -> Void) {
        guard let session else {
            completion([])
            return
        }
        session.getAllTasks { tasks in
            // taskDescription format: "assetId|fileURL|…"
            completion(Set(tasks.compactMap { $0.taskDescription?.components(separatedBy: "|").first }))
        }
    }

    /// - Parameter albumId: the album the asset must land in, sent as `Upload-Metadata.albumId`.
    ///   Nil — the background-sync case — leaves the choice to the server's target album.
    /// - Parameter maxUploadBytes: the server's advertised `tus.maxSize`, or nil when
    ///   capabilities have not been fetched yet. Only used to refuse a file locally with a
    ///   readable reason instead of a 413 — never to relax anything the server enforces.
    func queueUpload(
        asset: PHAsset,
        api: APIClient,
        maxUploadBytes: Int64? = nil,
        albumId: Int? = nil,
        completion: (@Sendable (Result<Void, Error>) -> Void)? = nil,
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
                createUpload(api: api, asset: asset, exp: exp, maxUploadBytes: maxUploadBytes,
                             albumId: albumId, completion: completion)
            }
        }
    }

    private func createUpload(
        api: APIClient,
        asset: PHAsset,
        exp: Uploader.ExportResult,
        maxUploadBytes: Int64?,
        albumId: Int?,
        completion: (@Sendable (Result<Void, Error>) -> Void)?,
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
                                albumId: albumId,
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
        albumId: Int?,
        mayRetryWithFreshToken: Bool,
        completion: (@Sendable (Result<Void, Error>) -> Void)?,
    ) {
        var request = URLRequest(url: tusURL)
        request.httpMethod = "POST"
        request.applyNetworkPolicy()
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(fileSize), forHTTPHeaderField: "Upload-Length")
        request.setValue(
            api.tusUploadMetadata(filename: exp.filename, mimeType: exp.mimeType,
                                  contentId: asset.localIdentifier, albumId: albumId,
                                  auth: authValue, checksum: exp.checksum),
            forHTTPHeaderField: "Upload-Metadata",
        )
        api.addBasicAuth(to: &request)

        let assetId = asset.localIdentifier

        // The create POST goes on the **background** session, for the same reason the resume
        // HEAD below does: a `URLSession.shared` task is killed the moment iOS suspends the app,
        // and its error is only delivered at the next wake-up — as "The request timed out."
        // against a server that never saw the request at all. Three of those and
        // `SyncCoordinator`'s export-retry policy gave the asset up, which is what filled the
        // Status tab with red lines for uploads that had never been attempted.
        //
        // Background sessions accept only upload and download tasks, so this is an upload task
        // with a zero-byte body: TUS creation carries its length in `Upload-Length`, never in
        // the body. That empty file is the task's `chunkPath`, so `didCompleteWithError` deletes
        // it along with every other slice.
        //
        // `session` is an implicitly unwrapped optional assigned by ``configureSession()``, which
        // both `AppDelegate.didFinishLaunching` and `SyncCoordinator.start` call. It is checked
        // rather than forced because the old code path could not crash here, and a refused upload
        // is a better failure than a dead app.
        guard let session else {
            discardExport(exp)
            SyncLogger.shared.logUploadFailure(assetId: assetId, error: "upload session not ready")
            UploadStore.shared.removeFromUploading(assetId)
            completion?(.failure(AppError.api(message: "Could not start the upload.",
                                              statusCode: nil)))
            return
        }
        let bodyURL = fileManager.temporaryDirectory
            .appendingPathComponent("tus-create-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: bodyURL.path, contents: Data()) else {
            discardExport(exp)
            SyncLogger.shared.logUploadFailure(assetId: assetId,
                                               error: "could not stage the create request")
            UploadStore.shared.removeFromUploading(assetId)
            completion?(.failure(AppError.api(message: "Could not start the upload.",
                                              statusCode: nil)))
            return
        }

        rememberPendingCreate(
            PendingCreate(api: api, asset: asset, exp: exp, fileSize: fileSize, tusURL: tusURL,
                          maxUploadBytes: maxUploadBytes, albumId: albumId,
                          mayRetryWithFreshToken: mayRetryWithFreshToken, completion: completion),
            for: assetId,
        )

        let task = session.uploadTask(with: request, fromFile: bodyURL)
        task.taskDescription = TusTask(
            assetId: assetId,
            chunkPath: bodyURL.path,
            // No resource exists yet, so there is no per-upload URL to record. The collection URL
            // goes here instead: it is what a relaunched process resolves `Location` against.
            uploadURL: tusURL,
            checksum: exp.checksum,
            originalPath: exp.fileURL.path,
            fileSize: fileSize,
            sentOffset: 0,
            kind: .create,
        ).description
        task.resume()
    }

    /// The create POST came back. Routes the answer exactly as the old completion handler did.
    ///
    /// `pending` is nil when iOS relaunched the app only to deliver this: the `PHAsset`, the
    /// export record and the caller's completion are live objects no `taskDescription` can carry.
    /// A 201 still continues from the fields ``TusTask`` does carry — path, checksum and size are
    /// all ``patchChunk`` needs — a 409 still records the dedupe, and every other answer cleans
    /// the export up rather than leaving the asset stuck in `uploading`.
    private func handleCreateFinished(
        create: TusTask,
        pending: PendingCreate?,
        error: Error?,
        response: URLResponse?,
        body: Data?,
    ) {
        let assetId = create.assetId
        let originalURL = URL(fileURLWithPath: create.originalPath)
        let completion = pending?.completion

        if let error {
            failCreate(assetId: assetId, originalURL: originalURL,
                       message: error.localizedDescription, completion: completion)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            failCreate(assetId: assetId, originalURL: originalURL,
                       message: "no response from server", completion: completion)
            return
        }

        switch http.statusCode {
        case 200, 201:
            guard let location = http.value(forHTTPHeaderField: "Location"),
                  let uploadURL = resolveLocation(location, against: create.uploadURL)
            else {
                failCreate(assetId: assetId, originalURL: originalURL,
                           message: "missing Location header", completion: completion)
                return
            }
            // A freshly created TUS resource is empty by definition, so the offset is 0
            // and a HEAD here would only cost a round-trip. HEAD is the *resume* path.
            patchChunk(
                assetId: assetId,
                originalURL: originalURL,
                uploadURL: uploadURL,
                checksum: create.checksum,
                fileSize: create.fileSize,
                offset: 0,
                api: pending?.api ?? apiFromKeychain(),
                completion: completion,
            )
        case 409:
            // Pre-create dedupe — the server already holds this asset somewhere in the
            // account, matched on either the contentId or the checksum, and refuses the bytes.
            // The checksum arm is the one that fires for a second device: the same iCloud
            // photo synced from an iPad has its own contentId but identical bytes.
            //
            // Reported as its own outcome rather than as a success: nothing was stored, so an
            // upload aimed at a particular album produces no new photo there, and the caller
            // has to be able to say so.
            try? fileManager.removeItem(at: originalURL)
            SyncLogger.shared.logUploadDeduped(assetId: assetId)
            UploadStore.shared.markUploaded(assetId, checksum: create.checksum)
            onTaskFinished?(assetId, .deduped)
            completion?(.success(()))
        case 401 where pending?.mayRetryWithFreshToken == true:
            // The token was refused — expired early, or revoked by a password change. Mint a
            // new one and run the same create again, once. Without this the asset would be
            // reported as a permanent client error and skipped until the next scan, for what
            // is really a routine credential rotation.
            guard let pending else { return }
            UploadTokenStore.shared.invalidate()
            UploadTokenStore.shared.token(api: pending.api) { [weak self] fresh in
                guard let self else { return }
                AppLog.upload.notice("Upload token refused — retrying with a fresh one")
                performCreate(api: pending.api, asset: pending.asset, exp: pending.exp,
                              fileSize: pending.fileSize, tusURL: pending.tusURL,
                              authValue: fresh, maxUploadBytes: pending.maxUploadBytes,
                              albumId: pending.albumId, mayRetryWithFreshToken: false,
                              completion: pending.completion)
            }
        case 413:
            // The local check in `createUpload` did not catch it — capabilities were never
            // fetched, or the cap was lowered since. Same outcome, same message, limit left
            // unstated when we genuinely do not know it.
            guard let pending else {
                failCreate(assetId: assetId, originalURL: originalURL,
                           message: "HTTP 413", completion: completion)
                return
            }
            refuseForSize(asset: pending.asset, exp: pending.exp, size: create.fileSize,
                          limit: pending.maxUploadBytes, completion: completion)
        case 507:
            // The account's storage on the server is full. Not retryable on any timer — it
            // clears when the user frees space or registers their own storage — so it is
            // reported like the too-large refusal rather than deferred: the asset stays
            // un-uploaded and is picked up again by a later scan once there is room.
            guard let pending else {
                failCreate(assetId: assetId, originalURL: originalURL,
                           message: "HTTP 507", completion: completion)
                return
            }
            refuseForStorageFull(asset: pending.asset, exp: pending.exp, response: body)
            completion?(.success(()))
        case 429, 503:
            let retry = parseRetryAfter(from: http) ?? 30
            // Safe to delete: a deferred asset is re-queued and re-exported from the photo
            // library when its turn comes round again, not resumed from this file.
            try? fileManager.removeItem(at: originalURL)
            SyncLogger.shared.logUploadDeferred(assetId: assetId, retryAfter: retry)
            UploadStore.shared.removeFromUploading(assetId)
            onTaskFinished?(assetId, .backpressure(retry))
            completion?(.success(()))
        default:
            try? fileManager.removeItem(at: originalURL)
            SyncLogger.shared.logUploadFailure(assetId: assetId, error: "HTTP \(http.statusCode)")
            UploadStore.shared.removeFromUploading(assetId)
            onTaskFinished?(assetId, .clientError)
            completion?(.failure(AppError.api(message: APIClient.plainMeaning(of: http.statusCode),
                                              statusCode: http.statusCode)))
        }
    }

    /// HEADs the TUS resource on the **background** session, so a resume that starts while the
    /// app is suspended still runs. A `URLSession.shared` request here would simply never
    /// return once iOS suspends us after `urlSessionDidFinishEvents`, leaving the asset stuck
    /// in `uploading` with no callback to clear it.
    ///
    /// Background sessions accept only upload/download tasks, so this is a download task whose
    /// method is HEAD — the (empty) body is discarded and only `Upload-Offset` is read, in
    /// ``handleHeadFinished(patch:originalURL:error:response:)``.
    private func startHeadForResume(
        assetId: String,
        originalURL: URL,
        uploadURL: URL,
        checksum: String,
        fileSize: Int64,
    ) {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "HEAD"
        request.applyNetworkPolicy()
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        apiFromKeychain().addBasicAuth(to: &request)

        let task = session.downloadTask(with: request)
        // chunkPath == originalPath so the delegate does not delete anything when this ends.
        task.taskDescription = TusTask(
            assetId: assetId,
            chunkPath: originalURL.path,
            uploadURL: uploadURL,
            checksum: checksum,
            originalPath: originalURL.path,
            fileSize: fileSize,
            sentOffset: 0,
            kind: .head,
        ).description
        task.resume()
    }

    /// The resume HEAD came back. Continue from the offset the server kept, or finish.
    private func handleHeadFinished(
        patch: TusTask,
        originalURL: URL,
        error: Error?,
        response: URLResponse?,
    ) {
        let assetId = patch.assetId
        if let error {
            failCreate(assetId: assetId, originalURL: originalURL,
                       message: error.localizedDescription, completion: nil)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            failCreate(assetId: assetId, originalURL: originalURL,
                       message: "no response from HEAD", completion: nil)
            return
        }
        // 404/410: tusd expired the incomplete upload. The next scan will POST a new one.
        guard (200 ... 299).contains(http.statusCode) else {
            failCreate(assetId: assetId, originalURL: originalURL,
                       message: "HEAD /files/ returned \(http.statusCode)", completion: nil)
            return
        }
        let offset = TusChunking.parseOffset(http.value(forHTTPHeaderField: "Upload-Offset")) ?? 0
        let fileSize: Int64
        if patch.fileSize > 0 {
            fileSize = patch.fileSize
        } else {
            do {
                let attrs = try fileManager.attributesOfItem(atPath: originalURL.path)
                fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            } catch {
                failCreate(assetId: assetId, originalURL: originalURL,
                           message: error.localizedDescription, completion: nil)
                return
            }
        }
        guard TusChunking.nextChunk(offset: offset, fileSize: fileSize) != nil else {
            finishSuccessfully(assetId: assetId, originalURL: originalURL,
                               checksum: patch.checksum, completion: nil)
            return
        }
        patchChunk(
            assetId: assetId,
            originalURL: originalURL,
            uploadURL: patch.uploadURL,
            checksum: patch.checksum,
            fileSize: fileSize,
            offset: offset,
            api: apiFromKeychain(),
            completion: nil,
        )
    }

    private func patchChunk(
        assetId: String,
        originalURL: URL,
        uploadURL: URL,
        checksum: String,
        fileSize: Int64,
        offset: Int64,
        api: APIClient,
        completion: (@Sendable (Result<Void, Error>) -> Void)?,
    ) {
        guard let range = TusChunking.nextChunk(offset: offset, fileSize: fileSize) else {
            finishSuccessfully(
                assetId: assetId, originalURL: originalURL, checksum: checksum,
                completion: completion,
            )
            return
        }

        // Slicing copies up to a chunk of bytes. `patchChunk` is called from the URLSession
        // delegate queue when the previous chunk lands, and blocking that queue on file I/O
        // stalls every other callback the session has to deliver — including other uploads'.
        sliceQueue.async { [weak self] in
            guard let self else { return }
            let chunkURL: URL
            let wholeFile = range.lowerBound == 0 && range.upperBound == fileSize
            if wholeFile {
                chunkURL = originalURL
            } else {
                chunkURL = fileManager.temporaryDirectory
                    .appendingPathComponent("tus-chunk-\(UUID().uuidString)")
                do {
                    try TusChunking.writeSlice(from: originalURL, range: range, to: chunkURL)
                } catch {
                    failCreate(assetId: assetId, originalURL: originalURL,
                               message: error.localizedDescription, completion: completion)
                    return
                }
            }
            sendPatch(
                assetId: assetId, originalURL: originalURL, uploadURL: uploadURL,
                checksum: checksum, fileSize: fileSize, range: range, chunkURL: chunkURL,
                api: api, completion: completion,
            )
        }
    }

    /// Puts one prepared chunk on the background session. Split from ``patchChunk`` only so the
    /// slicing above can happen off the delegate queue.
    private func sendPatch(
        assetId: String,
        originalURL: URL,
        uploadURL: URL,
        checksum: String,
        fileSize: Int64,
        range: Range<Int64>,
        chunkURL: URL,
        api: APIClient,
        completion: (@Sendable (Result<Void, Error>) -> Void)?,
    ) {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PATCH"
        request.applyNetworkPolicy()
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(range.lowerBound), forHTTPHeaderField: "Upload-Offset")
        request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
        api.addBasicAuth(to: &request)

        let task = session.uploadTask(with: request, fromFile: chunkURL)
        task.taskDescription = TusTask(
            assetId: assetId,
            chunkPath: chunkURL.path,
            uploadURL: uploadURL,
            checksum: checksum,
            originalPath: originalURL.path,
            fileSize: fileSize,
            sentOffset: range.lowerBound,
            kind: .patch,
        ).description
        task.resume()
        completion?(.success(()))
    }

    private func failCreate(
        assetId: String,
        originalURL: URL,
        message: String,
        completion: (@Sendable (Result<Void, Error>) -> Void)?,
    ) {
        try? fileManager.removeItem(at: originalURL)
        clearResumeAttempts(for: assetId)
        SyncLogger.shared.logUploadFailure(assetId: assetId, error: message)
        UploadStore.shared.removeFromUploading(assetId)
        // The queue-handoff completion already frees the slot. `onTaskFinished` is only for
        // a chunk that died after that handoff (completion is nil).
        if let completion {
            completion(.failure(AppError.api(message: message, statusCode: nil)))
        } else {
            onTaskFinished?(assetId, .transport)
        }
    }

    private func finishSuccessfully(
        assetId: String,
        originalURL: URL,
        checksum: String,
        completion: (@Sendable (Result<Void, Error>) -> Void)?,
    ) {
        clearResumeAttempts(for: assetId)
        try? fileManager.removeItem(at: originalURL)
        UploadStore.shared.markUploaded(assetId, checksum: checksum)
        SyncCoordinator.shared.onUploadedOne(assetId: assetId)
        SyncLogger.shared.logUploadSuccess(assetId: assetId)
        onTaskFinished?(assetId, .success(serverAssetId: nil))
        completion?(.success(()))
    }

    private func clearResumeAttempts(for assetId: String) {
        resumeBudget.clear(assetId)
    }

    private func consumeResumeAttempt(for assetId: String) -> Bool {
        resumeBudget.consume(assetId)
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
        completion: (@Sendable (Result<Void, Error>) -> Void)?,
    ) {
        let assetId = asset.localIdentifier
        discardExport(exp)
        SyncLogger.shared.logUploadSkippedTooLarge(filename: exp.filename, size: size, limit: limit)
        UploadStore.shared.markSkippedTooLarge(
            assetId,
            limit: limit ?? UploadSizeLimit.impliedLimit(forRefusedSize: size),
        )
        onTaskFinished?(assetId, .clientError)
        completion?(.success(()))
    }

    /// Records a refusal for lack of room. Answers `.success` for the same reason the 409-dedupe
    /// path does: a `.failure` routes into SyncCoordinator's export-retry branch and re-queues the
    /// asset every ten seconds, and nothing about the next ten seconds will have made space.
    private func refuseForStorageFull(asset: PHAsset, exp: Uploader.ExportResult, response: Data?) {
        let assetId = asset.localIdentifier
        discardExport(exp)
        SyncLogger.shared.logUploadSkippedStorageFull(
            filename: exp.filename,
            serverMessage: Self.serverMessage(from: response),
        )
        // Deliberately not marked uploaded: the bytes are not on the server, and a later run
        // must try again once the user has made room.
        UploadStore.shared.removeFromUploading(assetId)
        onTaskFinished?(assetId, .clientError)
    }

    /// The server's own sentence, which names both numbers. Falls back to nil rather than to a
    /// guess — an invented limit would send the user deleting the wrong amount.
    static func serverMessage(from data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        if let decoded = try? JSONDecoder().decode(ServerErrorBody.self, from: data),
           let message = decoded.message, !message.isEmpty
        {
            return message
        }
        let raw = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    private struct ServerErrorBody: Decodable {
        let message: String?
    }

    private func resolveLocation(_ location: String, against base: URL) -> URL? {
        if let abs = URL(string: location), abs.scheme != nil {
            return abs
        }
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
        guard let desc = task.taskDescription, let patch = TusTask.parse(desc) else { return }
        let assetId = patch.assetId
        let originalURL = URL(fileURLWithPath: patch.originalPath)

        // The slice is disposable as soon as this task ends. The original stays until the
        // whole file has been accepted — later chunks still need it.
        if patch.chunkPath != patch.originalPath {
            try? fileManager.removeItem(atPath: patch.chunkPath)
        }

        if patch.kind == .head {
            handleHeadFinished(patch: patch, originalURL: originalURL,
                               error: error, response: task.response)
            return
        }

        if patch.kind == .create {
            handleCreateFinished(
                create: patch,
                pending: takePendingCreate(for: assetId),
                error: error,
                response: task.response,
                body: takeCreateBody(for: task.taskIdentifier),
            )
            return
        }

        if let error {
            resumeOrFail(
                assetId: assetId,
                originalURL: originalURL,
                uploadURL: patch.uploadURL,
                checksum: patch.checksum,
                fileSize: patch.fileSize,
                message: error.localizedDescription,
            )
            return
        }
        if let http = task.response as? HTTPURLResponse {
            let code = http.statusCode
            if (200 ... 299).contains(code) {
                let reported = TusChunking.parseOffset(http.value(forHTTPHeaderField: "Upload-Offset"))
                let newOffset = reported ?? patch.fileSize
                if patch.fileSize > 0, newOffset < patch.fileSize {
                    if newOffset <= patch.sentOffset {
                        resumeOrFail(
                            assetId: assetId,
                            originalURL: originalURL,
                            uploadURL: patch.uploadURL,
                            checksum: patch.checksum,
                            fileSize: patch.fileSize,
                            message: "Upload-Offset did not advance",
                        )
                        return
                    }
                    // Bytes landed, so earlier transport errors are behind us: the resume budget
                    // is for a chunk that keeps dying, not a lifetime cap on a 500-chunk video.
                    clearResumeAttempts(for: assetId)
                    patchChunk(
                        assetId: assetId,
                        originalURL: originalURL,
                        uploadURL: patch.uploadURL,
                        checksum: patch.checksum,
                        fileSize: patch.fileSize,
                        offset: newOffset,
                        api: apiFromKeychain(),
                        completion: nil,
                    )
                    return
                }
                finishSuccessfully(
                    assetId: assetId, originalURL: originalURL, checksum: patch.checksum,
                    completion: nil,
                )
            } else if code == 409 {
                resumeOrFail(
                    assetId: assetId,
                    originalURL: originalURL,
                    uploadURL: patch.uploadURL,
                    checksum: patch.checksum,
                    fileSize: patch.fileSize,
                    message: "offset mismatch",
                )
            } else if code == 429 || code == 503 {
                try? fileManager.removeItem(at: originalURL)
                clearResumeAttempts(for: assetId)
                let retry = parseRetryAfter(from: http) ?? 30
                SyncLogger.shared.logUploadDeferred(assetId: assetId, retryAfter: retry)
                UploadStore.shared.removeFromUploading(assetId)
                onTaskFinished?(assetId, .backpressure(retry))
            } else {
                try? fileManager.removeItem(at: originalURL)
                clearResumeAttempts(for: assetId)
                SyncLogger.shared.logUploadFailure(assetId: assetId, error: "HTTP \(code)")
                UploadStore.shared.removeFromUploading(assetId)
                onTaskFinished?(assetId, .clientError)
            }
        } else {
            finishSuccessfully(
                assetId: assetId, originalURL: originalURL, checksum: patch.checksum,
                completion: nil,
            )
        }
    }

    /// A chunk died in transit. HEAD the resource and continue from whatever offset the
    /// server kept, up to ``TusResumeBudget``'s cap of *consecutive* stalls — the budget is
    /// refilled whenever the offset advances. Past that the next scan re-exports.
    private func resumeOrFail(
        assetId: String,
        originalURL: URL,
        uploadURL: URL,
        checksum: String,
        fileSize: Int64,
        message: String,
    ) {
        guard fileManager.fileExists(atPath: originalURL.path), consumeResumeAttempt(for: assetId) else {
            try? fileManager.removeItem(at: originalURL)
            clearResumeAttempts(for: assetId)
            SyncLogger.shared.logUploadFailure(assetId: assetId, error: message)
            UploadStore.shared.removeFromUploading(assetId)
            onTaskFinished?(assetId, .transport)
            return
        }
        AppLog.upload.notice("Resuming after a transport error: \(message, privacy: .public)")
        startHeadForResume(
            assetId: assetId,
            originalURL: originalURL,
            uploadURL: uploadURL,
            checksum: checksum,
            fileSize: fileSize,
        )
    }

    /// The client to retry with, when a background-session callback arrives with no caller
    /// left to hand one over. Anonymous when signed out — see ``SyncCoordinator/api``.
    private func apiFromKeychain() -> APIClient {
        APIClientProvider.shared.clientOrAnonymous
    }

    /// Collects an upload task's response body. Only the create POST has one worth keeping: a
    /// 507 answers with the server's own sentence naming how much room is left, which is the
    /// only thing that makes the log entry actionable. A background session has no per-request
    /// completion handler to hand it to, so it is accumulated here and read once in
    /// ``handleCreateFinished(create:pending:error:response:body:)``.
    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let desc = dataTask.taskDescription,
              TusTask.parse(desc)?.kind == .create else { return }
        appendCreateBody(data, for: dataTask.taskIdentifier)
    }

    /// The resume HEAD is a download task, so the system insists on handing us a file for its
    /// (empty) body. Everything that matters is read from `task.response` in
    /// ``urlSession(_:task:didCompleteWithError:)``.
    func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        try? fileManager.removeItem(at: location)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        onAllBackgroundEventsComplete?(session.configuration.identifier ?? "")
    }
}

/// What kind of request a background task is. Only ``TusTask/kind`` distinguishes them once
/// iOS hands the task back after a relaunch.
private enum TusTaskKind: String {
    case patch = "PATCH"
    case head = "HEAD"
    case create = "POST"
}

/// What a background task needs to carry on after a relaunch.
///
/// `taskDescription` is the only state iOS preserves across a kill. Four-field values from
/// builds that sent the whole file in one PATCH still parse: the original path is the chunk
/// path, a missing file size treats a 2xx as complete, and a missing kind is a PATCH.
///
/// `assetId` stays field 0 because ``TusUploader/getActiveUploadAssetIds(completion:)`` reads it
/// straight off the raw string.
private struct TusTask {
    let assetId: String
    let chunkPath: String
    let uploadURL: URL
    let checksum: String
    let originalPath: String
    let fileSize: Int64
    let sentOffset: Int64
    let kind: TusTaskKind

    var description: String {
        [
            assetId, chunkPath, uploadURL.absoluteString, checksum,
            originalPath, String(fileSize), String(sentOffset), kind.rawValue,
        ]
        .joined(separator: "|")
    }

    static func parse(_ raw: String) -> TusTask? {
        let comps = raw.components(separatedBy: "|")
        guard comps.count >= 4, let uploadURL = URL(string: comps[2]) else { return nil }
        return TusTask(
            assetId: comps[0],
            chunkPath: comps[1],
            uploadURL: uploadURL,
            checksum: comps[3],
            originalPath: comps.count > 4 ? comps[4] : comps[1],
            fileSize: comps.count > 5 ? (Int64(comps[5]) ?? -1) : -1,
            sentOffset: comps.count > 6 ? (Int64(comps[6]) ?? 0) : 0,
            kind: comps.count > 7 ? (TusTaskKind(rawValue: comps[7]) ?? .patch) : .patch,
        )
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
    /// - Parameter checksum: SHA-256 over the exact bytes about to be sent. Sent so the server can
    ///   recognise a photo it already holds from *another* device. `contentId` cannot do that job:
    ///   it is a `PHAsset.localIdentifier`, which an iPhone and an iPad each mint separately for
    ///   their own copy of one iCloud photo. The bytes are the same — ``exportAssetToTempFile``
    ///   writes the untouched original resource — so the hash is what matches. Optional only so an
    ///   older server, which ignores the key, is unaffected.
    func tusUploadMetadata(filename: String, mimeType: String, contentId: String,
                           albumId: Int? = nil, auth: String? = nil,
                           checksum: String? = nil) -> String
    {
        var parts: [(String, String)] = [
            ("filename", filename),
            ("filetype", mimeType),
            ("contentId", contentId),
        ]
        if let checksum, !checksum.isEmpty {
            parts.append(("checksum", checksum))
        }
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
