import Combine
import Foundation
import Photos
import SwiftUI
import os

@MainActor
class AlbumDetailViewModel: ViewModelProtocol {
    @Published var photos: [Photo] = [] {
        didSet { dayGroups = groupByDayAndRegion(photos) }
    }

    /// The album re-shelved into day and place sections, for the "By Day & Place" layout.
    ///
    /// Rebuilt here rather than in the view: the clustering is O(n²) in the worst case, and a
    /// SwiftUI body runs again for every tap, scroll and selection change while the photo list
    /// itself only changes when the server says something new.
    @Published private(set) var dayGroups: [DayGroup] = []
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?
    @Published var isLoadingMore: Bool = false

    /// True while a sort request is in flight, so the Sort menu can disable itself.
    @Published var isReordering: Bool = false

    /// Mirrors the web gallery's "Arrange by hand" mode: while on, the grid is replaced by a
    /// movable list and every move is written straight back to the server.
    @Published var isArrangingByHand: Bool = false

    /// How many photos this screen has handed to the uploader and not yet seen finish.
    @Published var uploadsInFlight: Int = 0

    /// Bumped by every user-initiated refresh, and watched by each cell's image loader.
    ///
    /// Reloading the file list is not enough on its own: the photos come back with the same
    /// ids and the same image URLs, so SwiftUI keeps the existing cells — and with them the
    /// loader that already decided the image failed. Without this, a thumbnail the server has
    /// since fixed only appeared after leaving the album and reopening it.
    @Published private(set) var imageReloadToken: Int = 0

    /// Photos with a rotate in flight. The worker pod does the work, so the tile has to say it
    /// is busy for the seconds in between — and refuse a second rotate on the same photo.
    @Published private(set) var rotatingPhotoIds: Set<Int> = []

    // The four tag properties below are written only by `AlbumDetailViewModel+Tags.swift`.
    // They are not `private(set)` because `private` in Swift means "this file", and that
    // extension is a different one.

    /// Tags this album accepts, straight from the server. Not the account's whole tag list:
    /// the server refuses any tag that is not enabled for the album, so offering the others
    /// would only produce failures.
    @Published var albumTags: [Tag] = []

    /// The account's whole tag list, needed only by the screen that says which of them this
    /// album accepts.
    @Published var accountTags: [Tag] = []

    @Published var isLoadingTags: Bool = false

    /// True while a tag change is in flight, so a second one cannot be started on top of it.
    @Published var isApplyingTags: Bool = false

    /// True while the grid picks photos instead of opening them.
    @Published var isSelecting: Bool = false

    /// The picked photos, held as ids because the photo list is replaced under it by every
    /// reload — a stored `Photo` would go stale, an id does not.
    @Published var selectedPhotoIds: Set<Int> = []

    /// Drives the system photo picker. Set by ``requestUpload()`` once library access is
    /// settled, never by the view directly — the picker can only name assets while access is
    /// granted, and asking afterwards would throw the user's choice away.
    @Published var isPickerPresented: Bool = false

    /// Where this album's map opens, or nil to fit every pin.
    ///
    /// Held here rather than read off ``album`` on every access because saving a view changes it:
    /// the album this screen was pushed with is a value, and the server's answer to the save is
    /// the new truth. Seeded from the album, then owned by ``saveMapView(_:)`` and
    /// ``clearMapView()``.
    @Published private(set) var savedMapView: SavedMapView?

    let album: Album

    /// Readable across the file boundary so the tag actions in `AlbumDetailViewModel+Tags.swift`
    /// can use it; still only written here, by ``loadCredentials()``.
    private(set) var apiClient: APIClient?
    private var currentPage: Int = 1
    private var hasMorePages: Bool = true
    private let syncCoordinator: SyncCoordinator
    private var uploadObserver: AnyCancellable?
    private var processingPollTask: Task<Void, Never>?

    init(album: Album, syncCoordinator: SyncCoordinator = .shared,
         apiClient: APIClient? = APIClientProvider.shared.current)
    {
        self.album = album
        self.syncCoordinator = syncCoordinator
        self.apiClient = apiClient
        savedMapView = album.savedMapView
        observeUploads()
    }

