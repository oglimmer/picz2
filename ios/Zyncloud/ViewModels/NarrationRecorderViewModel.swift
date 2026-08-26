import Foundation

/// Drives the album's audio-commentary feature: pick a tag filter and a language, walk the
/// matching assets one tap at a time, and record the voice over the top.
///
/// Mirrors the web gallery's `useSlideshow` composable — same wire payload, same one-recording-
/// per-(tag, language) rule — so a narration made on the phone plays back in the browser.
@MainActor
final class NarrationRecorderViewModel: ViewModelProtocol {
    // MARK: - Where the user is

    enum Phase: Equatable {
        /// Choosing a filter and a language.
        case setup
        /// The slideshow is on screen and the microphone is live.
        case recording
        /// Recording stopped, upload in flight.
        case saving
        /// Upload failed; the audio is still on disk so the user can retry.
        case saveFailed
    }

    @Published private(set) var phase: Phase = .setup
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?

    // MARK: - Setup choices

    /// Tags that at least one asset in this album actually carries, with their counts.
    /// `no_tag` is left out, exactly as the web gallery's tag dropdown does.
    @Published private(set) var availableTags: [TagCount] = []

    /// nil means "every photo in the album" — the same as the web app's empty filter, and it is
    /// sent to the server as a null `filterTag`.
    @Published var selectedTag: String?

    @Published var selectedLanguage: NarrationLanguage = .language1
    @Published private(set) var language1Name: String = "Language 1"
    @Published private(set) var language2Name: String = "Language 2"

    /// Narrations the album already has. Used to warn before recording over one.
    @Published private(set) var existingRecordings: [RecordingInfo] = []

    // MARK: - Slideshow state

    /// The assets the slideshow walks, in album order, already narrowed to the chosen tag.
    @Published private(set) var slides: [Photo] = []
    @Published private(set) var currentIndex: Int = 0

    /// Seconds of audio recorded so far, refreshed once a second so the overlay can show it.
    @Published private(set) var elapsedSeconds: Int = 0

    struct TagCount: Identifiable, Hashable {
        let name: String
        let count: Int
        var id: String {
            name
        }
    }

    let album: Album

    private let recorder = NarrationAudioRecorder()
    private var apiClient: APIClient?

    /// Every asset in the album, kept so switching the tag filter needs no round trip.
    private var allPhotos: [Photo] = []

    /// When each slide was on screen. The clock it is fed is `systemUptime`, which is monotonic
    /// unlike `Date`: the timings are the payload's whole value, and a clock the user or the
    /// network can step backwards would put slides out of order on playback.
    private var timeline = NarrationTimeline(startedAt: 0)

    /// Recording start, kept for the elapsed-seconds clock the screen shows.
    private var recordingStartedAt: TimeInterval = 0

    private var tickTask: Task<Void, Never>?

    /// Kept after a failed save so Retry can send the same file. Cleared on success or Discard.
    private var pendingAudioURL: URL?
    private var pendingPayload: RecordingUploadRequest?

    /// How many assets an unfiltered slideshow would walk. Shown next to the "All photos"
    /// option so the count is there before the option is chosen.
    var slidesCountForAllPhotos: Int {
        readyPhotos.count
    }

    /// The album's assets minus anything the worker pod has not finished with. A "Processing…"
    /// placeholder is nothing to narrate, and a timing entry for one would point playback at a
    /// slide the gallery may render differently once the derivative exists. Everything the
    /// setup screen counts and the slideshow walks comes from here.
    private var readyPhotos: [Photo] {
        NarrationSlides.ready(from: allPhotos)
    }

    var currentSlide: Photo? {
        slides.indices.contains(currentIndex) ? slides[currentIndex] : nil
    }

    func name(of language: NarrationLanguage) -> String {
        language == .language1 ? language1Name : language2Name
    }

    // MARK: - Media URLs

    func imageURL(for photo: Photo) -> URL? {
        AssetURLs.image(for: photo)
    }

    func videoURL(for photo: Photo) -> URL? {
        AssetURLs.video(for: photo)
    }

    /// True when the album already holds a narration for the chosen filter and language.
    var hasExistingRecordingForSelection: Bool {
        existingRecording(for: selectedTag, language: selectedLanguage) != nil
    }

