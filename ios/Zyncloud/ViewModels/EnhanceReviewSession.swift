import Combine
import SwiftUI

/// The accept-or-decline pass over one or more photos (D82).
///
/// Every preview is requested at the start so the worker can build the later ones while the
/// owner looks at the first. Each photo is then waited for on the status endpoint, fetched,
/// shown against the current picture by ``EnhanceReviewView``, and either accepted — collected
/// in ``acceptedIds`` for ``AlbumDetailViewModel/applyEnhance(to:)``, which enqueues the real
/// job — or declined, which deletes the preview. Cancelling declines everything not yet decided.
/// Accepted previews are the server's to remove: the ENHANCE job drops them when it rewrites the
/// photo.
///
/// A class, and `Identifiable`, so a screen can present it with `fullScreenCover(item:)` and the
/// state survives the view being re-made under it.
@MainActor
final class EnhanceReviewSession: ObservableObject, Identifiable {
    let id = UUID()
    let photos: [Photo]

    @Published private(set) var index = 0
    /// The current photo's enhanced picture, nil while it is being built or after a failure.
    @Published private(set) var preview: UIImage?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// Which side the stage shows. Flipped by the segmented control; press-and-hold peeks past it.
    @Published var showsEnhanced = true
    /// True once every photo has been decided or the review was cancelled.
    @Published private(set) var isFinished = false
    private(set) var acceptedIds: [Int] = []

    private let apiClient: APIClient
    /// Ids whose preview request the server refused; they can only be skipped.
    private var refused: [Int: String] = [:]
    /// Bumped by every start/advance so a slow load for a previous photo cannot land on this one.
    private var generation = 0
    private var started = false

    /// How long one preview may take, worker queue included.
    private let previewTimeout: TimeInterval = 120

    init(photos: [Photo], apiClient: APIClient) {
        self.photos = photos
        self.apiClient = apiClient
    }

    var current: Photo? {
        index < photos.count ? photos[index] : nil
    }

    var count: Int {
        photos.count
    }

    func start() {
        guard !started else { return }
        started = true
        Task { await run() }
    }

    func accept() {
        guard let photo = current, !isFinished, !isLoading, errorMessage == nil, preview != nil else { return }
        acceptedIds.append(photo.id)
        advance()
    }

    func decline() {
        guard let photo = current, !isFinished else { return }
        discardQuietly(photo.id)
        advance()
    }

    func cancel() {
        guard !isFinished else { return }
        for photo in photos.dropFirst(index) {
            discardQuietly(photo.id)
        }
        generation += 1
        preview = nil
        isLoading = false
        isFinished = true
    }

    func toggle() {
        if preview != nil {
            showsEnhanced.toggle()
        }
    }

    // MARK: - Flow

    private func run() async {
        guard let first = photos.first else {
            isFinished = true
            return
        }
        // The first photo is shown as soon as its own request is in; the rest queue behind it.
        await request(first.id)
        let loadingFirst = Task { await loadCurrent() }
        for photo in photos.dropFirst() {
            await request(photo.id)
        }
        await loadingFirst.value
    }

    private func request(_ id: Int) async {
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            apiClient.requestEnhancePreview(id: id) { continuation.resume(returning: $0) }
        }
        if case let .failure(error) = result {
            refused[id] = error.localizedDescription
        }
    }

    private func loadCurrent() async {
        guard let photo = current else { return }
        generation += 1
        let myGeneration = generation
        preview = nil
        errorMessage = nil
        showsEnhanced = true

        if let refusal = refused[photo.id] {
            errorMessage = refusal
            isLoading = false
            return
        }
        isLoading = true

        let outcome = await awaitPreview(of: photo.id)
        guard myGeneration == generation else { return }
        switch outcome {
        case let .failed(message):
            errorMessage = message
            isLoading = false
            return
        case .timedOut:
            errorMessage = "The server is taking longer than usual. Try again in a moment."
            isLoading = false
            return
        case .done:
            break
        }

        let fetched: Result<Data, Error> = await withCheckedContinuation { continuation in
            apiClient.fetchEnhancePreview(id: photo.id) { continuation.resume(returning: $0) }
        }
        guard myGeneration == generation else { return }
        switch fetched {
        case let .success(data):
            if let image = UIImage(data: data) {
                preview = image
            } else {
                errorMessage = "Could not read the preview."
            }
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func advance() {
        preview = nil
        if index + 1 >= photos.count {
            generation += 1
            isLoading = false
            isFinished = true
            return
        }
        index += 1
        Task { await loadCurrent() }
    }

    /// Best-effort: a preview left behind costs a few hundred KB, and a delete of the photo or
    /// the admin sweep removes it.
    private func discardQuietly(_ id: Int) {
        guard refused[id] == nil else { return }
        apiClient.discardEnhancePreview(id: id) { _ in }
    }

    private enum Outcome {
        case done
        case failed(String)
        case timedOut
    }

    /// Same poll as ``AlbumDetailViewModel``'s, with the longer ceiling a queued preview needs.
    private func awaitPreview(of assetId: Int) async -> Outcome {
        let deadline = Date().addingTimeInterval(previewTimeout)
        while Date() < deadline {
            let status: AssetProcessingStatusResponse? = await withCheckedContinuation { continuation in
                apiClient.getAssetStatus(id: assetId) { result in
                    continuation.resume(returning: try? result.get())
                }
            }
            if let status, status.processingStatus.isTerminal {
                if case .done = status.processingStatus {
                    return .done
                }
                return .failed(status.error ?? "The server could not build the preview.")
            }
            try? await Task.sleep(for: .seconds(2))
        }
        return .timedOut
    }
}
