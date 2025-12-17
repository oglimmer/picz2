import Foundation

struct SyncLogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let isManual: Bool
    let success: Bool
    let message: String

    init(id: UUID = UUID(), timestamp: Date = Date(), isManual: Bool, success: Bool, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.isManual = isManual
        self.success = success
        self.message = message
    }
}
