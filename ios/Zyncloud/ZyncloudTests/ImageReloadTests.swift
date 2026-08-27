import Foundation
import Testing
import UIKit

@testable import Zyncloud

/// The Refresh button inside an album used to reload only the file list. The photos came back
/// with the same ids and the same image URLs, so SwiftUI kept the existing cells — and each
/// cell's `AuthenticatedImageLoader` is a `@StateObject` that runs once and keeps its answer.
/// A thumbnail the server had since fixed therefore stayed on the error icon until the album
/// was left and reopened. These pin down the two halves of the fix.
///
/// `.serialized` for the rule ``StubServer`` states: this suite reaches the stub, and the
/// interception is process-wide.
@Suite(.serialized)
@MainActor
struct ImageReloadTests {
    private func url(_ suffix: String) -> URL {
        URL(string: "http://127.0.0.1:1/api/i/\(suffix)?size=thumbnail")!
    }

    private var pixel: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    // MARK: - Cache eviction

    // ``ImageCache`` is process-wide and ``ImageLoaderIsolationTests`` asserts against it
    // too, so every test here that stores into it or wipes it holds the same gate that
    // suite's stub uses. Without that, wiping the cache here failed an assertion there.

    @Test func removeAllDropsEveryDecodedImage() async {
        await StubServer.holdingTheStub {
            let first = url("aaa")
            let second = url("bbb")
            ImageCache.store(pixel, for: first)
            ImageCache.store(pixel, for: second)

            ImageCache.removeAll()

            #expect(ImageCache.image(for: first) == nil)
            #expect(ImageCache.image(for: second) == nil)
        }
    }

    @Test func removeDropsOnlyTheNamedURL() async {
        await StubServer.holdingTheStub {
            ImageCache.removeAll()
            let kept = url("kept")
            let dropped = url("dropped")
            ImageCache.store(pixel, for: kept)
            ImageCache.store(pixel, for: dropped)

            ImageCache.remove(dropped)

            #expect(ImageCache.image(for: dropped) == nil)
            #expect(ImageCache.image(for: kept) != nil)
        }
    }

    // MARK: - Loader reset

    /// The bug in one assertion: a loader that has latched an error must not keep it across a
    /// reload. The request it starts points at a dead port and is irrelevant here — what is
    /// asserted is the state the reload leaves behind synchronously.
    @Test func reloadClearsALatchedError() async {
        // Inside the stub, not merely inside the gate. `reload()` puts a real request on
        // `URLSession.shared`, and this test used to fire it while ``EndpointShapeTests`` had the
        // stub armed — so `GET /api/i/failed` was recorded as *that* suite's request and its
        // `captureOne` read the wrong one. Holding the stub here means the request cannot be
        // recorded anywhere else, and it is answered at once instead of hanging on a dead port.
        //
        // A 500 with no body on purpose: a 200 would decode and land in ``ImageCache``, which the
        // next test asserts about.
        await StubServer.serving(status: 500, body: Data()) {
            let target = url("failed")
            let loader = AuthenticatedImageLoader(url: target)
            loader.error = URLError(.badServerResponse)

            loader.reload()
            loader.cancel()

            #expect(loader.error == nil)
            #expect(loader.image == nil)
        }
    }

    /// A reload must also go past the decoded-image cache, because the server reuses a URL when
    /// it regenerates a derivative — so the cached copy is exactly the stale one.
    @Test func reloadEvictsTheCachedImageForItsOwnURL() async {
        // Holds the stub rather than only the gate, for the reason above: `reload()` makes a
        // request, and a request that escapes this window gets recorded by whoever holds it next.
        await StubServer.serving(status: 500, body: Data()) {
            let target = url("stale")
            ImageCache.store(pixel, for: target)
            let loader = AuthenticatedImageLoader(url: target)

            loader.reload()
            loader.cancel()

            #expect(ImageCache.image(for: target) == nil)
        }
    }

    /// `load()` is the scrolling path and must stay cheap: an image already decoded is taken
    /// from the cache with no request at all. Only `reload()` pays for a round trip.
    @Test func loadStillServesFromTheCache() async {
        await StubServer.holdingTheStub {
            let target = url("cached")
            ImageCache.store(pixel, for: target)
            let loader = AuthenticatedImageLoader(url: target)

            loader.load()

            #expect(loader.image != nil)
            #expect(loader.isLoading == false)
        }
    }
}
