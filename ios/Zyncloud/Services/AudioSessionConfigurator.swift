import AVFoundation

/// Turns the shared audio session on and off, **never on the main thread**.
///
/// `AVAudioSession.setCategory` and `setActive` are synchronous calls into the audio server, and
/// they block until the hardware route has been negotiated. That is tens of milliseconds on a
/// good day and much longer when Bluetooth is involved or another app has to be told to stop.
/// Xcode's Thread Performance Checker reports it as "AVAudioSession Hang Risk", and it is right:
/// both call sites here run while a full-screen slideshow is on screen, so a blocked main thread
/// is a visibly stuck slideshow.
///
/// `@concurrent` is what actually moves the work. This project builds with
/// `SWIFT_APPROACHABLE_CONCURRENCY`, under which a plain `nonisolated async` function runs on the
/// **caller's** actor — so without the attribute these would still block main, and the `await`
/// would be pure decoration.
enum AudioSessionConfigurator {
    /// Sets the category and activates. Awaited, because playback must not start until the route
    /// is up — starting first gets the first second out of the wrong speaker.
    @concurrent
    static func activate(
        category: AVAudioSession.Category,
        mode: AVAudioSession.Mode = .default,
        options: AVAudioSession.CategoryOptions = [],
    ) async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(category, mode: mode, options: options)
        try session.setActive(true)
    }

    /// Hands the audio route back.
    ///
    /// Deliberately not thrown from and safe to fire and forget — nothing the user sees depends
    /// on it finishing, and it must not hold up tearing a screen down. It does still matter:
    /// leaving the session in `.playAndRecord` routes the *next* thing the phone plays to the
    /// earpiece instead of the speaker.
    @concurrent
    static func deactivate() async {
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation,
        )
    }
}
