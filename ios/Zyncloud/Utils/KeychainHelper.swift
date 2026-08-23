import Foundation
import Security

final class KeychainHelper {
    static let shared = KeychainHelper()

    /// Posted after the stored credentials change — a sign-in, a sign-out, or the legacy-format
    /// migration rewriting the item.
    ///
    /// Exists so callers can cache an authenticated client instead of rebuilding one from the
    /// keychain on every request (§5.10). A keychain read is a synchronous IPC to securityd; on
    /// the upload path it was happening several times per asset for a value that changes twice
    /// in a session. Cache invalidation needs a signal, and this is it.
    static let credentialsDidChange = Notification.Name("com.oglimmer.photosync.credentialsDidChange")

    static let defaultService = "com.oglimmer.photosync"

    private let service: String
    private let account = "credentials"

    private enum Field {
        static let username = "username"
        static let password = "password"
    }

    /// `service` is injectable purely so tests can operate on a scratch keychain item
    /// instead of the signed-in user's credentials. Production code uses ``shared``.
    init(service: String = KeychainHelper.defaultService) {
        self.service = service
    }

    func save(username: String, password: String) -> Bool {
        // JSON rather than "username:password": a colon is legal inside a password, and the
        // old delimiter-based format silently failed to load those credentials at all.
        guard let data = try? JSONEncoder().encode([Field.username: username, Field.password: password]) else {
            print("KeychainHelper: Failed to encode credentials")
            return false
        }

        // Delete any existing item
        delete()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        let success = status == errSecSuccess
        print("KeychainHelper: Save credentials - \(success ? "SUCCESS" : "FAILED with status \(status)")")
        if success { notifyCredentialsChanged() }
        return success
    }

    func load() -> (username: String, password: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                print("KeychainHelper: Load credentials - FAILED with status \(status)")
            }
            return nil
        }

        guard let data = result as? Data else {
            print("KeychainHelper: Load credentials - Failed to read data")
            return nil
        }

        if let fields = try? JSONDecoder().decode([String: String].self, from: data),
           let username = fields[Field.username],
           let password = fields[Field.password]
        {
            return (username: username, password: password)
        }

        if let migrated = migrateLegacyCredentials(from: data) {
            return migrated
        }

        print("KeychainHelper: Load credentials - Invalid format")
        return nil
    }

    /// Credentials written before the JSON format was introduced are stored as
    /// "username:password". Split on the FIRST colon only — the previous parser required
    /// exactly two components, so any password containing a colon was rejected outright and
    /// the user was silently signed out. Rewrite in the new format so this runs once.
    private func migrateLegacyCredentials(from data: Data) -> (username: String, password: String)? {
        guard let legacy = String(data: data, encoding: .utf8),
              let separator = legacy.firstIndex(of: ":")
        else { return nil }

        let username = String(legacy[legacy.startIndex ..< separator])
        let password = String(legacy[legacy.index(after: separator)...])
        guard !username.isEmpty, !password.isEmpty else { return nil }

        print("KeychainHelper: Migrating legacy credential format")
        _ = save(username: username, password: password)
        return (username: username, password: password)
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        notifyCredentialsChanged()
    }

    /// Posted on main so observers can touch UI state without hopping. `delete()` is also called
    /// from inside `save()`, which posts again on success — a duplicate invalidation is free,
    /// and the alternative (suppressing it) is a flag that has to stay correct forever.
    private func notifyCredentialsChanged() {
        let post = { NotificationCenter.default.post(name: KeychainHelper.credentialsDidChange, object: nil) }
        if Thread.isMainThread { post() } else { DispatchQueue.main.async(execute: post) }
    }
}
