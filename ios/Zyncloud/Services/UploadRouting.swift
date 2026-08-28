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
    /// TUS is used whenever the server advertises it. There is no client-side opt-out.
    ///
    /// The third state matters: on the first `drainQueue` after a cold launch the capabilities
    /// cache is still empty, and that is deliberately *not* treated as "server said no". It
    /// means "we have not asked yet", and the batch goes multipart rather than being held back.
    /// Once `ensureCapabilitiesLoaded` completes, later batches switch over.
    static func selectPath(capabilities: Capabilities?) -> UploadPath {
        guard let capabilities else { return .multipart }
        return capabilities.tus.enabled ? .tus : .multipart
    }

    /// Album-screen uploads store the destination in `albumOverrides`; background sync does
    /// not. The by-content lookup is scoped to `(albumId, contentId)`, so using the sync
    /// target for a hand-picked upload 404s and status polling never starts.
    static func lookupAlbumId(override: Int?, fallback: Int) -> Int {
        override ?? fallback
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
