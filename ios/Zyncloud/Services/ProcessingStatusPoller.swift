import Foundation

// Polls GET /api/assets/{id}/status after a 202 upload completes.
//
// The upload-side 2xx only tells us the bytes landed; the worker pod still has
// to finish thumbnailing / transcoding / HEIC conversion before the asset
// shows up in gallery. If that pipeline FAILs (or hits DEAD_LETTER after
// max_attempts), the upload-side log entry alone gives no signal — this poller
// closes that gap and surfaces post-upload failures via SyncLogger.
//
// Happy path is intentionally silent: DONE doesn't emit a log entry, since the
// existing "Uploaded photo …" entry already reads as success to the user.
// Only FAILED / DEAD_LETTER / poll-timeout produce new entries.
final class ProcessingStatusPoller {
    static let shared = ProcessingStatusPoller()

    // 2 s interval, 60 s cap. Matches the web frontend's rotate-poll cadence
    // (see GalleryView.vue post-rotate poll).
    private let interval: TimeInterval = 2
    private let timeout: TimeInterval = 60

    private let queue = DispatchQueue(label: "com.oglimmer.photosync.poller", qos: .utility)
    private var inFlight: Set<Int> = [] // server asset ids currently being polled

    private init() {}

    func poll(serverAssetId: Int, contentId: String, api: APIClient) {
        queue.async {
            // Idempotent: don't double-poll the same asset (e.g. if upload
            // delegate fires twice on app relaunch).
            guard !self.inFlight.contains(serverAssetId) else { return }
            self.inFlight.insert(serverAssetId)
            self.tick(serverAssetId: serverAssetId, contentId: contentId, api: api, deadline: Date().addingTimeInterval(self.timeout))
        }
    }

    private func tick(serverAssetId: Int, contentId: String, api: APIClient, deadline: Date) {
        api.getAssetStatus(id: serverAssetId) { [weak self] result in
            guard let self else { return }
            self.queue.async {
                switch result {
                case let .success(response):
                    if response.processingStatus.isTerminal {
                        self.inFlight.remove(serverAssetId)
                        self.handleTerminal(response: response, contentId: contentId)
                    } else if Date() >= deadline {
                        self.inFlight.remove(serverAssetId)
                        SyncLogger.shared.logProcessingTimeout(assetId: contentId)
                    } else {
                        self.queue.asyncAfter(deadline: .now() + self.interval) {
                            self.tick(serverAssetId: serverAssetId, contentId: contentId, api: api, deadline: deadline)
                        }
                    }
                case let .failure(error):
                    // Transient network errors: keep polling until the deadline,
                    // don't escalate into a user-visible failure entry.
                    if Date() >= deadline {
                        self.inFlight.remove(serverAssetId)
                        print("ProcessingStatusPoller: giving up on \(serverAssetId) after \(self.timeout)s, last error: \(error)")
                    } else {
                        self.queue.asyncAfter(deadline: .now() + self.interval) {
                            self.tick(serverAssetId: serverAssetId, contentId: contentId, api: api, deadline: deadline)
                        }
                    }
                }
            }
        }
    }

    private func handleTerminal(response: AssetProcessingStatusResponse, contentId: String) {
        switch response.processingStatus {
        case .done:
            // Silent: the upload-success log already covered this for the user.
            break
        case .failed, .deadLetter:
            let detail = response.error ?? response.processingStatus.rawValue
            SyncLogger.shared.logProcessingFailure(assetId: contentId, error: detail)
        case .queued, .processing:
            break // unreachable — guarded by isTerminal
        }
    }
}
