import Foundation
import Testing
import UIKit

@testable import Zyncloud

/// Drives ``AuthenticatedImageLoader`` all the way through a real `URLSession` round trip.
///
/// **Why this exists.** ``ImageReloadTests`` points its loader at a dead port and asserts only the
/// state a reload leaves behind synchronously, so nothing there ever lets the Combine chain
/// deliver a response — and that is exactly where the loader crashed.
///
/// The crash: the loader is `@MainActor`, and this project builds with
/// `SWIFT_APPROACHABLE_CONCURRENCY`, under which a non-`@Sendable` closure inherits the isolation
/// of wherever it is written. Combine's operator closures are not `@Sendable`, so a `tryMap`
/// written inline inside the loader became a main-actor closure — and Combine runs operators on
/// the `NSURLSession-delegate` queue. Every thumbnail therefore ran a main-actor check on a
/// background queue: `BUG IN CLIENT OF LIBDISPATCH: Assertion failed`, on launch.
///
/// A test that only checks the decoded image would still have caught it, because the process dies
/// before the assertion is reached. That is the point — this is a crash test wearing a
/// behaviour test's clothes.
///
/// Serialized for the usual reason: the stub intercepts `URLSession.shared`, which is
/// process-wide.
@Suite(.serialized)
@MainActor
struct ImageLoaderIsolationTests {
    private func url(_ suffix: String) -> URL {
        URL(string: "https://example.test/api/i/\(suffix)?size=thumbnail")!
    }

    /// A real PNG, because the loader decodes what comes back — `Data("x".utf8)` would decode to
    /// nil and take the "could not load" branch instead of the success branch.
    private var pngBytes: Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return image.pngData()!
    }

    /// Waits for `condition` to hold, or gives up. The loader finishes on the main queue via
    /// Combine rather than through anything awaitable, so there is nothing to `await` on.
    private func eventually(
        _ label: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool,
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("timed out waiting for \(label)")
    }

    /// Through ``StubServer/serving(status:body:_:)`` rather than driving ``StubURLProtocol``
    /// by hand, so this suite queues behind the other two that share the process-wide stub.
    private func serving(status: Int, body: Data, _ work: () async -> Void) async {
        // Inside the gate, not before it. ``ImageCache`` is process-wide and ``ImageReloadTests``
        // wipes it too, so clearing it out here raced with this suite's own cache assertions.
        await StubServer.serving(status: status, body: body) {
            ImageCache.removeAll()
            await work()
        }
    }

    /// The one that would have caught the crash: a plain successful load, start to finish.
    @Test func aloadedThumbnailReachesTheView() async {
        let target = url("ok")
        let loader = AuthenticatedImageLoader(url: target)

        await serving(status: 200, body: pngBytes) {
            loader.load()
            await eventually("the image to arrive") { loader.image != nil }
        }

        #expect(loader.image != nil)
        #expect(loader.error == nil)
        #expect(loader.isLoading == false)
        // A decoded image is cached, so the next cell showing the same URL costs nothing.
        #expect(ImageCache.image(for: target) != nil)
    }

    /// The 202 branch runs through the same operators, and it throws from inside `tryMap` —
    /// the failure path deserves the same coverage as the success path.
    @Test func aserverStillWorkingOnItReadsAsProcessing() async {
        let target = url("pending")
        let loader = AuthenticatedImageLoader(url: target)

        await serving(status: 202, body: Data()) {
            loader.load()
            await eventually("the processing flag") { loader.isServerProcessing }
            // A 202 schedules a re-check two seconds out. Cancelled here so it cannot fire after
            // the stub has moved on to another suite and be recorded as that suite's request.
            loader.cancel()
        }

        #expect(loader.isServerProcessing)
        // Not an error: the asset is fine, the derivative is merely not made yet.
        #expect(loader.error == nil)
        #expect(loader.image == nil)
    }

    /// And a genuine refusal, which must latch as an error rather than as "processing".
    @Test func arefusalLatchesAsAnError() async {
        let target = url("gone")
        let loader = AuthenticatedImageLoader(url: target)

        await serving(status: 404, body: Data()) {
            loader.load()
            await eventually("the error") { loader.error != nil }
        }

        #expect(loader.error != nil)
        #expect(loader.isServerProcessing == false)
        #expect(loader.image == nil)
    }
}
