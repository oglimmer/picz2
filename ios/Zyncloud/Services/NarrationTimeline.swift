import Foundation

/// Which of an album's assets a narration walks, and when each one was on screen.
///
/// Both halves used to live inline in ``NarrationRecorderViewModel``, reading
/// `ProcessInfo.processInfo.systemUptime` directly and mutating private state that nothing could
/// reach from outside. The timings *are* the feature — a slideshow plays back against them — so
/// they are worth being able to test.
enum NarrationSlides {
    /// The assets a slideshow may use: everything the worker pod has finished with.
    ///
    /// A "Processing…" placeholder is nothing to narrate, and a timing entry pointing at one
    /// would aim playback at a slide the gallery may render differently once the derivative
    /// exists.
    static func ready(from photos: [Photo]) -> [Photo] {
        photos.filter { $0.isThumbnailReady && !$0.processingFailed }
    }

    /// The tags worth offering as a filter, with how many ready assets each one covers.
    ///
    /// Sorted by name, case-insensitively, so the list does not reshuffle between runs.
    static func tagCounts(for photos: [Photo]) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for photo in ready(from: photos) {
            for tag in photo.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The filter to keep, given the one that was selected and the tags now available.
    ///
    /// A filter the album no longer has any ready asset for would start an empty slideshow, so
    /// it falls back to "all photos" rather than to nothing.
    static func survivingFilter(_ selected: String?, among available: [(name: String, count: Int)]) -> String? {
        guard let selected else { return nil }
        return available.contains { $0.name == selected } ? selected : nil
    }

    /// The slides a recording will actually walk.
    ///
    /// Filtered on the phone rather than by refetching with `?tag=`: the server applies the
    /// identical `tags.contains` test, and the full list is already here.
    static func slides(from photos: [Photo], tag: String?) -> [Photo] {
        let ready = ready(from: photos)
        guard let tag else { return ready }
        return ready.filter { $0.tags.contains(tag) }
    }
}

/// Accumulates "slide N was on screen from X ms for Y ms" while a narration is being recorded.
///
/// The clock is a parameter rather than a call to `ProcessInfo.processInfo.systemUptime`, so the
/// arithmetic can be checked without recording anything. The app still passes system uptime,
/// which is monotonic — a wall clock the user or the network can step backwards would put slides
/// out of order on playback.
struct NarrationTimeline {
    /// System uptime, in seconds, when recording began.
    private let startedAt: TimeInterval

    /// When the slide now on screen came up.
    private var currentSlideStartedAt: TimeInterval

    private(set) var timings: [RecordingUploadRequest.ImageTiming] = []

    init(startedAt: TimeInterval) {
        self.startedAt = startedAt
        currentSlideStartedAt = startedAt
    }

    /// Opens an entry for a slide that has just come on screen. Its duration is filled in later,
    /// by ``closeCurrentSlide(at:)``.
    mutating func openSlide(fileId: Int, at now: TimeInterval) {
        currentSlideStartedAt = now
        timings.append(
            RecordingUploadRequest.ImageTiming(
                fileId: fileId,
                startTimeMs: Self.milliseconds(from: startedAt, to: now),
                durationMs: 0,
            ),
        )
    }

    /// Writes the duration of the slide now on screen.
    ///
    /// The web app leaves this null until the next slide starts; here it is always filled in,
    /// because the server column is not nullable in any useful sense and a null would play back
    /// as a zero-length slide anyway. Harmless before the first slide, and harmless twice — the
    /// Stop button and the auto-stop at the end of the list can both reach it.
    mutating func closeCurrentSlide(at now: TimeInterval) {
        guard let last = timings.last else { return }
        timings[timings.count - 1] = RecordingUploadRequest.ImageTiming(
            fileId: last.fileId,
            startTimeMs: last.startTimeMs,
            durationMs: Self.milliseconds(from: currentSlideStartedAt, to: now),
        )
    }

    /// How long the whole recording ran.
    func totalMilliseconds(at now: TimeInterval) -> Int {
        Self.milliseconds(from: startedAt, to: now)
    }

    /// Never negative. A monotonic clock should not go backwards, but a zero-length slide is a
    /// far better failure than a negative one, which the server would store and playback would
    /// read as a slide that ends before it starts.
    private static func milliseconds(from start: TimeInterval, to end: TimeInterval) -> Int {
        max(0, Int((end - start) * 1000))
    }
}
