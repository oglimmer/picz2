import Foundation

/// Which upload implementation a batch goes through.
enum UploadPath: Equatable {
    case tus
    case multipart
}

/// Which uploader owns a given background `URLSession` identifier.
enum BackgroundSessionRoute: Equatable {
    case tus
    case multipart
}

/// The two routing decisions that were previously inline and untestable.
///
/// Both were the site of real bugs: §3.1 handed TUS background sessions to `Uploader`, and the
/// path selection has a third state ("capabilities not fetched yet") that is easy to collapse
/// into the boolean by accident.
enum UploadRouting {
    /// TUS requires **both** the local opt-in and the server advertising it.
    ///
    /// The third state matters: on the first `drainQueue` after a cold launch the capabilities
    /// cache is still empty, and that is deliberately *not* treated as "server said no". It
    /// means "we have not asked yet", and the batch goes multipart rather than being held back.
    /// Once `ensureCapabilitiesLoaded` completes, later batches switch over.
    static func selectPath(userOptedIn: Bool, capabilities: Capabilities?) -> UploadPath {
        guard userOptedIn else { return .multipart }
        guard let capabilities else { return .multipart }
        return capabilities.tus.enabled ? .tus : .multipart
    }

    /// Routes a background session identifier handed back by the system on relaunch.
    ///
    /// An identifier we do not recognise — a session created by an older build, say — routes to
    /// multipart on purpose rather than being dropped. iOS requires the completion handler for
    /// *every* identifier it gives us to be invoked; ignoring an unknown one is the exact
    /// "reduced background time" penalty §3.1 was about.
    static func route(
        forSessionIdentifier identifier: String,
        tusSessionId: String,
        multipartSessionId: String
    ) -> BackgroundSessionRoute {
        if identifier == tusSessionId { return .tus }
        if identifier == multipartSessionId { return .multipart }
        return .multipart
    }
}
