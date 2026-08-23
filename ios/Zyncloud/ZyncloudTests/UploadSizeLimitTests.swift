import Foundation
import Testing
@testable import Zyncloud

/// D43 — the file that is too big to back up.
///
/// The whole point of this type is that a refusal must be *legible* and must not become
/// permanent by accident, so the tests are about the two edges rather than the happy path:
/// an unknown limit must not refuse anything, and a raised limit must un-refuse what it admits.
struct UploadSizeLimitTests {
    private let twoGiB: Int64 = 2_147_483_648
    private let fiveHundredMB: Int64 = 524_288_000

    // MARK: - check

    @Test func `a file under the limit is allowed`() {
        #expect(UploadSizeLimit.check(size: 100_000_000, limit: fiveHundredMB) == .allowed)
    }

    @Test func `a file exactly at the limit is allowed`() {
        // tusd rejects `Upload-Length > MaxSize`, so equality must pass here too — refusing it
        // locally would make the client stricter than the server for no reason.
        #expect(UploadSizeLimit.check(size: fiveHundredMB, limit: fiveHundredMB) == .allowed)
    }

    @Test func `a file one byte over the limit is refused`() {
        #expect(UploadSizeLimit.check(size: fiveHundredMB + 1, limit: fiveHundredMB)
            == .tooLarge(size: fiveHundredMB + 1, limit: fiveHundredMB))
    }

    /// The three-state rule. "We have not asked the server yet" is not "the server said no":
    /// refusing on an unknown limit would block every upload made before the first
    /// `/api/capabilities` response lands.
    @Test(arguments: [nil, Int64(0), Int64(-1)])
    func `an unknown or nonsense limit allows everything`(limit: Int64?) {
        #expect(UploadSizeLimit.check(size: 9_000_000_000, limit: limit) == .allowed)
    }

    // MARK: - shouldRetry

    /// The 500 MB → 2 GiB rollout in one assertion: a video refused under the old cap must be
    /// picked up again once the new cap is advertised, without the user doing anything.
    @Test func `raising the server cap unsticks A previously refused file`() {
        #expect(UploadSizeLimit.shouldRetry(recordedLimit: fiveHundredMB, currentLimit: twoGiB))
    }

    @Test func `an unchanged cap keeps the file skipped`() {
        #expect(!UploadSizeLimit.shouldRetry(recordedLimit: twoGiB, currentLimit: twoGiB))
    }

    @Test func `a lowered cap keeps the file skipped`() {
        #expect(!UploadSizeLimit.shouldRetry(recordedLimit: twoGiB, currentLimit: fiveHundredMB))
    }

    /// Forgetting the limit (fresh install, cleared settings) retries rather than skips. The
    /// cost of being wrong is one wasted export; the cost of the opposite is a video that is
    /// never backed up and never mentioned again.
    @Test func `an unknown current cap retries`() {
        #expect(UploadSizeLimit.shouldRetry(recordedLimit: fiveHundredMB, currentLimit: nil))
        #expect(UploadSizeLimit.shouldRetry(recordedLimit: fiveHundredMB, currentLimit: 0))
    }

    // MARK: - impliedLimit

    /// A 413 with no advertised cap still tells us something: the cap is below this file. The
    /// recorded value must therefore let any cap >= the file's size re-admit it.
    @Test func `an implied limit is beaten by A cap that would fit the file`() {
        let size: Int64 = 1_600_000_000
        let implied = UploadSizeLimit.impliedLimit(forRefusedSize: size)
        #expect(!UploadSizeLimit.shouldRetry(recordedLimit: implied, currentLimit: size - 1))
        #expect(UploadSizeLimit.shouldRetry(recordedLimit: implied, currentLimit: size))
        #expect(UploadSizeLimit.shouldRetry(recordedLimit: implied, currentLimit: twoGiB))
    }

    @Test func `an implied limit never goes negative`() {
        #expect(UploadSizeLimit.impliedLimit(forRefusedSize: 0) == 0)
    }

    // MARK: - message

    /// "HTTP 413" is what this replaced. The replacement is only worth anything if it names the
    /// file and both numbers, so that is asserted rather than assumed.
    @Test func `the message names the file and both sizes`() {
        let text = UploadSizeLimit.message(filename: "IMG_4021.MOV", size: 1_600_000_000, limit: twoGiB)
        #expect(text.contains("IMG_4021.MOV"))
        #expect(text.contains(UploadSizeLimit.format(1_600_000_000)))
        #expect(text.contains(UploadSizeLimit.format(twoGiB)))
    }

    /// With no known cap the sentence must not invent one — a wrong number here is worse than
    /// a missing one, because the user would trim the clip to the wrong size.
    @Test func `the message omits A limit it does not know`() {
        let text = UploadSizeLimit.message(filename: "IMG_4021.MOV", size: 1_600_000_000, limit: nil)
        #expect(text.contains("IMG_4021.MOV"))
        #expect(text.contains(UploadSizeLimit.format(1_600_000_000)))
        #expect(!text.contains("accepts up to"))
    }
}
