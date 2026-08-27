import Combine
import Foundation
import SwiftUI

/// Decoded images, kept so scrolling a grid does not re-fetch and re-decode what it just showed.
///
/// `AuthenticatedImage` holds its loader in a `@StateObject`, and SwiftUI throws that away when a
/// `LazyVGrid` cell scrolls out of view — so without this, every cell that comes back is a fresh
/// network request and a fresh decode. `NSCache` is the right shape for it: it is thread-safe and
/// the system evicts it under memory pressure, which a plain dictionary would not.
///
/// Keyed by absolute URL, which already carries the size variant (`?size=thumbnail` vs `large`).
enum ImageCache {
    /// `nonisolated(unsafe)` because `NSCache` is not marked `Sendable`, even though it is
    /// documented as thread-safe — you may read and write one from any thread. Nothing else here
    /// is shared, so this is the one assertion the type needs.
    nonisolated(unsafe) private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    static func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }

    /// Drops every decoded image. Called when the user asks for a refresh: the cache is keyed
    /// by URL, and the server reuses a URL when it replaces a derivative, so keeping entries
    /// would let a refresh hand back exactly the picture the user is trying to get rid of.
    static func removeAll() {
        cache.removeAllObjects()
    }

    static func remove(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}

/// Loads one image URL into a SwiftUI view.
///
/// **No `Authorization` header, deliberately.** This used to read the Keychain on every `load()`
/// to build one — a synchronous IPC to securityd per grid cell — for a header the server ignores:
/// all three call sites point at `/api/i/{publicToken}`, which `SecurityConfig` declares
/// `permitAll`. The public token *is* the credential for that endpoint. Sending Basic auth
/// alongside it bought nothing and cost a securityd round-trip per thumbnail, and it also meant a
/// signed-out user saw a "No credentials found" error instead of the image.
/// The server's "not yet" answer for a derivative the worker has not produced.
///
/// `202 Accepted` sits inside the 2xx range, so it used to be read as a successful response
/// whose body happened not to decode — which is how every freshly uploaded photo ended up
/// under a red "Failed" icon while the thumbnail was merely still being made.
private struct ImageNotReadyYet: Error {}

