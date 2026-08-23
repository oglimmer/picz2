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
}

/// Loads one image URL into a SwiftUI view.
///
/// **No `Authorization` header, deliberately.** This used to read the Keychain on every `load()`
/// to build one — a synchronous IPC to securityd per grid cell — for a header the server ignores:
/// all three call sites point at `/api/i/{publicToken}`, which `SecurityConfig` declares
/// `permitAll`. The public token *is* the credential for that endpoint. Sending Basic auth
/// alongside it bought nothing and cost a securityd round-trip per thumbnail, and it also meant a
/// signed-out user saw a "No credentials found" error instead of the image.
class AuthenticatedImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var error: Error?

    private var cancellable: AnyCancellable?
    private let url: URL

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

        isLoading = true
        error = nil

        let request = URLRequest(url: url)

        // Load image
        cancellable = URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { output -> Data in
                guard let http = output.response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return output.data
            }
            .map { UIImage(data: $0) }
            .mapError { $0 }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                if case let .failure(err) = completion {
                    self?.error = err
                    self?.isLoading = false
                }
            }, receiveValue: { [weak self] loadedImage in
                guard let self else { return }
                self.image = loadedImage
                self.isLoading = false
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

    @StateObject private var loader: AuthenticatedImageLoader

    init(url: URL) {
        self.url = url
        _loader = StateObject(wrappedValue: AuthenticatedImageLoader(url: url))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
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
    }
}
