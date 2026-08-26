import Foundation
import Testing
@testable import Zyncloud

/// The share extension's progress bar used to tick once per finished file, so a single video sat
/// at 0% for the whole upload and then jumped to 100%. These pin down the byte-weighted
/// replacement.
struct ShareUploadProgressTests {
    @Test("a lone file drives the bar from its own byte count")
    func singleFileTracksBytes() {
        var progress = ShareUploadProgress(fileSizes: [1000])

        #expect(progress.fraction == 0)

        progress.noteBytesSent(250)
        #expect(abs(progress.fraction - 0.25) < 0.0001)

        progress.noteBytesSent(1000)
        #expect(abs(progress.fraction - 1.0) < 0.0001)
    }

    @Test("files are weighted by size, not counted equally")
    func weightsBySize() {
        // 1 MB photo + 99 MB video. Finishing the photo must not claim half the work.
        var progress = ShareUploadProgress(fileSizes: [1_000_000, 99_000_000])

        progress.finishCurrentItem()
        #expect(abs(progress.fraction - 0.01) < 0.0001)

        progress.noteBytesSent(49_500_000)
        #expect(abs(progress.fraction - 0.505) < 0.0001)
    }

    @Test("a retried body does not walk the bar backwards")
    func monotonicWithinAFile() {
        var progress = ShareUploadProgress(fileSizes: [1000])

        progress.noteBytesSent(800)
        progress.noteBytesSent(0) // URLSession restarting the body from offset 0
        #expect(abs(progress.fraction - 0.8) < 0.0001)
    }

    @Test("a failed file still retires its weight")
    func failedItemAdvances() {
        var progress = ShareUploadProgress(fileSizes: [500, 500])

        progress.noteBytesSent(120)
        progress.finishCurrentItem() // gave up on this one
        #expect(abs(progress.fraction - 0.5) < 0.0001)

        // The next file starts from the boundary, not from the abandoned file's byte count.
        progress.noteBytesSent(250)
        #expect(abs(progress.fraction - 0.75) < 0.0001)
    }

    @Test("over-reported bytes cannot push past the file boundary")
    func clampsToWeight() {
        var progress = ShareUploadProgress(fileSizes: [100, 100])

        progress.noteBytesSent(9999)
        #expect(abs(progress.fraction - 0.5) < 0.0001)
    }

    @Test("zero-byte files still make the bar move")
    func zeroSizedFilesGetWeight() {
        var progress = ShareUploadProgress(fileSizes: [0, 0])

        progress.finishCurrentItem()
        #expect(abs(progress.fraction - 0.5) < 0.0001)

        progress.finishCurrentItem()
        #expect(abs(progress.fraction - 1.0) < 0.0001)
    }

    @Test("finishing more items than exist is harmless")
    func overRunIsSafe() {
        var progress = ShareUploadProgress(fileSizes: [10])

        progress.finishCurrentItem()
        progress.finishCurrentItem()
        #expect(abs(progress.fraction - 1.0) < 0.0001)
    }

    @Test("an empty share reads as 0, not as done")
    func emptyShare() {
        let progress = ShareUploadProgress(fileSizes: [])
        #expect(progress.fraction == 0)
    }
}

/// Mixed-batch reporting. A share that landed 2 of 3 used to complete as `.failure` and invite
/// a full retry that duplicated the two that had already arrived.
struct ShareUploadOutcomeTests {
    @Test func aCleanShareReportsACount() {
        let outcome = ShareUploadOutcome(uploaded: 3, failed: 0, lastErrorDescription: nil)
        #expect(outcome.allSucceeded)
        #expect(outcome.userMessage == "Uploaded 3 items")
    }

    @Test func aSingleItemDoesNotPluralize() {
        let outcome = ShareUploadOutcome(uploaded: 1, failed: 0, lastErrorDescription: nil)
        #expect(outcome.userMessage == "Uploaded 1 item")
    }

    @Test func aTotalFailureNamesTheError() {
        let outcome = ShareUploadOutcome(
            uploaded: 0, failed: 2, lastErrorDescription: "POST /files/ returned 413",
        )
        #expect(!outcome.allSucceeded)
        #expect(outcome.userMessage == "Upload failed: POST /files/ returned 413")
    }

    @Test func aMixedBatchKeepsTheSuccessCount() {
        let outcome = ShareUploadOutcome(
            uploaded: 2, failed: 1, lastErrorDescription: "Too big to back up: clip.mov is 3 GB, the server accepts up to 2 GB",
        )
        #expect(!outcome.allSucceeded)
        #expect(outcome.userMessage.contains("Uploaded 2 of 3"))
        #expect(outcome.userMessage.contains("1 failed"))
        #expect(outcome.userMessage.contains("clip.mov"))
    }
}

/// The skip list may only carry over to a genuine retry — the same files again. A partly
/// overlapping share that inherited it reported the shared files as uploaded without sending
/// a byte.
struct ShareRetryBatchTests {
    private func urls(_ names: [String]) -> Set<URL> {
        Set(names.map { URL(fileURLWithPath: "/tmp/\($0)") })
    }

    @Test func theSameFilesAgainIsARetry() {
        #expect(ShareRetryBatch.isRetry(of: urls(["a", "b"]), incoming: urls(["b", "a"])))
    }

    @Test func aDisjointShareIsNotARetry() {
        #expect(!ShareRetryBatch.isRetry(of: urls(["a", "b"]), incoming: urls(["c"])))
    }

    @Test func aPartlyOverlappingShareIsNotARetry() {
        #expect(!ShareRetryBatch.isRetry(of: urls(["a", "b"]), incoming: urls(["a", "c"])))
    }

    @Test func aSubsetIsNotARetry() {
        #expect(!ShareRetryBatch.isRetry(of: urls(["a", "b"]), incoming: urls(["a"])))
        #expect(!ShareRetryBatch.isRetry(of: urls(["a"]), incoming: urls(["a", "b"])))
    }

    @Test func theFirstShareOfASessionIsNotARetry() {
        #expect(!ShareRetryBatch.isRetry(of: [], incoming: urls(["a"])))
        #expect(!ShareRetryBatch.isRetry(of: [], incoming: []))
    }
}
