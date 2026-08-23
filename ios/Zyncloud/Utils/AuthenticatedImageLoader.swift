import Combine
import Foundation
import SwiftUI

// Custom image loader that supports Basic Authentication
class AuthenticatedImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var error: Error?

    private var cancellable: AnyCancellable?
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func load() {
        guard image == nil, !isLoading else { return }

        isLoading = true
        error = nil

        // Get credentials
        guard let credentials = KeychainHelper.shared.load() else {
            error = NSError(domain: "AuthenticatedImageLoader", code: 401, userInfo: [NSLocalizedDescriptionKey: "No credentials found"])
            isLoading = false
            return
        }

        // Create authenticated request
        var request = URLRequest(url: url)
        let authString = "\(credentials.username):\(credentials.password)"
        if let authData = authString.data(using: .utf8) {
            let base64Auth = authData.base64EncodedString()
            request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        }

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
                self?.image = loadedImage
                self?.isLoading = false
                if loadedImage == nil {
                    self?.error = NSError(domain: "AuthenticatedImageLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image"])
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
