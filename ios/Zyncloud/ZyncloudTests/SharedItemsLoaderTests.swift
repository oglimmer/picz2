import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Zyncloud

/// The share extension's accounting: every attachment iOS hands over must reach the tally
/// exactly once, and the completion must fire exactly once when they all have.
///
/// This is the half of the "Preparing media files…" bug that ``AttachmentLoadingTests`` does not
/// reach. That suite proves the routing has no gap; this one proves the *counting* has none —
/// an attachment routed correctly and then never counted hangs the share just as completely,
/// with Upload disabled and no error anywhere.
///
/// The providers are real `NSItemProvider`s carrying URLs rather than files on disk: the loader
/// never reads the bytes, it only decides what each attachment is and books it.
@MainActor
struct SharedItemsLoaderTests {
    // MARK: - Attachments to hand over

    /// An attachment that arrives as a file on disk — the ordinary case from Photos.
    private func fileURLAttachment(_ name: String) -> NSItemProvider {
        NSItemProvider(
            item: URL(fileURLWithPath: "/tmp/share-test/\(name)") as NSURL,
            typeIdentifier: UTType.fileURL.identifier,
        )
    }

    /// A movie that does not also announce itself as a file URL, so it takes the movie branch.
    private func movieAttachment(_ name: String) -> NSItemProvider {
        NSItemProvider(
            item: URL(fileURLWithPath: "/tmp/share-test/\(name)") as NSURL,
            typeIdentifier: UTType.movie.identifier,
        )
    }

    /// An image held in memory rather than on disk. Routed as an image, loads as something that
    /// is not a URL, and there is nowhere to upload it from.
    private func inMemoryImageAttachment() -> NSItemProvider {
        NSItemProvider(item: NSData(), typeIdentifier: UTType.image.identifier)
    }

    /// Conforms to none of the three types the extension handles. This is the one the original
    /// `if / else if / else if` dropped on the floor.
    private func unusableAttachment() -> NSItemProvider {
        NSItemProvider(item: NSString("just some words"), typeIdentifier: UTType.plainText.identifier)
    }

    private func extensionItem(_ attachments: [NSItemProvider]) -> NSExtensionItem {
        let item = NSExtensionItem()
        item.attachments = attachments
        return item
    }

    // MARK: - Running one share

    /// What one share produced: how many attachments were found, the batch if the completion
    /// fired, and how many times it fired.
    private struct Outcome {
        var found: Int
        var batch: SharedItemsLoader.Batch?
        var calls: Int
    }

    /// The completion is called from a `Task { @MainActor }` hop off an `NSItemProvider`
    /// callback, so there is nothing to `await` on — hence polling with a deadline.
    ///
    /// `settle` is how long to keep waiting *after* the completion fires, so a second call can be
    /// caught. Without it "fires exactly once" would only ever prove "fires at least once".
    private func share(
        _ items: [NSExtensionItem],
        timeout: TimeInterval = 5,
        settle: TimeInterval = 0.2,
    ) async -> Outcome {
        let loader = SharedItemsLoader()
        var outcome = Outcome(found: 0, batch: nil, calls: 0)

        // A box so the completion can write from a later main-actor hop.
        final class Sink {
            var batch: SharedItemsLoader.Batch?
            var calls = 0
        }
        let sink = Sink()

        outcome.found = loader.load(from: items) { batch in
            sink.batch = batch
            sink.calls += 1
        }

        if outcome.found > 0 {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline, sink.calls == 0 {
                try? await Task.sleep(for: .milliseconds(10))
            }
            if sink.calls == 0 {
                Issue.record("the share never finished preparing — \(outcome.found) attachments went unaccounted for")
            }
        }

        try? await Task.sleep(for: .milliseconds(Int(settle * 1000)))

        // Keep the loader alive to here: its callbacks hold it weakly, so an early release
        // would look exactly like the hang this suite is here to rule out.
        withExtendedLifetime(loader) {}

        outcome.batch = sink.batch
        outcome.calls = sink.calls
        return outcome
    }

    // MARK: - Nothing is ever left uncounted

    /// The regression. One usable attachment next to two that produce nothing must still finish:
    /// the batch completes, and the two are reported as skipped rather than silently dropped.
    @Test func `amixed share finishes and reports what it could not use`() async {
        let outcome = await share([extensionItem([
            fileURLAttachment("holiday.jpg"),
            unusableAttachment(),
            inMemoryImageAttachment(),
        ])])

        #expect(outcome.found == 3)
        #expect(outcome.batch?.items.count == 1)
        #expect(outcome.batch?.skippedCount == 2)
    }