/// - Note: `@MainActor` — this is held in a `@StateObject` and every property it publishes drives
///   one view. The Combine chain below already ends with `.receive(on: DispatchQueue.main)`.
@MainActor
final class AuthenticatedImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var error: Error?

    /// The server has the asset but not this size of it yet. Not an error — the view shows the
    /// same "Processing…" placeholder the file list's own status drives.
    @Published var isServerProcessing = false

    /// `nonisolated(unsafe)` so ``cancel()`` can stay callable from `deinit`, which runs on
    /// whichever thread drops the last reference. `AnyCancellable.cancel()` is safe to call from
    /// anywhere; the reference itself is only ever assigned on the main actor.
    nonisolated(unsafe) private var cancellable: AnyCancellable?

    /// The pending 202 re-check, held so ``cancel()`` can stop it.
    ///
    /// Without this, `cancel()` cancelled the subscription and nothing else, so a tile that
    /// scrolled away while the server was still making its thumbnail went on waking up and
    /// asking again every two seconds, up to fifteen times. `reload()` was worse: it cancels and
    /// starts a fresh chain, and the old chain's pending re-check then started a second one.
    ///
    /// `nonisolated(unsafe)` for the same reason as ``cancellable`` — `Task.cancel()` is safe to
    /// call from anywhere, and the reference is only ever assigned on the main actor.
    nonisolated(unsafe) private var retryTask: Task<Void, Never>?
    private let url: URL

    /// Bounded self-retry for the 202 case, so a thumbnail that becomes ready a second after
    /// the tile was drawn appears without the user doing anything. Covers the race the file
    /// list's status cannot: the list can say DONE a moment before the derivative is servable.
    private var notReadyRetries = 0
    private let maxNotReadyRetries = 15
    private let notReadyRetryDelay: TimeInterval = 2

    init(url: URL) {
        self.url = url
        image = ImageCache.image(for: url)
    }

    func load() {
        guard image == nil, !isLoading else { return }

        if let cached = ImageCache.image(for: url) {
            image = cached
            return
        }

        startRequest(bypassCaches: false)
    }

    /// Throws away whatever this loader decided last time and asks the server again.
    ///
    /// A loader runs `load()` once per cell and then keeps its answer, so a thumbnail that
    /// failed stayed failed for as long as the cell existed — reloading the file list did not
    /// touch it, which is why a fixed image only appeared after leaving the album and coming
    /// back. Both caches are skipped, because the server serves derivatives as `immutable`
    /// under a URL it reuses when it regenerates one.
    func reload() {
        cancel()
        ImageCache.remove(url)
        image = nil
        error = nil
        isServerProcessing = false
        notReadyRetries = 0
        isLoading = false
        startRequest(bypassCaches: true)
    }

    /// Turns one response into an image, or into the reason there is not one.
    ///
    /// A `nonisolated static` function, and passed to `tryMap` by name — **not** written inline
    /// as a closure. Under `SWIFT_APPROACHABLE_CONCURRENCY` a non-`@Sendable` closure inherits
    /// the isolation of wherever it was written. Combine's operator closures are not
    /// `@Sendable`, so writing this inline inside a `@MainActor` type made it a main-actor
    /// closure — and Combine runs these operators on the `NSURLSession-delegate` queue. The
    /// result was a main-actor check failing on a background queue:
    /// `BUG IN CLIENT OF LIBDISPATCH: Assertion failed`, on the first thumbnail loaded.
    ///
    /// A named `nonisolated` function has no enclosing isolation to inherit, which is the point.
    ///
    /// **The flag is set on the ShareExtension target only, not on the app target this file is
    /// built into.** That is deliberate but unfinished: turning it on for the app compiles
    /// cleanly and then crashes at runtime in this exact way somewhere else, because nothing
    /// else in the app was written for the rule and the compiler does not point at the places
    /// that break. Keep this function `nonisolated` regardless — it is correct either way, and
    /// it is what the app target will need on the day the flag is switched on for real.
    private nonisolated static func decode(
        _ output: URLSession.DataTaskPublisher.Output,
    ) throws -> UIImage? {
        guard let http = output.response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 202 {
            throw ImageNotReadyYet()
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return UIImage(data: output.data)
    }

    private func startRequest(bypassCaches: Bool) {
        isLoading = true
        error = nil

        var request = URLRequest(url: url)
        if bypassCaches {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }

        // Load image
        cancellable = URLSession.shared.dataTaskPublisher(for: request)
            .tryMap(Self.decode)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                // `.receive(on: DispatchQueue.main)` above guarantees this runs on the main
                // queue; `assumeIsolated` tells the compiler what the operator already ensures.
                MainActor.assumeIsolated {
                guard let self, case let .failure(err) = completion else { return }
                self.isLoading = false

                guard err is ImageNotReadyYet else {
                    self.error = err
                    return
                }

                // Still being made. Say so rather than failing, and look again shortly — up to
                // a bounded number of times, so a genuinely stuck asset settles on the
                // placeholder instead of polling for ever.
                self.isServerProcessing = true
                guard self.notReadyRetries < self.maxNotReadyRetries else { return }
                self.notReadyRetries += 1
                let delay = self.notReadyRetryDelay
                self.retryTask?.cancel()
                self.retryTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    guard let self, self.image == nil else { return }
                    self.startRequest(bypassCaches: true)
                }
                }
            }, receiveValue: { [weak self] loadedImage in
                MainActor.assumeIsolated {
                guard let self else { return }
                self.image = loadedImage
                self.isLoading = false
                self.isServerProcessing = false
                if let loadedImage {
                    ImageCache.store(loadedImage, for: self.url)
                } else {
                    self.error = AppError.api(message: "Could not load the picture", statusCode: nil)
                }
                }
            })
    }

    nonisolated func cancel() {
        cancellable?.cancel()
        retryTask?.cancel()
    }

    deinit {
        cancel()
    }
}

// SwiftUI view that uses AuthenticatedImageLoader
struct AuthenticatedImage: View {
    let url: URL

    /// Changes every time the user asks for a refresh. The loader is a `@StateObject`, so it
    /// survives a reload of the surrounding list and would otherwise keep showing its first
    /// answer; watching this value is what lets Refresh reach it.
    var reloadToken: Int = 0

    var body: some View {
        // A `@StateObject` is built once per view identity and keeps the URL it was born with,
        // so the loader has to be given a new identity when the URL changes. Rotating a photo
        // swaps its `publicToken`, and without this the tile would go on showing the picture
        // from before the rotate. Done here rather than at each call site so no caller can
        // forget it.
        AuthenticatedImageContent(url: url, reloadToken: reloadToken)
            .id(url)
    }
}

private struct AuthenticatedImageContent: View {
    let url: URL
    let reloadToken: Int

    @StateObject private var loader: AuthenticatedImageLoader

    init(url: URL, reloadToken: Int) {
        self.url = url
        self.reloadToken = reloadToken
        _loader = StateObject(wrappedValue: AuthenticatedImageLoader(url: url))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
            } else if loader.isServerProcessing {
                ProcessingPlaceholder(label: "Processing…")
            } else if loader.isLoading {
                ProgressView()
            } else if loader.error != nil {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .font(.title2)
                    Text("Failed")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Color.clear
            }
        }
        .onAppear {
            loader.load()
        }
        .onChange(of: reloadToken) { _, _ in
            loader.reload()
        }
    }
}

// MARK: - Processing Placeholder

/// Shown in place of a picture the server is still making. Used both by the image loader, when
/// a request comes back `202`, and by the gallery, when the file list already says the asset is
/// not `DONE` — the two are the same state seen from different sides.
struct ProcessingPlaceholder: View {
    let label: String
    var isFailure: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            if isFailure {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                    .font(.title3)
            } else {
                ProgressView()
            }

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(4)
    }
}
