import AVFoundation
import Foundation

/// Records the voice track for a slideshow narration.
///
/// **Why AAC in an `.m4a` and not Opus:** iOS has no Opus encoder, so the phone records the one
/// format `AVAudioRecorder` does well. The server re-encodes every upload with ffmpeg to Opus
/// regardless of what came in (`AudioReencodingService`), so the stored file ends up identical to
/// a browser-made one. See ``NarrationAudioRecorder/uploadFilename`` for the naming that goes
/// with that.
/// - Note: `@MainActor` — one view model owns one of these and drives it from the recording
///   screen. Only the audio-session call inside ``start()`` leaves the main thread, and it does
///   so through ``AudioSessionConfigurator``, which is where that hop belongs.
@MainActor
final class NarrationAudioRecorder {
    enum RecorderError: LocalizedError {
        case permissionDenied
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "Picz cannot use the microphone. Allow microphone access for Picz in the iOS Settings app, then try again."
            case .couldNotStart:
                "The microphone could not be started."
            }
        }
    }

    /// The name the audio is uploaded under.
    ///
    /// Deliberately `.webm`, although the bytes leaving the phone are AAC. The server derives the
    /// *stored* file's extension from this name and then hands the file to ffmpeg, which probes
    /// the real format from the content — so the extension describes the file after re-encoding
    /// (WebM/Opus), which is what every player then asks for. Naming it `.m4a` would leave an
    /// Opus stream in a container the web player will not touch.
    /// `nonisolated` because it is a constant string that the upload path reads while building
    /// a multipart body on a background thread. Nothing about it needs the main actor.
    nonisolated static let uploadFilename = "recording.webm"

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    /// Asks for the microphone once, and answers from the stored decision every time after.
    static func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            true
        case .denied:
            false
        default:
            await AVAudioApplication.requestRecordPermission()
        }
    }

    /// Starts recording to a fresh file in the caches directory.
    ///
    /// The session is `.playAndRecord` rather than `.record` because the slideshow plays videos
    /// while this runs. They are muted, but a video item still wants a session that permits
    /// playback — `.record` alone stalls it.
    func start() async throws {
        // Awaited rather than called inline: see ``AudioSessionConfigurator``. Recording must not
        // begin before the route is up, so this one is waited for.
        try await AudioSessionConfigurator.activate(
            category: .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothHFP],
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("narration-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else {
            throw RecorderError.couldNotStart
        }

        self.recorder = recorder
        recordingURL = url
    }

    /// Stops and hands back the finished file. Nil when nothing was recording.
    func stop() -> URL? {
        guard let recorder, recorder.isRecording else { return recordingURL }
        recorder.stop()
        self.recorder = nil
        deactivateSession()
        return recordingURL
    }

    /// Stops and throws the audio away. Used when the user backs out.
    func cancel() {
        recorder?.stop()
        recorder = nil
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        deactivateSession()
    }

    /// Deletes a file handed out by ``stop()``. The caller owns it from that point — this is
    /// how it says it is done with it, once the upload has finished either way.
    func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        if recordingURL == url {
            recordingURL = nil
        }
    }

    /// Hands the audio route back. Without it the phone stays in the record category, which
    /// routes later playback to the earpiece.
    private func deactivateSession() {
        // Fired and forgotten: nothing here waits on the route coming down, and blocking the
        // caller — which is the main thread, mid-teardown — is the whole problem being avoided.
        Task { await AudioSessionConfigurator.deactivate() }
    }
}
