import Foundation
import Testing
@testable import Zyncloud

/// §6 step 7 — the `isUploaded` / `markAsUploading` / `markUploaded` / `cleanupStaleUploading`
/// state machine, which is where the "stuck uploading" bugs live. §3.2 (two background sessions
/// sharing an identifier, the second orphaning the first's delegate) corrupted exactly this
/// state: uploads lost the callback that would have cleared their uploading entry.
///
/// Every case gets its own `UserDefaults` suite and removes it afterwards, so the real upload
/// history is never touched.
///
/// `.serialized` is not optional here. `UploadStore` guards its state with `queue.sync` on a
/// concurrent `DispatchQueue`; run in parallel, a dozen Swift Testing cases block cooperative
/// threads inside `_dispatch_sync_f_slow` at once and the run wedges. Sampling a stuck run
/// showed 11 threads parked in `isUploaded`.
@Suite(.serialized)
struct UploadStoreTests {
    /// The mutating methods dispatch `async(flags: .barrier)`, so a write has not necessarily
    /// landed when the call returns. `isUploaded` is a `queue.sync` read on the same concurrent
    /// queue, which cannot start until earlier barriers have finished — so calling it is a
    /// reliable flush before inspecting `UserDefaults` or building a second store.
    private func flush(_ store: UploadStore) {
        _ = store.isUploaded("flush-probe")
    }

    private func withScratchStore(_ body: (UploadStore, UserDefaults) throws -> Void) rethrows {
        let name = "test.uploadstore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(UploadStore(defaults: defaults), defaults)
    }

    // MARK: - isUploaded

    @Test func anUnknownAssetIsNotUploaded() {
        withScratchStore { store, _ in
            #expect(!store.isUploaded("never-seen"))
        }
    }

    /// Deliberate conflation: an in-flight upload reports as "uploaded" so the scanner does not
    /// queue it a second time. This is the property that makes a *stuck* uploading entry so
    /// costly — the asset is invisible to the scanner until something clears it.
    @Test func anAssetBeingUploadedAlreadyCountsAsUploaded() {
        withScratchStore { store, _ in
            store.markAsUploading("asset-1")
            #expect(store.isUploaded("asset-1"))
        }
    }

    @Test func removingFromUploadingMakesTheAssetVisibleAgain() {
        withScratchStore { store, _ in
            store.markAsUploading("asset-1")
            store.removeFromUploading("asset-1")
            #expect(!store.isUploaded("asset-1"))
        }
    }

    // MARK: - markUploaded

    @Test func markingUploadedClearsTheUploadingEntry() {
        withScratchStore { store, defaults in
            store.markAsUploading("asset-1")
            store.markUploaded("asset-1")
            flush(store)

            #expect(store.isUploaded("asset-1"))
            let uploading = defaults.stringArray(forKey: "uploads.uploading.ids") ?? []
            #expect(!uploading.contains("asset-1"))
        }
    }

    /// Completion is sticky — a stray `removeFromUploading` must not un-complete an asset and
    /// cause it to be uploaded twice.
    @Test func aCompletedAssetStaysCompleted() {
        withScratchStore { store, _ in
            store.markUploaded("asset-1")
            store.removeFromUploading("asset-1")
            #expect(store.isUploaded("asset-1"))
        }
    }

    @Test func markingUploadedWithoutEverMarkingUploadingWorks() {
        withScratchStore { store, _ in
            store.markUploaded("asset-1")
            #expect(store.isUploaded("asset-1"))
        }
    }

    // MARK: - cleanupStaleUploading

    /// The paper-over for §3.2. With no live tasks every uploading entry is stale.
    @Test func cleanupWithNoActiveTasksClearsEveryUploadingEntry() {
        withScratchStore { store, _ in
            store.markAsUploading("a")
            store.markAsUploading("b")

            store.cleanupStaleUploading(activeTasks: [])

            #expect(!store.isUploaded("a"))
            #expect(!store.isUploaded("b"))
        }
    }

