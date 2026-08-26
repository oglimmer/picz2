import Foundation
import Testing
@testable import Zyncloud

/// D43 — PATCH from the server's offset, in chunks small enough to survive Traefik's 60s
/// `readTimeout`. The production uploaders only send what this type returns.
struct TusChunkingTests {
    private let fourMiB: Int64 = 4 * 1024 * 1024

    // MARK: - nextChunk

    @Test func theFirstChunkStartsAtZero() {
        let range = TusChunking.nextChunk(offset: 0, fileSize: 10_000_000, chunkSize: fourMiB)
        #expect(range == 0 ..< fourMiB)
    }

    @Test func aMiddleChunkContinuesFromTheOffset() {
        let range = TusChunking.nextChunk(offset: fourMiB, fileSize: 10_000_000, chunkSize: fourMiB)
        #expect(range == fourMiB ..< (2 * fourMiB))
    }

    @Test func theLastChunkIsShorterThanTheCap() {
        let fileSize: Int64 = 10_000_000
        let offset: Int64 = 8 * 1024 * 1024
        let range = TusChunking.nextChunk(offset: offset, fileSize: fileSize, chunkSize: fourMiB)
        #expect(range == offset ..< fileSize)
    }

    @Test func aFinishedUploadHasNoNextChunk() {
        #expect(TusChunking.nextChunk(offset: 100, fileSize: 100) == nil)
        #expect(TusChunking.nextChunk(offset: 101, fileSize: 100) == nil)
    }

    @Test func aFileSmallerThanTheChunkIsOnePatch() {
        let range = TusChunking.nextChunk(offset: 0, fileSize: 1234, chunkSize: fourMiB)
        #expect(range == 0 ..< 1234)
    }

    @Test(arguments: [
        (offset: Int64(-1), fileSize: Int64(100), chunkSize: Int64(10)),
        (offset: Int64(0), fileSize: Int64(-1), chunkSize: Int64(10)),
        (offset: Int64(0), fileSize: Int64(100), chunkSize: Int64(0)),
        (offset: Int64(0), fileSize: Int64(100), chunkSize: Int64(-4)),
        (offset: Int64(0), fileSize: Int64(0), chunkSize: Int64(10)),
    ])
    func nonsenseInputsProduceNoChunk(offset: Int64, fileSize: Int64, chunkSize: Int64) {
        #expect(TusChunking.nextChunk(offset: offset, fileSize: fileSize, chunkSize: chunkSize) == nil)
    }

    // MARK: - parseOffset

    @Test func aDecimalOffsetParses() {
        #expect(TusChunking.parseOffset("0") == 0)
        #expect(TusChunking.parseOffset("4096") == 4096)
        #expect(TusChunking.parseOffset(" 12 ") == 12)
    }

    @Test(arguments: [nil as String?, "", "   ", "NaN", "inf", "-1", "1.5", "abc"])
    func malformedOffsetsAreRejected(value: String?) {
        #expect(TusChunking.parseOffset(value) == nil)
    }

    // MARK: - writeSlice

    @Test func aSliceIsTheRequestedByteRange() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("tus-src-\(UUID().uuidString)")
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("tus-dst-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: dest)
        }

        let bytes = Data((0 ..< 200).map { UInt8($0) })
        try bytes.write(to: source)

        try TusChunking.writeSlice(from: source, range: 50 ..< 80, to: dest)
        let sliced = try Data(contentsOf: dest)
        #expect(sliced == Data(bytes[50 ..< 80]))
    }
}

/// D43 — the resume budget counts *consecutive* stalls. Before this was clear-on-progress it
/// was a per-file lifetime cap, and a 500-chunk video died on its third dropped chunk.
struct TusResumeBudgetTests {
    @Test func aFreshAssetMayResume() {
        let budget = TusResumeBudget(maxAttempts: 3)
        #expect(budget.consume("a"))
    }

    @Test func theBudgetRunsOutAfterTheCap() {
        let budget = TusResumeBudget(maxAttempts: 3)
        #expect(budget.consume("a"))
        #expect(budget.consume("a"))
        #expect(budget.consume("a"))
        #expect(!budget.consume("a"))
    }

    @Test func progressRefillsTheBudget() {
        let budget = TusResumeBudget(maxAttempts: 3)
        #expect(budget.consume("a"))
        #expect(budget.consume("a"))
        budget.clear("a") // a chunk landed
        #expect(budget.consume("a"))
        #expect(budget.consume("a"))
        #expect(budget.consume("a"))
        #expect(!budget.consume("a"))
    }

    @Test func assetsDoNotShareABudget() {
        let budget = TusResumeBudget(maxAttempts: 1)
        #expect(budget.consume("a"))
        #expect(!budget.consume("a"))
        #expect(budget.consume("b"))
    }

    @Test func aBudgetOfZeroNeverResumes() {
        let budget = TusResumeBudget(maxAttempts: 0)
        #expect(!budget.consume("a"))
    }
}