    init(album: Album) {
        self.album = album
        if let credentials = KeychainHelper.shared.load() {
            apiClient = APIClient(username: credentials.username, password: credentials.password)
        }
    }

    // MARK: - Loading

    /// Pulls everything the setup screen needs: the album's assets (for the tag list), the two
    /// language names, and the narrations already saved.
    func load() {
        guard let apiClient else {
            alertState = AlertState(title: "Error", message: "Not authenticated. Please log in again.")
            return
        }

        isLoading = true

        apiClient.fetchFiles(albumId: album.id) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case let .success(response):
                    self.allPhotos = response.files
                    self.rebuildTags()
                    self.applyFilter()
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }

        apiClient.fetchLanguageSettings { [weak self] result in
            Task { @MainActor in
                guard let self, case let .success(response) = result else { return }
                // The server answers with nulls until the user has named them; the web app
                // falls back to the same two defaults.
                self.language1Name = response.language1 ?? "German"
                self.language2Name = response.language2 ?? "English"
            }
        }

        reloadRecordings()
    }

    func reloadRecordings() {
        guard let apiClient else { return }

        apiClient.fetchRecordings(albumId: album.id) { [weak self] result in
            Task { @MainActor in
                guard let self, case let .success(recordings) = result else { return }
                self.existingRecordings = recordings
            }
        }
    }

    private func rebuildTags() {
        let counts = NarrationSlides.tagCounts(for: allPhotos)
        availableTags = counts.map { TagCount(name: $0.name, count: $0.count) }
        selectedTag = NarrationSlides.survivingFilter(selectedTag, among: counts)
    }

    /// Narrows the slideshow to the chosen tag. Filtered on the phone rather than by refetching
    /// with `?tag=` — the server applies the identical `tags.contains` test, and the full list is
    /// already here.
    func applyFilter() {
        slides = NarrationSlides.slides(from: allPhotos, tag: selectedTag)
    }

    /// The album's assets keyed by id, so a saved commentary's `fileId` can be turned back
    /// into something to render. Built from the unfiltered list — a commentary made under one
    /// tag filter must still resolve while a different filter is selected.
    var photosByID: [Int: Photo] {
        Dictionary(allPhotos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func existingRecording(for tag: String?, language: NarrationLanguage) -> RecordingInfo? {
        existingRecordings.first { $0.filterTag == tag && $0.language == language.rawValue }
    }

    // MARK: - Recording

    /// Asks for the microphone, starts the audio, and puts the first asset on screen.
    ///
    /// The caller has already dealt with an existing narration for this filter and language —
    /// the server keeps both, and the gallery would then have two rows to choose between.
    func startRecording() async {
        guard phase == .setup else { return }
        guard !slides.isEmpty else {
            alertState = AlertState(
                title: "Nothing to Show",
                message: selectedTag == nil
                    ? "This album has no photos yet."
                    : "No photos in this album carry the tag \"\(selectedTag ?? "")\".",
            )
            return
        }

        guard await NarrationAudioRecorder.requestPermission() else {
            alertState = AlertState(
                title: "Microphone Needed",
                message: NarrationAudioRecorder.RecorderError.permissionDenied.errorDescription ?? "",
            )
            return
        }

        do {
            try recorder.start()
        } catch {
            alertState = AlertState(title: "Could Not Record", message: error.localizedDescription)
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        recordingStartedAt = now
        timeline = NarrationTimeline(startedAt: now)
        currentIndex = 0
        elapsedSeconds = 0
        phase = .recording

        trackSlideStart()
        startTicking()
    }

    /// A tap anywhere on the slideshow. Closes the timing of the slide leaving the screen and
    /// opens the next one; running past the last slide ends the recording, which is what the
    /// web app does too.
    func advance() {
        guard phase == .recording else { return }

        closeCurrentTiming()

        guard currentIndex + 1 < slides.count else {
            finish()
            return
        }

        currentIndex += 1
        trackSlideStart()
    }

    /// Stops the microphone and uploads. Safe to call twice — the second call is ignored, which
    /// matters because the Stop button and the auto-stop at the end of the list can race.
    func finish() {
        guard phase == .recording else { return }

        closeCurrentTiming()
        stopTicking()
        phase = .saving

        guard let audioURL = recorder.stop() else {
            phase = .setup
            alertState = AlertState(title: "Nothing Recorded", message: "No audio was captured.")
            return
        }

        guard apiClient != nil else {
            phase = .setup
            recorder.discard(audioURL)
            alertState = AlertState(title: "Error", message: "Not authenticated. Please log in again.")
            return
        }

        let totalMs = timeline.totalMilliseconds(at: ProcessInfo.processInfo.systemUptime)
        let payload = RecordingUploadRequest(
            filterTag: selectedTag,
            language: selectedLanguage.rawValue,
            durationMs: totalMs,
            images: timeline.timings,
        )

        pendingAudioURL = audioURL
        pendingPayload = payload
        sendPendingSave()
    }

    /// Re-sends the audio kept after a failed save. No-op if there is nothing to send.
    func retrySave() {
        guard phase == .saveFailed, pendingAudioURL != nil, pendingPayload != nil else { return }
        phase = .saving
        sendPendingSave()
    }

    /// Throws away a failed recording. The user has to start over.
    func discardFailedSave() {
        if let pendingAudioURL {
            recorder.discard(pendingAudioURL)
        }
        pendingAudioURL = nil
        pendingPayload = nil
        phase = .setup
    }

    private func sendPendingSave() {
        guard let audioURL = pendingAudioURL, let payload = pendingPayload else {
            phase = .setup
            return
        }
        guard let apiClient else {
            // Credentials went away between recording and sending. Say so rather than dropping
            // back to setup with the recording silently stranded on disk.
            recorder.discard(audioURL)
            pendingAudioURL = nil
            pendingPayload = nil
            phase = .setup
            alertState = AlertState(title: "Error", message: "Not authenticated. Please log in again.")
            return
        }

        apiClient.uploadRecording(albumId: album.id, audioFileURL: audioURL, request: payload) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                switch result {
                case .success:
                    self.recorder.discard(audioURL)
                    self.pendingAudioURL = nil
                    self.pendingPayload = nil
                    self.phase = .setup
                    self.reloadRecordings()
                    let totalMs = payload.durationMs
                    self.showSuccess(
                        title: "Narration Saved",
                        message: "\(self.slides.count) slides, \(Self.durationLabel(totalMs)) of audio.",
                    )
                case let .failure(error):
                    self.phase = .saveFailed
                    let message = (error as? AppError)?.errorDescription ?? error.localizedDescription
                    self.alertState = AlertState(
                        title: "Couldn't Save Commentary",
                        message: message,
                        primaryButton: AlertState.AlertButton(title: "Retry") { [weak self] in
                            self?.retrySave()
                        },
                        secondaryButton: AlertState.AlertButton(title: "Discard") { [weak self] in
                            self?.discardFailedSave()
                        },
                    )
                }
            }
        }
    }

    /// Backs out without saving. The audio is deleted — nothing was ever sent.
    func cancelRecording() {
        guard phase == .recording else { return }
        stopTicking()
        recorder.cancel()
        timeline = NarrationTimeline(startedAt: recordingStartedAt)
        phase = .setup
    }

    func deleteRecording(_ recording: RecordingInfo) {
        guard let apiClient else { return }

        apiClient.deleteRecording(id: recording.id) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.existingRecordings.removeAll { $0.id == recording.id }
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }
}

/// Slide timings and the recording clock. Split out only because the type has grown past
/// the house length limit — these are as much a part of the recorder as anything above.
extension NarrationRecorderViewModel {
    // MARK: - Timings

    private func trackSlideStart() {
        guard let slide = currentSlide else { return }
        timeline.openSlide(fileId: slide.id, at: ProcessInfo.processInfo.systemUptime)
    }

    private func closeCurrentTiming() {
        timeline.closeCurrentSlide(at: ProcessInfo.processInfo.systemUptime)
    }

    // MARK: - Elapsed clock

    private func startTicking() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.phase == .recording else { return }
                    self.elapsedSeconds = Int(ProcessInfo.processInfo.systemUptime - self.recordingStartedAt)
                }
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    static func durationLabel(_ milliseconds: Int) -> String {
        let total = milliseconds / 1000
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var elapsedLabel: String {
        String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }
}