    /// The case that matters on relaunch: an upload still running in a background session must
    /// survive cleanup, or it gets queued a second time while the first is still in flight.
    @Test func cleanupPreservesAssetsWithLiveBackgroundTasks() {
        withScratchStore { store, _ in
            store.markAsUploading("still-running")
            store.markAsUploading("orphaned")

            store.cleanupStaleUploading(activeTasks: ["still-running"])

            #expect(store.isUploaded("still-running"))
            #expect(!store.isUploaded("orphaned"))
        }
    }

    @Test func cleanupNeverTouchesCompletedUploads() {
        withScratchStore { store, _ in
            store.markUploaded("done")
            store.markAsUploading("in-flight")

            store.cleanupStaleUploading(activeTasks: [])

            #expect(store.isUploaded("done"))
            #expect(!store.isUploaded("in-flight"))
        }
    }

    @Test func cleanupOnAnEmptyStoreIsHarmless() {
        withScratchStore { store, _ in
            store.cleanupStaleUploading(activeTasks: ["not-even-tracked"])
            #expect(!store.isUploaded("not-even-tracked"))
        }
    }

    // MARK: - Persistence

    @Test func stateSurvivesARestart() {
        let name = "test.uploadstore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        let first = UploadStore(defaults: defaults)
        first.markUploaded("done")
        first.markAsUploading("in-flight")
        flush(first)

        let second = UploadStore(defaults: defaults)
        #expect(second.isUploaded("done"))
        #expect(second.isUploaded("in-flight"))
    }

    @Test func clearRemovesEverything() {
        withScratchStore { store, defaults in
            store.markUploaded("done", checksum: "abc")
            store.markAsUploading("in-flight")

            store.clear()
            flush(store)

            #expect(!store.isUploaded("done"))
            #expect(!store.isUploaded("in-flight"))
            #expect(defaults.stringArray(forKey: "uploads.completed.ids") == nil)
            #expect(defaults.stringArray(forKey: "uploads.uploading.ids") == nil)
            #expect(defaults.data(forKey: "uploads.checksums") == nil)
        }
    }

    // MARK: - Checksum reconciliation

    @Test func reconcilingMarksAssetsWhoseChecksumTheServerAlreadyHas() {
        withScratchStore { store, _ in
            store.storeChecksumMapping(checksum: "sha-1", localId: "asset-1")

            store.reconcileWithServerChecksums(["sha-1"])

            #expect(store.isUploaded("asset-1"))
        }
    }

    @Test func markingUploadedWithAChecksumRecordsTheMapping() {
        withScratchStore { store, _ in
            store.markUploaded("asset-1", checksum: "sha-1")
            store.clear()
            store.storeChecksumMapping(checksum: "sha-1", localId: "asset-1")
            store.reconcileWithServerChecksums(["sha-1"])

            #expect(store.isUploaded("asset-1"))
        }
    }

    @Test func reconcilingClearsAnyUploadingEntryForAMatchedAsset() {
        withScratchStore { store, _ in
            store.storeChecksumMapping(checksum: "sha-1", localId: "asset-1")
            store.markAsUploading("asset-1")

            store.reconcileWithServerChecksums(["sha-1"])
            store.removeFromUploading("asset-1")

            // Still uploaded: reconciliation promoted it to completed, so dropping the
            // uploading entry cannot make it look un-uploaded.
            #expect(store.isUploaded("asset-1"))
        }
    }

    /// Documents §5.8 rather than asserting desired behaviour. `checksumToLocalId` is empty on a
    /// fresh install, so reconciliation — the mechanism that exists to avoid re-uploading — is
    /// inert exactly when it would matter most. If that is ever fixed, invert this test.
    @Test func reconcilingDoesNothingOnAFreshInstallBecauseTheLocalMapIsEmpty() {
        withScratchStore { store, _ in
            store.reconcileWithServerChecksums(["sha-1", "sha-2"])
            #expect(!store.isUploaded("asset-1"))
        }
    }

    @Test func reconcilingWithAnUnknownChecksumIsHarmless() {
        withScratchStore { store, _ in
            store.storeChecksumMapping(checksum: "sha-1", localId: "asset-1")
            store.reconcileWithServerChecksums(["some-other-checksum"])
            #expect(!store.isUploaded("asset-1"))
        }
    }
}
