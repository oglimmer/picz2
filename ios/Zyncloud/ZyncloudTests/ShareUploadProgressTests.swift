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
