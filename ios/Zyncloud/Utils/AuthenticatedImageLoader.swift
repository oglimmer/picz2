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
    private static let cache: NSCache<NSURL, UIImage> = {
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

class AuthenticatedImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var error: Error?

    /// The server has the asset but not this size of it yet. Not an error — the view shows the
    /// same "Processing…" placeholder the file list's own status drives.
    @Published var isServerProcessing = false

    private var cancellable: AnyCancellable?
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

    private func startRequest(bypassCaches: Bool) {
        isLoading = true
        error = nil

        var request = URLRequest(url: url)
        if bypassCaches {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }

        // Load image
        cancellable = URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { output -> Data in
                guard let http = output.response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if http.statusCode == 202 {
                    throw ImageNotReadyYet()
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return output.data
            }
            .map { UIImage(data: $0) }
            .mapError { $0 }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
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
                DispatchQueue.main.asyncAfter(deadline: .now() + self.notReadyRetryDelay) { [weak self] in
                    guard let self, self.image == nil else { return }
                    self.startRequest(bypassCaches: true)
                }
            }, receiveValue: { [weak self] loadedImage in
                guard let self else { return }
                self.image = loadedImage
                self.isLoading = false
                self.isServerProcessing = false
                if let loadedImage {
                    ImageCache.store(loadedImage, for: self.url)
                } else {
                    self.error = NSError(domain: "AuthenticatedImageLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image"])
                }
            })
    }

    func cancel() {
        cancellable?.cancel()
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
