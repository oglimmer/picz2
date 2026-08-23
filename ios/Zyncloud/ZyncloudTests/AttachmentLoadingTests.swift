import Testing
@testable import Zyncloud

/// Covers §5.3 — the share extension sitting on "Preparing media files…" forever because an
/// attachment matching none of the three handled types was counted but never loaded.
struct AttachmentLoadingTests {
    // MARK: - Routing truth table

    /// The whole point: there is no combination of type checks with no answer. The original
    /// `if / else if / else if` had exactly one — all three false — and that was the bug.
    @Test(arguments: [
        (true, true, true, AttachmentRoute.fileURL),
        (true, true, false, AttachmentRoute.fileURL),
        (true, false, true, AttachmentRoute.fileURL),
        (true, false, false, AttachmentRoute.fileURL),
        (false, true, true, AttachmentRoute.image),
        (false, true, false, AttachmentRoute.image),
        (false, false, true, AttachmentRoute.movie),
        (false, false, false, AttachmentRoute.unusable),
    ])
    func routesEveryCombinationOfTypeChecks(
        fileURL: Bool, image: Bool, movie: Bool, expected: AttachmentRoute
    ) {
        let route = AttachmentRoute.route(
            conformsToFileURL: fileURL,
            conformsToImage: image,
            conformsToMovie: movie
        )
        #expect(route == expected)
    }

    @Test func anAttachmentConformingToNothingIsUnusableRatherThanUnhandled() {
        #expect(
            AttachmentRoute.route(conformsToFileURL: false, conformsToImage: false, conformsToMovie: false)
                == .unusable
        )
    }

    /// The fallback runs *after* a file-URL load has already failed, so it must not send the
    /// attachment back down the path that just produced nothing.
    @Test func theFallbackNeverRoutesBackToFileURL() {
        for image in [true, false] {
            for movie in [true, false] {
                let route = AttachmentRoute.fallbackRoute(conformsToImage: image, conformsToMovie: movie)
                #expect(route != .fileURL)
            }
        }
    }

    @Test(arguments: [
        (true, true, AttachmentRoute.image),
        (true, false, AttachmentRoute.image),
        (false, true, AttachmentRoute.movie),
        (false, false, AttachmentRoute.unusable),
    ])
    func fallbackRoutesByRemainingType(image: Bool, movie: Bool, expected: AttachmentRoute) {
        #expect(AttachmentRoute.fallbackRoute(conformsToImage: image, conformsToMovie: movie) == expected)
    }

    // MARK: - Tally

    @Test func aBatchIsIncompleteUntilEveryAttachmentIsAccountedFor() {
        var tally = AttachmentLoadTally(total: 3)
        #expect(!tally.isComplete)

        tally.noteLoaded()
        #expect(!tally.isComplete)

        tally.noteLoaded()
        #expect(!tally.isComplete)

        tally.noteLoaded()
        #expect(tally.isComplete)
    }

    /// The regression itself: a batch whose only attachment is unusable must still finish.
    /// Before the fix nothing counted it, so the UI waited on it forever.
    @Test func aBatchOfNothingButUnusableAttachmentsStillCompletes() {
        var tally = AttachmentLoadTally(total: 2)
        tally.noteSkipped()
        #expect(!tally.isComplete)

        tally.noteSkipped()
        #expect(tally.isComplete)
        #expect(tally.skipped == 2)
    }

    @Test func skippedAttachmentsCountTowardCompletionAndTowardTheSkipTotal() {
        var tally = AttachmentLoadTally(total: 4)
        tally.noteLoaded()
        tally.noteSkipped()
        tally.noteLoaded()
        tally.noteSkipped()

        #expect(tally.isComplete)
        #expect(tally.processed == 4)
        #expect(tally.skipped == 2)
    }

    @Test func loadedAttachmentsDoNotCountAsSkipped() {
        var tally = AttachmentLoadTally(total: 1)
        tally.noteLoaded()
        #expect(tally.skipped == 0)
    }

    /// `isComplete` is `>=` rather than `==` on purpose: an overcount should finish early,
    /// never sail past the completion point and hang the way the original bug did.
    @Test func anOvercountCompletesRatherThanHanging() {
        var tally = AttachmentLoadTally(total: 1)
        tally.noteLoaded()
        tally.noteLoaded()
        #expect(tally.isComplete)
    }

    @Test func anEmptyBatchIsAlreadyComplete() {
        #expect(AttachmentLoadTally(total: 0).isComplete)
    }
}