    /// A share made entirely of things the extension cannot use still has to finish. Before the
    /// `unusable` branch existed this sat on "Preparing media files…" forever.
    @Test func `ashare of nothing usable still finishes`() async {
        let outcome = await share([extensionItem([unusableAttachment(), unusableAttachment()])])

        #expect(outcome.calls == 1)
        #expect(outcome.batch?.items.isEmpty == true)
        #expect(outcome.batch?.skippedCount == 2)
    }

    /// An in-memory image is counted, not dropped. Uploading one means writing it to a temp file
    /// first, which the extension does not do yet — so it is a skip with a reason, not a gap.
    @Test func `anin memory image is skipped rather than lost`() async {
        let outcome = await share([extensionItem([inMemoryImageAttachment()])])

        #expect(outcome.batch?.items.isEmpty == true)
        #expect(outcome.batch?.skippedCount == 1)
    }

    /// Attachments spread over several extension items are all found and all counted. iOS splits
    /// a multi-photo share this way, so counting only the first item's would hang every one.
    @Test func `attachments across several extension items are all counted`() async {
        let outcome = await share([
            extensionItem([fileURLAttachment("a.jpg")]),
            extensionItem([fileURLAttachment("b.jpg"), unusableAttachment()]),
        ])

        #expect(outcome.found == 3)
        #expect(outcome.batch?.items.count == 2)
        #expect(outcome.batch?.skippedCount == 1)
    }

    /// Exactly once. The tally completes on `>=` so a double-count finishes early rather than
    /// never; the `didFinish` flag is what keeps early from also meaning twice.
    @Test func `thecompletion fires exactly once`() async {
        let outcome = await share([extensionItem([
            fileURLAttachment("a.jpg"),
            fileURLAttachment("b.mov"),
            unusableAttachment(),
        ])])

        #expect(outcome.calls == 1)
    }

    // MARK: - An empty share

    /// Nothing to wait for, so the completion is never called and the caller decides what an
    /// empty share means. The return value is the whole signal.
    @Test func `anempty share reports zero and never completes`() async {
        let outcome = await share([extensionItem([]), NSExtensionItem()])

        #expect(outcome.found == 0)
        #expect(outcome.calls == 0)
        #expect(outcome.batch == nil)
    }

    // MARK: - What each attachment turns into

    @Test func `afile URL becomes A media item named after the file`() async {
        let outcome = await share([extensionItem([fileURLAttachment("holiday.jpg")])])

        #expect(outcome.batch?.items.first?.filename == "holiday.jpg")
        #expect(outcome.batch?.items.first?.url.path == "/tmp/share-test/holiday.jpg")
    }

    /// The type is read off the extension, because a file URL arrives with no other clue. Getting
    /// it wrong sends a video down the image path, where it is refused for its size.
    @Test(arguments: [
        ("holiday.jpg", MediaItem.MediaType.image),
        ("holiday.HEIC", MediaItem.MediaType.image),
        ("clip.mov", MediaItem.MediaType.video),
        ("clip.MP4", MediaItem.MediaType.video),
    ])
    func `thefile extension decides image or video`(name: String, expected: MediaItem.MediaType) async {
        let outcome = await share([extensionItem([fileURLAttachment(name)])])

        #expect(outcome.batch?.items.first?.type == expected)
    }

    /// An extension nobody recognises falls back to image rather than being refused. The server
    /// decides what it will accept; guessing "not a photo" here would drop something uploadable.
    @Test func `anunrecognised extension falls back to image`() async {
        let outcome = await share([extensionItem([fileURLAttachment("scan.raw2")])])

        #expect(outcome.batch?.items.count == 1)
        #expect(outcome.batch?.items.first?.type == .image)
    }

    /// A movie arriving as a movie rather than as a file URL takes the other branch, and must
    /// come out as a video regardless of what the filename says.
    @Test func `amovie attachment is A video whatever it is called`() async {
        let outcome = await share([extensionItem([movieAttachment("recording.dat")])])

        #expect(outcome.batch?.items.first?.type == .video)
        #expect(outcome.batch?.items.first?.filename == "recording.dat")
    }
}
