import UIKit

/// Opens the OS page where photo access for this app can be changed.
///
/// `UIApplication.openSettingsURLString` is `app-settings:`, and only iOS registers a handler for
/// it. Under Mac Catalyst nothing answers that URL, so the "Open Settings" button did nothing at
/// all — no window, no error. macOS needs the System Settings URL for the Photos privacy pane
/// instead, and Apple renamed that pane's identifier in Ventura: the modern one is tried first,
/// the pre-Ventura one is the fallback, and plain `x-apple.systempreferences:` is the last resort
/// so the button always at least opens System Settings.
///
/// `isMacCatalystApp` is false on iOS, so this is a runtime branch and not an `#if` to keep in
/// sync — same reasoning as `DeviceIdentity`.
enum PhotoAccessSettings {
    private static let macSettingsURLs = [
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Photos",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos",
        "x-apple.systempreferences:",
    ]

    static func open() {
        guard ProcessInfo.processInfo.isMacCatalystApp else {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }
        open(firstOf: macSettingsURLs.compactMap { URL(string: $0) })
    }

    /// Walks the candidate list until one URL is actually accepted. The completion handler is the
    /// only honest signal here — `canOpenURL` reports true for the whole scheme, not for a pane.
    private static func open(firstOf urls: [URL]) {
        guard let url = urls.first else { return }
        UIApplication.shared.open(url) { opened in
            if !opened { open(firstOf: Array(urls.dropFirst())) }
        }
    }
}