    /// Watches the coordinator's per-album counter rather than each upload: uploads run on a
    /// background `URLSession` that outlives this screen, so the count is the only honest
    /// source. When this album's count falls to zero the new photos exist server-side, so the
    /// grid is reloaded.
    private func observeUploads() {
        let albumId = album.id
        uploadObserver = syncCoordinator.$albumUploadsInFlight
            .map { $0[albumId] ?? 0 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                guard let self else { return }
                let wasUploading = uploadsInFlight > 0
                uploadsInFlight = count
                if wasUploading, count == 0 {
                    let duplicates = syncCoordinator.albumUploadsRejectedAsDuplicate[albumId] ?? []
                    Task {
                        await self.refreshPhotos()
                        await self.reportDuplicates(duplicates)
                    }
                }
            }
    }

    func fetchPhotos() {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            return
        }

        isLoading = true
        alertState = nil

        // Server doesn't use pagination - fetches all files in album
        apiClient.fetchFiles(albumId: album.id) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case let .success(response):
                    self.photos = response.files
                    self.hasMorePages = false // No pagination on server
                    self.startProcessingPollingIfNeeded()

                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }

    func refreshPhotos() async {
        guard let apiClient else { return }

        await withCheckedContinuation { continuation in
            apiClient.fetchFiles(albumId: album.id) { [weak self] result in
                guard let self else {
                    continuation.resume()
                    return
                }

                Task { @MainActor in
                    switch result {
                    case let .success(response):
                        self.photos = response.files
                        self.hasMorePages = false
                        self.startProcessingPollingIfNeeded()
                    case let .failure(error):
                        self.handleError(error)
                    }
                    continuation.resume()
                }
            }
        }
    }

    /// Says out loud that the server kept photos out of this album.
    ///
    /// The server dedupes by contentId across the whole account, and a photo belongs to exactly
    /// one album, so picking one it already holds stores nothing — the album simply does not
    /// change. Without this the upload reported success and the user was left looking for a
    /// photo that was never going to appear.
    ///
    /// Each rejected photo is looked up in *this* album first, because the two cases need
    /// different words: re-picking a photo that is already here is harmless, while one held in
    /// a different album is the case where nothing the user can do from this screen will move
    /// it. A lookup that cannot answer is counted as elsewhere, which is the reading that at
    /// least sends the user looking.
    private func reportDuplicates(_ contentIds: [String]) async {
        guard !contentIds.isEmpty else { return }

        var alreadyHere = 0
        for contentId in contentIds where await isInThisAlbum(contentId: contentId) {
            alreadyHere += 1
        }
        let elsewhere = contentIds.count - alreadyHere

        if elsewhere == 0 {
            alertState = AlertState(
                title: "Already in This Album",
                message: alreadyHere == 1
                    ? "That photo is already in \(album.name), so it was not uploaded again."
                    : "Those \(alreadyHere) photos are already in \(album.name), so they were not uploaded again.",
            )
            return
        }

        let subject = elsewhere == 1
            ? "One of the photos you picked is"
            : "\(elsewhere) of the photos you picked are"
        let verb = elsewhere == 1 ? "it was" : "they were"

        alertState = AlertState(
            title: "Already on Your Server",
            message: "\(subject) already on your server, in another album. A photo can only be in one album, so \(verb) not added to \(album.name).",
        )
    }

    /// True when the server holds this contentId inside this album. A 404 — the answer for a
    /// photo filed under some other album — reads as false, as does any error.
    private func isInThisAlbum(contentId: String) async -> Bool {
        guard let apiClient else { return false }

        return await withCheckedContinuation { continuation in
            apiClient.lookupAssetByContentId(albumId: album.id, contentId: contentId) { result in
                switch result {
                case .success:
                    continuation.resume(returning: true)
                case .failure:
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Waiting for the server to finish processing

    /// Photos the worker pod has not finished with, and still might. Assets it has given up on
    /// are excluded — polling them would never end.
    private var pendingProcessingIds: [Int] {
        photos.filter { !$0.isThumbnailReady && !$0.processingFailed }.map(\.id)
    }

    /// Starts watching the server finish the photos it is still working on, if any.
    ///
    /// A freshly uploaded photo appears in the album before the worker has made its thumbnail;
    /// asking for one early answers `202` with no image. So the grid shows a "Processing…" tile
    /// and this keeps asking until the server says `DONE`, at which point the tile turns into
    /// the picture on its own. Idempotent — safe to call on every appearance and every reload.
    func startProcessingPollingIfNeeded() {
        guard processingPollTask == nil, !pendingProcessingIds.isEmpty else { return }
        processingPollTask = Task { [weak self] in
            await self?.pollProcessing()
        }
    }

    /// Stops the watch. Called when the screen goes away — nothing is looking at the result,
    /// and the next appearance starts it again from whatever the list says then.
    func stopProcessingPolling() {
        processingPollTask?.cancel()
        processingPollTask = nil
    }

    private func pollProcessing() async {
        // A ceiling rather than a forever loop: a worker that is genuinely stuck should leave
        // the user with a placeholder and a Refresh button, not a background poll that outlives
        // the reason for it.
        let deadline = Date().addingTimeInterval(300)

        while !Task.isCancelled, Date() < deadline {
            let pending = pendingProcessingIds
            guard !pending.isEmpty else { break }

            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }

            for id in pending {
                guard let status = await currentStatus(of: id) else { continue }
                apply(status: status, toPhotoId: id)
            }
        }

        processingPollTask = nil
    }

    /// Patches one row in place. The whole list is not reloaded because nothing else about it
    /// has changed, and an album can hold several hundred photos.
    private func apply(status: AssetProcessingStatus, toPhotoId id: Int) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].processingStatus = status.rawValue
    }

    private func currentStatus(of assetId: Int) async -> AssetProcessingStatus? {
        guard let apiClient else { return nil }

        return await withCheckedContinuation { continuation in
            apiClient.getAssetStatus(id: assetId) { result in
                continuation.resume(returning: try? result.get().processingStatus)
            }
        }
    }

    // MARK: - Single-photo actions

    /// Rotates one photo 90° left, the same single direction the web gallery offers.
    ///
    /// The server answers 202 and hands the job to the worker pod, so this waits for the
    /// asset to reach a terminal status before reloading. The reload is of the whole file
    /// list, not just the image: a rotate swaps the asset's `publicToken`, so the old URL
    /// stops being the photo's address.
    func rotate(_ photo: Photo) {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            return
        }

        guard !photo.isVideo else {
            alertState = AlertState(
                title: "Cannot Rotate",
                message: "Videos cannot be rotated.",
            )
            return
        }

        guard !rotatingPhotoIds.contains(photo.id) else { return }
        rotatingPhotoIds.insert(photo.id)

        apiClient.rotateImageLeft(id: photo.id) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                if case let .failure(error) = result {
                    self.rotatingPhotoIds.remove(photo.id)
                    self.handleError(error)
                    return
                }

                let outcome = await self.awaitProcessing(of: photo.id)
                await self.refreshPhotos()
                self.rotatingPhotoIds.remove(photo.id)

                switch outcome {
                case .done:
                    break
                case let .failed(message):
                    self.alertState = AlertState(title: "Rotation Failed", message: message)
                case .timedOut:
                    self.alertState = AlertState(
                        title: "Still Rotating",
                        message: "The server is taking longer than usual. Pull down to refresh in a moment.",
                    )
                }
            }
        }
    }

    /// Deletes one photo. The caller is responsible for confirming first — this is
    /// irreversible, the server drops the stored objects along with the row.
    ///
    /// The photo is removed from the grid on success rather than by reloading the list: the
    /// server has already forgotten it, and a reload would only be a slower way to say so.
    func delete(_ photo: Photo) {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            return
        }

        apiClient.deleteFile(id: photo.id) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.photos.removeAll { $0.id == photo.id }
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }

    private enum ProcessingOutcome {
        case done
        case failed(String)
        case timedOut
    }

    /// Polls until the worker reaches a terminal status. Same 2 s cadence and 60 s ceiling the
    /// web gallery uses after a rotate. Network errors are ridden out rather than reported —
    /// only the deadline ends the wait.
    private func awaitProcessing(of assetId: Int) async -> ProcessingOutcome {
        guard let apiClient else { return .timedOut }

        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            let status: AssetProcessingStatusResponse? = await withCheckedContinuation { continuation in
                apiClient.getAssetStatus(id: assetId) { result in
                    continuation.resume(returning: try? result.get())
                }
            }

            if let status, status.processingStatus.isTerminal {
                switch status.processingStatus {
                case .done:
                    return .done
                default:
                    return .failed(status.error ?? "The server could not rotate this photo.")
                }
            }

            try? await Task.sleep(for: .seconds(2))
        }
        return .timedOut
    }

    // MARK: - Refreshing

    /// The Refresh button: reload the file list *and* every image in it.
    func reloadPhotosAndImages() {
        invalidateImages()
        fetchPhotos()
    }

    /// Pull-to-refresh. Stays awaited so the spinner tracks the work.
    func reloadPhotosAndImagesAwaiting() async {
        invalidateImages()
        await refreshPhotos()
    }

    /// Clears the decoded-image cache and tells the visible cells to fetch again. Both halves
    /// are needed: the token reaches the cells on screen, the cache purge stops a cell that is
    /// recreated later from picking a stale copy back up.
    private func invalidateImages() {
        ImageCache.removeAll()
        imageReloadToken &+= 1
    }

    // MARK: - Uploading

    /// Handles the upload button: makes sure the photo library is reachable, then opens the
    /// picker. Access is requested here rather than at launch, because this is the first place
    /// the app needs to *read* the library on the user's behalf.
    func requestUpload() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            isPickerPresented = true

        case .notDetermined:
            // `@Sendable` on purpose. Photos calls this handler on a background queue, and its
            // block is not marked `NS_SWIFT_SENDABLE`, so under `SWIFT_APPROACHABLE_CONCURRENCY`
            // a bare closure written inside this `@MainActor` type would inherit main-actor
            // isolation and trip `BUG IN CLIENT OF LIBDISPATCH` the moment Photos answers.
            // `@Sendable` gives it no isolation to inherit; the hop to main is the `Task` below.
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { @Sendable [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    if status == .authorized || status == .limited {
                        self.isPickerPresented = true
                    } else {
                        self.showPhotoAccessAlert()
                    }
                }
            }

        default:
            showPhotoAccessAlert()
        }
    }

    private func showPhotoAccessAlert() {
        alertState = AlertState(
            title: "Photo Access Needed",
            message: "Zyncloud cannot open your photo library. Allow access for Zyncloud in the iOS Settings app, then try again.",
        )
    }

    /// Sends the photos picked in the system picker to *this* album.
    ///
    /// Takes plain library identifiers rather than `PhotosPickerItem`s so PhotosUI — and with
    /// it SwiftUI — stays on the view side. The uploader works in `PHAsset`s, because that is
    /// what gives it the original file, the content id used for dedupe, and background upload.
    ///
    /// - Parameter pickedCount: how many items the user actually chose. An identifier list
    ///   shorter than this means the picker could not name the assets, which happens when the
    ///   app has no photo-library access — a different fault from picking nothing.
    func upload(assetIdentifiers identifiers: [String], pickedCount: Int) {
        guard pickedCount > 0 else { return }

        guard !identifiers.isEmpty else {
            showPhotoAccessAlert()
            return
        }

        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetched.count)
        fetched.enumerateObjects { asset, _, _ in assets.append(asset) }

        guard !assets.isEmpty else {
            alertState = AlertState(
                title: "Nothing to Upload",
                message: "Those photos could not be read from your library.",
            )
            return
        }

        syncCoordinator.uploadToAlbum(assets: assets, albumId: album.id)
    }

    // MARK: - Sorting

    /// Runs one of the album-wide sorts on the server, then reloads so the grid shows the new
    /// order. The confirmation prompt lives in the view, same split as the web app.
    func reorder(by action: AlbumSortAction) {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            return
        }

        isReordering = true

        apiClient.reorderAlbum(albumId: album.id, by: action) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                switch result {
                case let .success(count):
                    Task { @MainActor in
                        await self.refreshPhotos()
                        self.isReordering = false
                        self.showSuccess(message: "Reordered \(count) files by \(action.title.lowercased()).")
                    }

                case let .failure(error):
                    self.isReordering = false
                    self.handleError(error)
                }
            }
        }
    }

    func toggleArrangeByHand() {
        isArrangingByHand.toggle()
    }

    /// Applies a hand move locally, then persists the whole album order. On failure the photos
    /// are reloaded from the server so the list can never keep an order the server rejected.
    func movePhotos(from source: IndexSet, to destination: Int) {
        guard let apiClient else { return }

        let previous = photos
        photos.move(fromOffsets: source, toOffset: destination)

        let fileIds = photos.map(\.id)
        isReordering = true

        apiClient.reorderFiles(fileIds: fileIds) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                self.isReordering = false

                if case let .failure(error) = result {
                    self.photos = previous
                    self.handleError(error)
                }
            }
        }
    }

    // MARK: - Map

    /// True when any photo in this album carries a location, which is what makes a map worth
    /// offering. A location lives only in the original, so photos uploaded before GPS extraction
    /// existed — and those whose original retention has purged — never have one.
    var hasLocatedPhotos: Bool {
        !PhotoMapPlaces.located(in: photos).isEmpty
    }

    /// Stores the framing the owner has panned and pinched to, so everyone opening this album's
    /// map — including share-link visitors — starts there.
    ///
    /// The server's answer carries the album back with the four fields set, so the new view is
    /// taken from that rather than from what was sent: `MapView.of` clamps an over-wide span, and
    /// believing our own copy would leave the screen disagreeing with what was stored.
    func saveMapView(_ view: SavedMapView) {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            return
        }

        apiClient.setMapView(albumId: album.id, view: view) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case let .success(album):
                    self.savedMapView = album.savedMapView
                    self.showSuccess(message: "This album's map now opens at this view.")
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }

    /// Puts the map back to framing every pin.
    func clearMapView() {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            return
        }

        apiClient.clearMapView(albumId: album.id) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case let .success(album):
                    self.savedMapView = album.savedMapView
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }

    // MARK: - Media URLs

    func thumbnailURL(for photo: Photo) -> URL? {
        // Use public token to access image via /api/i/{token}?size=thumbnail
        // This endpoint doesn't require authentication
        let baseURL = AppConfiguration.apiBaseURL
        var components = URLComponents(url: baseURL.appendingPathComponent("api/i/\(photo.publicToken)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "size", value: "thumbnail")]

        if let url = components?.url {
            AppLog.api.debug("Thumbnail URL for \(photo.originalName): \(url.absoluteString)")
            return url
        } else {
            AppLog.api.error("Could not build a thumbnail URL for \(photo.originalName)")
            return nil
        }
    }

    /// Playback URL for a video asset.
    ///
    /// Deliberately carries **no** `size` parameter: with no size the server hands back the
    /// transcoded H.264 rendition when one exists and the untouched original otherwise. Any
    /// size value would ask for an image derivative a video does not have — that is what made
    /// tapping a video show "Failed". Mirrors what the web Lightbox does.
    func videoURL(for photo: Photo) -> URL? {
        let baseURL = AppConfiguration.apiBaseURL
        return URLComponents(
            url: baseURL.appendingPathComponent("api/i/\(photo.publicToken)"),
            resolvingAgainstBaseURL: false,
        )?.url
    }

    // MARK: - Album Actions

    /// The public link for this album, or nil when the server gave it no share token.
    var shareURL: URL? {
        guard let shareToken = album.shareToken else { return nil }
        return AppConfiguration.publicAlbumURL(shareToken: shareToken)
    }

    /// Deletes the whole album, exactly as the web app's album delete does. The view asks for
    /// confirmation first and closes the screen on success — what it was showing is gone.
    func deleteAlbum(completion: @escaping @Sendable @MainActor (Bool) -> Void) {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            completion(false)
            return
        }

        isLoading = true

        apiClient.deleteAlbum(id: album.id) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success:
                    completion(true)
                case let .failure(error):
                    self.handleError(error)
                    completion(false)
                }
            }
        }
    }

    func fullImageURL(for photo: Photo) -> URL? {
        // Use public token to access original/large image via /api/i/{token}
        let baseURL = AppConfiguration.apiBaseURL
        var components = URLComponents(url: baseURL.appendingPathComponent("api/i/\(photo.publicToken)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "size", value: "large")]
        return components?.url
    }
}
