import Foundation

// MARK: - App Configuration

enum AppConfiguration {
    private static let productionBaseURL = "https://picz2.oglimmer.com"

    /// Release builds always point at production — there is no flag that can get that wrong.
    ///
    /// Debug builds may override it with the `ZYNCLOUD_BASE_URL` environment variable
    /// (Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables). This replaces
    /// a hardcoded `developmentBaseURL` guarded by `isProduction = true`, which meant the dev URL
    /// was unreachable: nothing could set the flag, and editing it was a source change that could
    /// be committed by accident.
    ///
    /// Note for a plain `http://` LAN address: it also needs an ATS exception in `Info.plist`, or
    /// the request fails with a transport-security error rather than anything self-explanatory.
    /// That exception is deliberately not shipped, so an http override needs a local plist edit
    /// as well — a temporary, uncommitted one.
    static var baseURL: String {
        #if DEBUG
            let override = ProcessInfo.processInfo.environment["ZYNCLOUD_BASE_URL"]
            if let override, !override.isEmpty {
                return override
            }
        #endif
        return productionBaseURL
    }

    static var apiBaseURL: URL {
        URL(string: baseURL)!
    }

    static var tusEndpointURL: URL {
        apiBaseURL.appendingPathComponent("files/")
    }
}
