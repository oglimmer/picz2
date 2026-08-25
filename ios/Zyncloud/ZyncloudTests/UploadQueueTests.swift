import Foundation
import Testing

@testable import Zyncloud

/// The rules ``SyncCoordinator`` uploads by: how many at once, what happens to an asset the
/// server pushed back, and what happens to one whose export failed.
///
/// These were unreachable until the bookkeeping came out of the coordinator — every path into
/// them needed a live `PHAsset`. They are the rules that decide whether a backup finishes, so
/// they are worth more coverage than the rest of the sync path put together.
struct UploadQueueTests {
    private struct Asset: UploadQueueItem, Equatable {
        let uploadQueueId: String
    }

    private func assets(_ ids: [String]) -> [Asset] {
        ids.map { Asset(uploadQueueId: $0) }
    }

    private func makeQueue(max: Int = 3) -> UploadQueue<Asset> {
        UploadQueue<Asset>(maxInFlight: max)
    }

    private func ids(_ items: [Asset]) -> [String] {
        items.map(\.uploadQueueId)
    }

    // MARK: - Enqueuing

    @Test func afreshQueueIsEmpty() {
        let queue = makeQueue()

        #expect(queue.isEmpty)
        #expect(queue.pendingCount == 0)
        #expect(queue.inFlightCount == 0)
        #expect(queue.freeSlots == 3)
    }

    @Test func enqueuingAddsToTheBackAndAnswersWithWhatWasAdded() {
        var queue = makeQueue()

        let added = queue.enqueue(assets(["a", "b", "c"]))

        #expect(ids(added) == ["a", "b", "c"])
        #expect(ids(queue.pending) == ["a", "b", "c"])
    }

    /// A re-scan hands the whole library over again. Anything already waiting must not be
    /// queued a second time, or it uploads twice.
    @Test func analreadyQueuedAssetIsNotQueuedAgain() {
        var queue = makeQueue()
        queue.enqueue(assets(["a", "b"]))

        let added = queue.enqueue(assets(["a", "b", "c"]))

        #expect(ids(added) == ["c"])
        #expect(ids(queue.pending) == ["a", "b", "c"])
    }

    /// The same holds for one that is already uploading — it is not in `pending` any more, so
    /// only checking there would let it back in behind its own upload.
    @Test func anassetAlreadyUploadingIsNotQueuedAgain() {
        var queue = makeQueue(max: 1)
        queue.enqueue(assets(["a", "b"]))
        _ = queue.startNext() // "a" is now in flight

        let added = queue.enqueue(assets(["a"]))

        #expect(added.isEmpty)
        #expect(queue.contains("a"))
        #expect(ids(queue.pending) == ["b"])
    }

    /// A scan can legitimately produce the same asset twice in one batch. Collapsing it here is
    /// cheaper than discovering the duplicate after both uploads have started.
    @Test func repeatsInsideOneBatchAreCollapsed() {
        var queue = makeQueue()

        let added = queue.enqueue(assets(["a", "b", "a", "a", "c", "b"]))

        #expect(ids(added) == ["a", "b", "c"])
        #expect(ids(queue.pending) == ["a", "b", "c"])
    }

    @Test func enqueuingNothingIsHarmless() {
        var queue = makeQueue()
        queue.enqueue(assets(["a"]))

        #expect(queue.enqueue([]).isEmpty)
        #expect(ids(queue.pending) == ["a"])
    }

    // MARK: - The concurrency cap

    /// The cap is the whole reason this type exists: the server must never be handed more than
    /// `maxInFlight` uploads at a time, however many are waiting.
    @Test func startingNeverExceedsTheCap() {
        var queue = makeQueue(max: 3)
        queue.enqueue(assets(["a", "b", "c", "d", "e", "f"]))

        let batch = queue.startNext()

        #expect(ids(batch) == ["a", "b", "c"])
        #expect(queue.inFlightCount == 3)
        #expect(queue.freeSlots == 0)
        #expect(ids(queue.pending) == ["d", "e", "f"])
    }

    /// A full queue starts nothing. This is what stops a burst of callbacks each launching
    /// another upload on top of a cap that is already met.
    @Test func afullQueueStartsNothing() {
        var queue = makeQueue(max: 2)
        queue.enqueue(assets(["a", "b", "c"]))
        _ = queue.startNext()

        #expect(queue.startNext().isEmpty)
        #expect(queue.inFlightCount == 2)
        #expect(ids(queue.pending) == ["c"])
    }

