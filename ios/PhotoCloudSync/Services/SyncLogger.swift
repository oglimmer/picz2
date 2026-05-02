import Combine
import Foundation
import SwiftUI

class SyncLogger: ObservableObject {
    static let shared = SyncLogger()

    @Published var logs: [SyncLogEntry] = []

    private let logsKey = "sync_logs"
    private let maxLogs = 100 // Keep last 100 logs

    private init() {
        loadLogs()
    }

    // MARK: - Public Methods

    func logUploadSuccess(assetId: String) {
        let message = "Uploaded photo \(assetId.prefix(8))..."
        addLog(isManual: false, success: true, message: message)
    }

    func logUploadFailure(assetId: String, error: String) {
        let message = "Failed to upload \(assetId.prefix(8))...: \(error)"
        addLog(isManual: false, success: false, message: message)
    }

    // Server asked us to back off (HTTP 429/503). Not a failure — the upload
    // will be retried automatically after the given delay, so render this
    // as an informational success-styled entry rather than a red error.
    func logUploadDeferred(assetId: String, retryAfter: TimeInterval) {
        let message = "Server busy, will retry \(assetId.prefix(8))... in \(Int(retryAfter))s"
        addLog(isManual: false, success: true, message: message)
    }

    // Worker-pod processing landed on FAILED / DEAD_LETTER after the upload
    // 2xx. The bytes are on the server but no thumbnails / transcoded variants
    // exist, so the asset will not appear in gallery — surface this so the
    // user knows to investigate.
    func logProcessingFailure(assetId: String, error: String) {
        let message = "Processing failed for \(assetId.prefix(8))...: \(error)"
        addLog(isManual: false, success: false, message: message)
    }

    // Polling exhausted its 60 s budget without seeing a terminal status. Not
    // a failure — the worker may still be catching up — but worth logging so
    // the user sees that the asset isn't necessarily ready in gallery yet.
    func logProcessingTimeout(assetId: String) {
        let message = "Still processing \(assetId.prefix(8))... on server"
        addLog(isManual: false, success: true, message: message)
    }

    // TUS pre-create returned 409: server already has a row for this contentId.
    // Bytes weren't transferred this run — log informationally so the user sees
    // "this one was already on the server" instead of nothing at all.
    func logUploadDeduped(assetId: String) {
        let message = "Already on server: \(assetId.prefix(8))..."
        addLog(isManual: false, success: true, message: message)
    }

    // TUS bytes landed (PATCH 2xx logged via logUploadSuccess), but the follow-up
    // contentId → serverAssetId lookup exhausted its retries. Processing-status
    // polling is disabled for this asset, so any FAILED / DEAD_LETTER outcome
    // won't surface. Log informationally so the user knows the asset uploaded
    // but post-upload visibility is degraded for this one.
    func logProcessingStatusUnavailable(assetId: String) {
        let message = "Processing status unavailable for \(assetId.prefix(8))..."
        addLog(isManual: false, success: true, message: message)
    }

    func logBackgroundSync(success: Bool, message: String) {
        addLog(isManual: false, success: success, message: "Background sync: \(message)")
    }

    func logBackgroundTask(taskType: String, message: String) {
        addLog(isManual: false, success: true, message: "\(taskType): \(message)")
    }

    func logManualSync(success: Bool, message: String) {
        addLog(isManual: true, success: success, message: "Manual sync: \(message)")
    }

    func clearLogs() {
        runOnMain { [weak self] in
            self?.logs.removeAll()
            self?.saveLogs()
        }
    }

    // MARK: - Private Methods

    private func addLog(isManual: Bool, success: Bool, message: String) {
        let logEntry = SyncLogEntry(isManual: isManual, success: success, message: message)

        // Print to console immediately so background-thread call sites still log
        // synchronously even if the published mutation is hopped to main.
        let prefix = isManual ? "Manual" : "Background"
        let status = success ? "✓" : "✗"
        print("[\(prefix)] \(status) \(message)")

        runOnMain { [weak self] in
            guard let self else { return }
            self.logs.insert(logEntry, at: 0)
            if self.logs.count > self.maxLogs {
                self.logs = Array(self.logs.prefix(self.maxLogs))
            }
            self.saveLogs()
        }
    }

    private func loadLogs() {
        guard let data = UserDefaults.standard.data(forKey: logsKey),
              let decodedLogs = try? JSONDecoder().decode([SyncLogEntry].self, from: data)
        else { return }
        runOnMain { [weak self] in
            self?.logs = decodedLogs
        }
    }

    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func saveLogs() {
        if let encoded = try? JSONEncoder().encode(logs) {
            UserDefaults.standard.set(encoded, forKey: logsKey)
        }
    }
}
