import Foundation

/// `GET /api/storage-usage`: how full the signed-in account's share of the site's own storage is.
///
/// `full` is the server's verdict — the same rule the upload path enforces with a 507 — and is
/// what the persistent banner keys on. The app never decides it from the two numbers itself, so
/// what is shown cannot drift from what is refused.
struct StorageUsage: Codable, Equatable, Sendable {
    let usedBytes: Int64
    let quotaBytes: Int64
    let remainingBytes: Int64
    let full: Bool

    /// "100 MB of 100 MB used", for the banner's second line.
    var summary: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: usedBytes)) of "
            + "\(formatter.string(fromByteCount: quotaBytes)) used"
    }

    /// What an uploader assumes the moment it is refused with 507, before the poll has answered:
    /// full, numbers unknown. Replaced by the real row on the next successful fetch.
    static let assumedFull = StorageUsage(usedBytes: 0, quotaBytes: 0, remainingBytes: 0, full: true)
}
