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
        logs.removeAll()
        saveLogs()
    }

    // MARK: - Private Methods

    private func addLog(isManual: Bool, success: Bool, message: String) {
        let logEntry = SyncLogEntry(isManual: isManual, success: success, message: message)

        // Insert at beginning for newest-first display
        logs.insert(logEntry, at: 0)

        // Trim to max logs
        if logs.count > maxLogs {
            logs = Array(logs.prefix(maxLogs))
        }

        saveLogs()

        // Also print to console for debugging
        let prefix = isManual ? "Manual" : "Background"
        let status = success ? "✓" : "✗"
        print("[\(prefix)] \(status) \(message)")
    }

    private func loadLogs() {
        if let data = UserDefaults.standard.data(forKey: logsKey),
           let decodedLogs = try? JSONDecoder().decode([SyncLogEntry].self, from: data)
        {
            logs = decodedLogs
        }
    }

    private func saveLogs() {
        if let encoded = try? JSONEncoder().encode(logs) {
            UserDefaults.standard.set(encoded, forKey: logsKey)
        }
    }
}
