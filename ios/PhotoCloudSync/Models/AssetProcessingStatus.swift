import Foundation

// Mirrors server-side ProcessingStatus enum + AssetProcessingStatusResponse.
// Used by GET /api/assets/{id}/status, polled after a 202 upload to detect
// post-upload pipeline failures the upload-side 2xx alone can't reveal.
enum AssetProcessingStatus: String, Codable {
    case queued = "QUEUED"
    case processing = "PROCESSING"
    case done = "DONE"
    case failed = "FAILED"
    case deadLetter = "DEAD_LETTER"

    var isTerminal: Bool {
        switch self {
        case .done, .failed, .deadLetter: return true
        case .queued, .processing: return false
        }
    }
}

struct AssetProcessingStatusResponse: Codable {
    let id: Int
    let processingStatus: AssetProcessingStatus
    let attempts: Int?
    let completedAt: String?
    let error: String?
}
