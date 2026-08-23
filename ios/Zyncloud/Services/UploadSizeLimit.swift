import Foundation

/// The one place that decides whether a file is too big to upload, and the one place that
/// phrases it for a human.
///
/// Extracted rather than left inline for the same reason as ``ExportRetryPolicy`` and
/// ``UploadRouting``: this is a decision with edge cases (limit not yet known, limit of zero,
/// a limit that later grows) and it needs to be testable without a network or a photo library.
///
/// Background — D43. The client uploads the untouched original, so a 4-minute 4K clip is around
/// 1.6 GB. Until 2026-08-23 the server cap was 500 MB, and tusd rejected the `POST /files/`
/// with `413 ERR_MAX_SIZE_EXCEEDED` *before a byte was sent*. The app reported that as
/// "Failed to upload 0AC3F1B2...: HTTP 413", which is true and useless: nothing told the user
/// that their videos were not being backed up, or why. The cap is now 2 GiB, but a cap of any
/// size still needs an answer for the file that does not fit.
enum UploadSizeLimit {
    enum Verdict: Equatable {
        case allowed
        /// The file cannot be uploaded at all. Retrying it unchanged will always fail.
        case tooLarge(size: Int64, limit: Int64)
    }

    /// - Parameter limit: the server's advertised `tus.maxSize`. `nil` or `<= 0` means
    ///   "not known yet" — capabilities have not been fetched, or an older server did not say.
    ///   That is deliberately **not** treated as "no file is allowed": we let the upload run and
    ///   let the server be the judge, exactly as before this check existed. Same three-state
    ///   care as ``UploadRouting/selectPath(userOptedIn:capabilities:)``.
    static func check(size: Int64, limit: Int64?) -> Verdict {
        guard let limit, limit > 0 else { return .allowed }
        return size > limit ? .tooLarge(size: size, limit: limit) : .allowed
    }

    /// Whether an asset previously skipped under `recordedLimit` deserves another try now that
    /// the server advertises `currentLimit`.
    ///
    /// A raised cap must un-stick everything it un-blocks — otherwise the 2 GiB rollout would
    /// leave every already-refused video permanently skipped on the phones that saw the 500 MB
    /// cap, which is the same data loss with a nicer error message.
    static func shouldRetry(recordedLimit: Int64, currentLimit: Int64?) -> Bool {
        guard let currentLimit, currentLimit > 0 else { return true }
        return currentLimit > recordedLimit
    }

    /// One sentence, addressed to the person, naming the file and both numbers.
    ///
    /// Both numbers matter: "too large" alone leaves the user unable to tell a clip that is
    /// slightly over the cap from one that never had a chance. `limit` is optional because a
    /// server 413 can arrive before capabilities have ever been fetched, and a message that
    /// invents a limit it does not know would be worse than one that omits it.
    static func message(filename: String, size: Int64, limit: Int64?) -> String {
        guard let limit, limit > 0 else {
            return "Too big to back up: the server refused \(filename) at \(format(size))."
        }
        return "Too big to back up: \(filename) is \(format(size)), the server accepts up to \(format(limit))."
    }

    /// The limit to record for an asset the server refused without telling us what the cap is.
    ///
    /// One byte under the file's own size: it is the strongest statement the 413 supports — the
    /// real cap was somewhere below this — and it makes ``shouldRetry(recordedLimit:currentLimit:)``
    /// re-admit the file as soon as an advertised cap reaches its size.
    static func impliedLimit(forRefusedSize size: Int64) -> Int64 {
        max(0, size - 1)
    }

    static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
