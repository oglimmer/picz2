import OSLog

/// The app's diagnostic log.
///
/// This replaced ~120 `print()` calls. `print` writes to stdout, which on a release build
/// attached to nothing goes nowhere — so the one moment you actually want the log (a user
/// reports a stuck upload) was the one moment there wasn't one. `Logger` writes to the unified
/// log, which survives, is readable through Console.app or a sysdiagnose, carries a level, and
/// can be filtered by subsystem and category.
///
/// **Do not confuse this with ``SyncLogger``.** That one is the list of sync events the app
/// shows the *user* on the Sync tab, persisted in `UserDefaults`. This one is for whoever is
/// debugging. Several call sites write to both, deliberately.
///
/// ## Privacy
///
/// `Logger` redacts interpolated non-constant values as `<private>` unless they are marked
/// `privacy: .public`. That default is the right one here, because unlike `print` these lines
/// persist on the device: album names, file names, e-mail addresses and photo identifiers stay
/// redacted unless a call site opts them out.
///
/// Mark `.public` only what a support conversation actually needs and no person is identifiable
/// from — counts, byte sizes, HTTP status codes, state names, error descriptions. When in
/// doubt, leave it private; the line still tells you which branch ran.
enum AppLog {
    private static let subsystem = "com.oglimmer.photosync"

    /// Scanning, reconciliation, queue draining, background-task scheduling.
    static let sync = Logger(subsystem: subsystem, category: "sync")

    /// The two upload paths — multipart (``Uploader``) and TUS (``TusUploader``).
    static let upload = Logger(subsystem: subsystem, category: "upload")

    /// HTTP requests and responses in ``APIClient`` and its extensions.
    static let api = Logger(subsystem: subsystem, category: "api")

    /// App lifecycle: launch, scene phase, background tasks, push registration.
    static let app = Logger(subsystem: subsystem, category: "app")

    /// The share extension, which is a separate process and so a separate story.
    static let share = Logger(subsystem: subsystem, category: "share")

    /// On-device persistence: keychain, `UserDefaults`-backed stores, upload bookkeeping.
    static let store = Logger(subsystem: subsystem, category: "store")
}
