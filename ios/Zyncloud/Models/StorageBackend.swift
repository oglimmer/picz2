import Foundation

/// An S3-compatible endpoint an album's photos can live in.
///
/// The site's own storage always appears in the list with `systemDefault == true`; it cannot be
/// edited or removed, and it is the option every album gets unless the owner picks another. The
/// rest belong to the signed-in user, who supplies (and pays for) the bucket.
///
/// The secret access key is never part of this: the server takes it, encrypts it, and never sends
/// it back. An edit form leaves the field empty and the server keeps the stored one.
struct StorageBackend: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let systemDefault: Bool
    let endpoint: String?
    let region: String?
    let bucket: String?
    let accessKey: String?
    let pathStyleAccess: Bool

    /// Albums already stored here. Non-zero means the backend cannot be deleted — those photos
    /// would become unreachable — so the UI explains that rather than offering a broken button.
    let albumCount: Int

    let createdAt: String?

    /// Bytes kept here and the allowance, for the site's own storage only. Both nil on a user's
    /// own bucket: that one is theirs to fill, so there is nothing to meter and nothing to cap.
    /// Optional `var` so a server that predates the quota still decodes.
    var usedBytes: Int64?
    var quotaBytes: Int64?

    /// Whether this backend reports a limit at all. Only the site's own storage does.
    var isMetered: Bool {
        usedBytes != nil && quotaBytes != nil
    }

    /// How full it is, 0...1. A quota of zero is a frozen account, not a divide by zero — it is
    /// full by definition.
    var usedFraction: Double {
        guard let usedBytes, let quotaBytes else { return 0 }
        guard quotaBytes > 0 else { return 1 }
        return min(1, Double(usedBytes) / Double(quotaBytes))
    }

    /// "12.4 MB of 100 MB used", or nil when this backend has no limit.
    var quotaSummary: String? {
        guard let usedBytes, let quotaBytes else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: usedBytes)) of "
            + "\(formatter.string(fromByteCount: quotaBytes)) used"
    }

    /// One line describing where this is, for a list row.
    var subtitle: String {
        if systemDefault {
            return "Provided by this site"
        }
        let host = endpoint ?? "unknown endpoint"
        guard let bucket else { return host }
        return "\(host) · \(bucket)"
    }
}

/// What the add/edit form sends. `secretKey` is omitted when editing without retyping it, which
/// the server reads as "keep the stored one".
struct StorageBackendBody: Encodable {
    let name: String
    let endpoint: String
    let region: String
    let bucket: String
    let accessKey: String
    let secretKey: String?
    let pathStyleAccess: Bool
}

/// Outcome of a connection check. `ok == false` is a normal answer, not a failed request — the
/// server tried a real write/read/delete and is reporting which step went wrong.
struct StorageBackendTestResult: Codable {
    let ok: Bool
    let failedStep: String?
    let message: String?
}