    /// Fewer waiting than there are slots is not an error — it starts what there is.
    @Test func startingTakesWhatIsThereWhenThatIsLessThanTheCap() {
        var queue = makeQueue(max: 5)
        queue.enqueue(assets(["a", "b"]))

        #expect(ids(queue.startNext()) == ["a", "b"])
        #expect(queue.freeSlots == 3)
        #expect(queue.pending.isEmpty)
    }

    @Test func startingAnEmptyQueueYieldsNothing() {
        var queue = makeQueue()

        #expect(queue.startNext().isEmpty)
        #expect(queue.isEmpty)
    }

    /// Uploads are handed over one-per-completion. Each finish frees exactly one slot, so the
    /// number in flight sits at the cap for as long as there is a backlog.
    @Test func oneFinishReleasesExactlyOneSlot() {
        var queue = makeQueue(max: 3)
        queue.enqueue(assets(["a", "b", "c", "d", "e"]))
        _ = queue.startNext()

        queue.finish("b")

        #expect(queue.inFlightCount == 2)
        #expect(ids(queue.startNext()) == ["d"])
        #expect(queue.inFlightCount == 3)
    }

    /// Drained end to end, every asset goes out exactly once and in the order it was queued.
    @Test func awholeBacklogDrainsInOrderAndOnlyOnce() {
        var queue = makeQueue(max: 3)
        let wanted = (0 ..< 20).map { "asset-\($0)" }
        queue.enqueue(assets(wanted))

        var started: [String] = []
        while true {
            let batch = queue.startNext()
            if batch.isEmpty { break }
            #expect(queue.inFlightCount <= 3, "the cap was breached")
            for item in batch {
                started.append(item.uploadQueueId)
                queue.finish(item.uploadQueueId)
            }
        }

        #expect(started == wanted)
        #expect(queue.isEmpty)
    }

    // MARK: - Finishing

    @Test func finishingHandsTheItemBack() {
        var queue = makeQueue()
        queue.enqueue(assets(["a"]))
        _ = queue.startNext()

        #expect(queue.finish("a") == Asset(uploadQueueId: "a"))
        #expect(queue.isEmpty)
    }

    /// A doubled or late callback must not free a slot that belongs to somebody else's upload —
    /// that is how the cap quietly becomes four.
    @Test func finishingSomethingNotInFlightChangesNothing() {
        var queue = makeQueue(max: 2)
        queue.enqueue(assets(["a", "b", "c"]))
        _ = queue.startNext()

        #expect(queue.finish("a") != nil)
        #expect(queue.finish("a") == nil, "the second callback for a must be a no-op")
        #expect(queue.finish("zzz") == nil)
        #expect(queue.inFlightCount == 1)
        #expect(queue.freeSlots == 1)
    }

    /// Finishing does not reach into the waiting list. An asset that is still queued is not in
    /// flight, and a callback naming it should not silently drop it from the backup.
    @Test func finishingDoesNotRemoveAPendingAsset() {
        var queue = makeQueue(max: 1)
        queue.enqueue(assets(["a", "b"]))
        _ = queue.startNext()

        #expect(queue.finish("b") == nil)
        #expect(ids(queue.pending) == ["b"])
    }

    // MARK: - The 503 / 429 re-queue

    /// A server that asked us to back off gets the same asset next, not last. Sending it to the
    /// back would slowly reverse the album's upload order every time the server got busy.
    @Test func abackedOffAssetGoesToTheFrontOfTheQueue() {
        var queue = makeQueue(max: 1)
        queue.enqueue(assets(["a", "b", "c"]))
        let batch = queue.startNext()

        queue.finish("a")
        queue.requeueFront(batch[0])

        #expect(ids(queue.pending) == ["a", "b", "c"])
        #expect(ids(queue.startNext()) == ["a"])
    }

    /// Several assets pushed back in a row keep their relative order rather than reversing it —
    /// each goes in front of the ones still waiting, behind the ones already pushed back.
    @Test func repeatedBackpressureDoesNotReverseTheBatch() {
        var queue = makeQueue(max: 3)
        queue.enqueue(assets(["a", "b", "c", "d"]))
        let batch = queue.startNext()

        // The uploads come back in the order they were started, as they normally do.
        for item in batch {
            queue.finish(item.uploadQueueId)
        }
        for item in batch.reversed() {
            queue.requeueFront(item)
        }

        #expect(ids(queue.pending) == ["a", "b", "c", "d"])
    }

