import Foundation
import Security

final class KeychainHelper {
    static let shared = KeychainHelper()

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
    }
}
