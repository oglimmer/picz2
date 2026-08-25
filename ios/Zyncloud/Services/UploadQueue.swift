import Foundation
import Photos

/// Something the upload queue can hold. Only identity is needed — the queue never looks inside.
protocol UploadQueueItem {
    /// Stable identity. `PHAsset.localIdentifier` in the app; anything unique in a test.
    var uploadQueueId: String { get }
}

extension PHAsset: UploadQueueItem {
    var uploadQueueId: String { localIdentifier }
}

/// The waiting-list bookkeeping behind ``SyncCoordinator``.
///
/// This used to be three fields sitting side by side on the coordinator — `pendingAssets`,
/// `uploadingAssets` and `inFlightAssets` — mutated from five separate places, with the
/// concurrency cap, the 503 re-queue and the export-failure re-queue all inlined among the
/// upload callbacks that used them. None of it could be tested, because reaching any of it meant
/// standing up a coordinator and handing it live `PHAsset`s.
///
/// Nothing about the rules is specific to photos, so they moved here, generic over whatever is
/// being queued. The coordinator keeps the parts that genuinely need the photo library.
///
/// Not thread-safe, deliberately: it is a value type and the coordinator touches it only on its
/// own `syncQueue`, which is the same discipline the three fields had.
struct UploadQueue<Item: UploadQueueItem> {
    /// The most uploads the server may be handed at once.
    let maxInFlight: Int

    /// Waiting, in the order they will be started.
    private(set) var pending: [Item] = []

    /// A membership index over ``pending``. The scan it replaces was O(pending) *per candidate*,
    /// which a library scan runs thousands of times.
    private var pendingIds: Set<String> = []

    /// Handed to an uploader and not yet finished, by id. Held as items rather than ids because
    /// a 503 has to put the very same item back at the front of the queue.
    private(set) var inFlight: [String: Item] = [:]

    init(maxInFlight: Int) {
        self.maxInFlight = maxInFlight
    }

    // MARK: - Reading

    var pendingCount: Int { pending.count }
    var inFlightCount: Int { inFlight.count }
    var isEmpty: Bool { pending.isEmpty && inFlight.isEmpty }

    /// Free upload slots right now. Never negative, even if something went in behind the cap's
    /// back — the caller uses it to decide how many uploads to start.
    var freeSlots: Int { max(0, maxInFlight - inFlight.count) }

    /// True while this id is queued or uploading. Used to keep a re-scan from queuing an asset
    /// that is already on its way.
    func contains(_ id: String) -> Bool {
        pendingIds.contains(id) || inFlight[id] != nil
    }

    // MARK: - Writing

    /// Adds everything not already queued or in flight to the back, and answers with exactly
    /// what was added.
    ///
    /// Repeats *within* `items` are collapsed too: a library scan can legitimately hand the same
    /// asset over twice, and queuing it twice would upload it twice.
    @discardableResult
    mutating func enqueue(_ items: [Item]) -> [Item] {
        var added: [Item] = []
        for item in items where !contains(item.uploadQueueId) {
            pending.append(item)
            pendingIds.insert(item.uploadQueueId)
            added.append(item)
        }
        return added
    }

    /// Moves up to ``freeSlots`` items off the front of the queue and marks them in flight.
    ///
    /// This is the whole concurrency cap: nothing else starts an upload, so the server can never
    /// see more than ``maxInFlight`` at once however many callbacks fire at the same moment.
    mutating func startNext() -> [Item] {
        let count = min(freeSlots, pending.count)
        guard count > 0 else { return [] }

        let batch = Array(pending.prefix(count))
        pending.removeFirst(count)
        for item in batch {
            pendingIds.remove(item.uploadQueueId)
            inFlight[item.uploadQueueId] = item
        }
        return batch
    }

    /// Frees the slot this id was holding and hands the item back, or nil if it was not in
    /// flight — a late duplicate callback, which must not free somebody else's slot.
    @discardableResult
    mutating func finish(_ id: String) -> Item? {
        inFlight.removeValue(forKey: id)
    }

    /// Puts an item back at the **front**, for a server that asked us to back off. It was next
    /// before the 503 and it should be next after it, or a busy server slowly reverses the
    /// album's upload order.
    ///
    /// Ignored when the item is somehow already queued or in flight, so a doubled callback
    /// cannot get the same asset uploaded twice.
    mutating func requeueFront(_ item: Item) {
        guard !contains(item.uploadQueueId) else { return }
        pending.insert(item, at: 0)
        pendingIds.insert(item.uploadQueueId)
    }

    /// Puts an item back at the **back**, for an export that failed and is worth another try
    /// later. Behind everything else on purpose: whatever is waiting has not failed yet.
    mutating func requeueBack(_ item: Item) {
        guard !contains(item.uploadQueueId) else { return }
        pending.append(item)
        pendingIds.insert(item.uploadQueueId)
    }

    /// Forgets everything. In-flight uploads are not cancelled by this — the sessions own those
    /// — it only stops the queue expecting them back.
    mutating func removeAll() {
        pending.removeAll()
        pendingIds.removeAll()
        inFlight.removeAll()
    }
}
