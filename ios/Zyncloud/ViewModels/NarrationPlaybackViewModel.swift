import AVFoundation
import Combine
import Foundation

/// Plays a saved commentary back: the voice from the server, the album's own pictures, advanced
/// by the timings that were recorded with it.
///
/// The audio is the clock. Slides are chosen from the player's current time rather than from a
/// timer of our own, so a slow network — which stalls the audio — never lets the pictures run
/// ahead of the narrator.
@MainActor
final class NarrationPlaybackViewModel: ObservableObject {
    /// The slides this recording names, already resolved to assets the album still holds.
    struct Slide: Identifiable {
        let photo: Photo
        let startMs: Int
        var id: Int {
            photo.id
        }
    }

    @Published private(set) var slides: [Slide] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var elapsedMs: Int = 0
    @Published private(set) var hasFinished: Bool = false

    /// Set when the audio cannot be reached at all. Shown in place of the transport, because a
    /// silent slideshow is not what the user asked to hear.
    @Published private(set) var loadError: String?

    /// Set while the server is still making the iPhone-playable copy of this commentary. Shown
    /// instead of the transport, and instead of an error — nothing is wrong, it is just not there
    /// yet, and the wait ends by itself.
    @Published private(set) var preparingMessage: String?

    /// Assets the recording names that the album no longer holds — deleted since it was made.
    /// Reported so a short preview does not look like a bug.
    let missingSlideCount: Int

    let recording: RecordingInfo
    let totalMs: Int

    private let player: AVPlayer
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private let apiClient: APIClient?
    private var prepareTask: Task<Void, Never>?

    /// How long to keep asking before giving up. One transcode takes about a minute on the
    /// server, so two minutes covers a cold start plus a queue of one ahead of it.
    private static let readinessPollSeconds: UInt64 = 5
    private static let readinessAttempts = 24

    /// - Parameter photosByID: the album's assets, so a `fileId` in the recording can be turned
    ///   back into something to render.
    init(recording: RecordingInfo, photosByID: [Int: Photo]) {
        self.recording = recording
        totalMs = recording.durationMs ?? 0

        let entries = recording.orderedImages
        let resolved: [Slide] = entries.compactMap { entry in
            guard let photo = photosByID[entry.fileId] else { return nil }
            return Slide(photo: photo, startMs: entry.startTimeMs ?? 0)
        }
        missingSlideCount = entries.count - resolved.count
        player = AVPlayer()
        slides = resolved
        if let credentials = KeychainHelper.shared.load() {
            apiClient = APIClient(username: credentials.username, password: credentials.password)
        } else {
            apiClient = nil
        }
    }

    var currentSlide: Photo? {
        slides.indices.contains(currentIndex) ? slides[currentIndex].photo : nil
    }

    var progress: Double {
        guard totalMs > 0 else { return 0 }
        return min(Double(elapsedMs) / Double(totalMs), 1)
    }

    var elapsedLabel: String {
        NarrationRecorderViewModel.durationLabel(elapsedMs)
    }

    var totalLabel: String {
        NarrationRecorderViewModel.durationLabel(totalMs)
    }

    // MARK: - Transport

    /// Waits for the server to have an iPhone-playable copy, then attaches the audio and starts.
    /// Called once, when the preview appears.
    ///
    /// The wait is the whole point. The server keeps the master as Opus in a WebM container, which
    /// Apple cannot decode, and converts it on a background worker — about a minute per
    /// commentary. Handing `AVPlayer` a URL that is not ready yet just produces a decode error it
    /// cannot explain, which is what used to make an old commentary fail on the first try and work
    /// on the second.
    func start() {
        // SwiftUI can send `onAppear` more than once for the same view; one wait is enough.
        guard prepareTask == nil else { return }

        guard recording.audioURL != nil, let publicToken = recording.publicToken else {
            loadError = "This commentary has no audio link on the server."
            return
        }

        prepareTask = Task { [weak self] in
            await self?.waitForAudioThenPlay(publicToken: publicToken)
        }
    }

    private func waitForAudioThenPlay(publicToken: String) async {
        guard let apiClient else {
            // Not logged in is not a reason to refuse: the audio route is public. Try it directly.
            attachAndPlay()
            return
        }

        for _ in 0 ..< Self.readinessAttempts {
            if Task.isCancelled { return }

            switch await readiness(from: apiClient, publicToken: publicToken) {
            case .ready:
                preparingMessage = nil
                attachAndPlay()
                return
            case .failed:
                preparingMessage = nil
                loadError = "This commentary could not be converted into a format iPhone can play."
                return
            case .notReady, .unreachable:
                preparingMessage = "Preparing this commentary for iPhone. This takes about a minute."
            }

            try? await Task.sleep(nanoseconds: Self.readinessPollSeconds * 1_000_000_000)
        }

        preparingMessage = nil
        loadError = "This commentary is still being prepared. Please close this and try again shortly."
    }

    private func readiness(
        from apiClient: APIClient,
        publicToken: String,
    ) async -> RecordingAudioReadiness {
        await withCheckedContinuation { continuation in
            apiClient.fetchRecordingAudioStatus(publicToken: publicToken) { readiness in
                continuation.resume(returning: readiness)
            }
        }
    }

    /// Hands the audio to `AVPlayer` and starts. Only called once the server says it is playable.
    private func attachAndPlay() {
        guard let url = recording.audioURL else {
            loadError = "This commentary has no audio link on the server."
            return
        }

        // `.playback` rather than the recorder's `.playAndRecord`: this only plays, and
        // `.playback` is the category that ignores the ring/silent switch — a preview the user
        // pressed play on should be audible.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleReachedEnd()
            }
        }

        // Without this the failure is silent: `play()` on an item the device cannot decode is a
        // no-op, so the first slide sits there, the clock never moves, and Play looks broken.
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard item.status == .failed else { return }
                self?.reportFailure(item.error)
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main,
        ) { [weak self] time in
            Task { @MainActor in
                self?.handleTick(seconds: time.seconds)
            }
        }

        player.play()
        isPlaying = true
    }

    func togglePlayPause() {
        guard loadError == nil, preparingMessage == nil else { return }

        if hasFinished {
            restart()
            return
        }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func restart() {
        hasFinished = false
        currentIndex = 0
        elapsedMs = 0
        player.seek(to: .zero)
        player.play()
        isPlaying = true
    }

    /// Releases the player and the audio route. Must be called when the preview closes — an
    /// abandoned time observer keeps the item, and the item keeps the network connection.
    func stop() {
        prepareTask?.cancel()
        prepareTask = nil
        player.pause()
        isPlaying = false

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        player.replaceCurrentItem(with: nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Following the audio

    private func handleTick(seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        elapsedMs = Int(seconds * 1000)

        // The last slide that has started is the one on screen. Chosen this way rather than by
        // testing each slide's own window, so a gap in the timings — or a duration the recorder
        // could not close — still leaves a picture up instead of a black screen.
        guard let index = slides.lastIndex(where: { $0.startMs <= elapsedMs }) else { return }
        if index != currentIndex {
            currentIndex = index
        }
    }

    /// Says the audio could not be played, and stops pretending the transport works.
    private func reportFailure(_ error: Error?) {
        isPlaying = false
        player.pause()
        loadError = "This commentary's audio cannot be played on iPhone. "
            + (error?.localizedDescription ?? "The server stored it in a format iOS cannot decode.")
    }

    private func handleReachedEnd() {
        isPlaying = false
        hasFinished = true
        elapsedMs = totalMs
    }
}
