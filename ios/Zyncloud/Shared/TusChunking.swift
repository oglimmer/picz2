import Foundation

/// How a TUS PATCH is sliced, and how the server's `Upload-Offset` is read.
///
/// A single PATCH of a multi-gigabyte original dies on Traefik's 60s `readTimeout` and used
/// to restart from byte 0 (`Upload-Offset: 0` hardcoded). Chunking plus HEAD-then-PATCH from
/// the reported offset is what makes a large video actually land. Extracted so the decision
/// can be tested without a `URLSession`.
enum TusChunking {
    /// 4 MiB. Traefik's default `readTimeout` is 60s; 4 MiB in 60s is ~0.53 Mbit/s, slow enough
    /// that a 2 GiB single PATCH cannot finish on a normal connection, and large enough that a
    /// 4-minute clip is tens of requests rather than thousands.
    static let defaultChunkSize: Int64 = 4 * 1024 * 1024

    /// The next byte range to PATCH, or `nil` when the server already has the whole file.
    static func nextChunk(
        offset: Int64,
        fileSize: Int64,
        chunkSize: Int64 = defaultChunkSize
    ) -> Range<Int64>? {
        guard offset >= 0, fileSize >= 0, chunkSize > 0, offset < fileSize else { return nil }
        let remaining = fileSize - offset
        let length = min(chunkSize, remaining)
        guard length > 0 else { return nil }
        return offset ..< (offset + length)
    }

    /// TUS `Upload-Offset` is a decimal integer. `nil`/blank/negative/`NaN` must not become a
    /// seek position — same care as `parseRetryAfter`.
    static func parseOffset(_ value: String?) -> Int64? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let offset = Int64(raw), offset >= 0
        else { return nil }
        return offset
    }

    /// Copies `range` of `source` into `destination`. The caller owns the destination and
    /// deletes it. A range covering the whole file is still copied — callers that want to
    /// PATCH the original in place should skip this and send `source` itself.
    static func writeSlice(from source: URL, range: Range<Int64>, to destination: URL) throws {
        let length = range.upperBound - range.lowerBound
        guard length > 0 else {
            throw NSError(
                domain: "TusChunking",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "empty slice"],
            )
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        fileManager.createFile(atPath: destination.path, contents: nil)

        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        try reader.seek(toOffset: UInt64(range.lowerBound))

        let writer = try FileHandle(forWritingTo: destination)
        defer { try? writer.close() }

        var remaining = length
        let bufferSize = 64 * 1024
        while remaining > 0 {
            let n = Int(min(Int64(bufferSize), remaining))
            guard let data = try reader.read(upToCount: n), !data.isEmpty else {
                throw NSError(
                    domain: "TusChunking",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "short read while slicing"],
                )
            }
            try writer.write(contentsOf: data)
            remaining -= Int64(data.count)
        }
    }
}

/// How many *consecutive* stalls one file may survive before the upload is abandoned.
///
/// The counter is per asset and must be cleared every time the server's `Upload-Offset`
/// advances. Without that clear it degenerates into a per-file lifetime cap: a 2 GiB video is
/// ~500 chunks, and three dropped chunks spread over an hour on a phone is ordinary — the file
/// would be re-exported from byte 0 for no good reason.
///
/// Extracted from ``TusUploader`` for the same reason as ``TusChunking``: it is a decision with
/// edge cases, and it should be testable without a `URLSession`.
final class TusResumeBudget {
    private var attempts: [String: Int] = [:]
    private let lock = NSLock()
    private let maxAttempts: Int

    init(maxAttempts: Int = 3) {
        self.maxAttempts = maxAttempts
    }

    /// Spends one attempt. `false` means the budget is gone and the caller must give up.
    func consume(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let used = attempts[key, default: 0]
        guard used < maxAttempts else { return false }
        attempts[key] = used + 1
        return true
    }

    /// Refills the budget. Call on every advance of the offset, and on every terminal outcome.
    func clear(_ key: String) {
        lock.lock()
        attempts[key] = nil
        lock.unlock()
    }
}