    /// A duplicate 503 callback must not put the same asset in the queue twice.
    @Test func requeueingSomethingAlreadyQueuedIsIgnored() {
        var queue = makeQueue(max: 1)
        queue.enqueue(assets(["a", "b"]))
        let batch = queue.startNext()
        queue.finish("a")

        queue.requeueFront(batch[0])
        queue.requeueFront(batch[0])
        queue.requeueBack(batch[0])

        #expect(ids(queue.pending) == ["a", "b"])
    }

    /// Nor while it is still in flight — a 503 handled twice, once before and once after the
    /// slot was freed, would otherwise upload it alongside itself.
    @Test func requeueingSomethingStillInFlightIsIgnored() {
        var queue = makeQueue(max: 2)
        queue.enqueue(assets(["a", "b"]))
        let batch = queue.startNext()

        queue.requeueFront(batch[0])

        #expect(queue.pending.isEmpty)
        #expect(queue.inFlightCount == 2)
    }

    // MARK: - The export-failure re-queue

    /// An export that failed goes to the back. Whatever is already waiting has not failed yet,
    /// so it deserves the slot first — and a stuck asset cannot hold the front of the queue.
    @Test func afailedExportGoesToTheBack() {
        var queue = makeQueue(max: 1)
        queue.enqueue(assets(["a", "b", "c"]))
        let batch = queue.startNext()

        queue.finish("a")
        queue.requeueBack(batch[0])

        #expect(ids(queue.pending) == ["b", "c", "a"])
    }

    /// The two re-queues really do differ. If they ever collapse into one call, a busy server
    /// and a broken export would start being treated the same way.
    @Test func theTwoRequeuesPutTheAssetAtOppositeEnds() {
        var backoff = makeQueue(max: 1)
        var failure = makeQueue(max: 1)
        backoff.enqueue(assets(["a", "b"]))
        failure.enqueue(assets(["a", "b"]))
        let fromBackoff = backoff.startNext()[0]
        let fromFailure = failure.startNext()[0]
        backoff.finish("a")
        failure.finish("a")

        backoff.requeueFront(fromBackoff)
        failure.requeueBack(fromFailure)

        #expect(ids(backoff.pending) == ["a", "b"])
        #expect(ids(failure.pending) == ["b", "a"])
    }

    // MARK: - Clearing

    /// Signing out, or switching album, drops everything — including what is in flight, whose
    /// callbacks must then find nothing to free.
    @Test func removingAllForgetsWaitingAndInFlightAlike() {
        var queue = makeQueue(max: 2)
        queue.enqueue(assets(["a", "b", "c", "d"]))
        _ = queue.startNext()

        queue.removeAll()

        #expect(queue.isEmpty)
        #expect(queue.freeSlots == 2)
        #expect(queue.finish("a") == nil)
        #expect(!queue.contains("a"))
    }

    /// And the queue is usable straight afterwards — a cleared queue is not a dead one.
    @Test func aclearedQueueAcceptsWorkAgain() {
        var queue = makeQueue(max: 2)
        queue.enqueue(assets(["a", "b"]))
        _ = queue.startNext()
        queue.removeAll()

        #expect(ids(queue.enqueue(assets(["a", "x"]))) == ["a", "x"])
        #expect(ids(queue.startNext()) == ["a", "x"])
    }

    // MARK: - Membership

    @Test func containsCoversBothWaitingAndUploading() {
        var queue = makeQueue(max: 1)
        queue.enqueue(assets(["a", "b"]))
        _ = queue.startNext()

        #expect(queue.contains("a"), "uploading")
        #expect(queue.contains("b"), "waiting")
        #expect(!queue.contains("c"))

        queue.finish("a")
        #expect(!queue.contains("a"))
    }

    /// A cap of one is the degenerate case the retry paths lean on hardest.
    @Test func acapOfOneStillWorks() {
        var queue = makeQueue(max: 1)
        queue.enqueue(assets(["a", "b"]))

        #expect(ids(queue.startNext()) == ["a"])
        #expect(queue.startNext().isEmpty)
        queue.finish("a")
        #expect(ids(queue.startNext()) == ["b"])
    }
}
