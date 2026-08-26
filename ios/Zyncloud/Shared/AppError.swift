import Foundation

/// Every error this app raises itself.
///
/// Lives in `Shared/` rather than next to ``AlertState`` in `Utils/ErrorHandler.swift` so the
/// share extension — a separate target that cannot see `Utils/` — reports failures as the same
/// type the app does. Before that split, the extension and the upload paths each minted ad-hoc
/// `NSError`s with a made-up domain string, so "what went wrong" was a `userInfo` dictionary
/// that no caller could switch on.
///
/// `LocalizedError` is what makes `error.localizedDescription` say something a person can read;
/// without it `NSError`'s default description is the domain and the code.
enum AppError: LocalizedError {
    /// The request never reached the server, or the reply never came back.
    case network(Error)

    /// The server answered, and the answer was a refusal. `statusCode` is nil when the failure
    /// happened before a status existed — a URL that would not build, a reply that was not HTTP.
    case api(message: String, statusCode: Int?)

    /// The server answered, and the answer was accepted, but the body was not the shape this
    /// client expects. Its own case rather than an ``api`` with the status on it, because the
    /// two want opposite handling: a refusal on `/api/auth/check` means "wrong password", while
    /// a body this client cannot read means the server changed and the password is fine.
    case decoding(String)

    /// Credentials are missing, wrong, or no longer accepted.
    case authentication(String)

    /// The photo library refused, or could not produce the asset.
    case photoLibrary(String)

    /// On-device storage: the keychain, the file system, an export that could not be written.
    case storage(String)

    /// The work was called off before it finished — the share sheet closed under it, the screen
    /// went away. Reported rather than dropped: a completion that never fires leaves a spinner
    /// turning forever with nothing to explain it.
    case cancelled(String)

    /// Something threw that is none of the above.
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case let .network(error):
            "Network error: \(error.localizedDescription)"
        case let .api(message, statusCode):
            if let statusCode {
                "API error (\(statusCode)): \(message)"
            } else {
                "API error: \(message)"
            }
        case let .decoding(message):
            "Could not read the server's answer: \(message)"
        case let .authentication(message):
            "Authentication error: \(message)"
        case let .photoLibrary(message):
            "Photo library error: \(message)"
        case let .storage(message):
            "Storage error: \(message)"
        case let .cancelled(message):
            message
        case let .unknown(error):
            "Unexpected error: \(error.localizedDescription)"
        }
    }

    /// The HTTP status this error carries, if it came from one.
    ///
    /// Callers that retry — the TUS resume path, the post-finish asset lookup — need to tell a
    /// 404 that will fix itself from a 401 that never will. Reading the code off the enum keeps
    /// them from string-matching the message.
    var statusCode: Int? {
        if case let .api(_, statusCode) = self { return statusCode }
        return nil
    }
}
