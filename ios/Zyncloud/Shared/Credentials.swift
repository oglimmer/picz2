import Foundation
import Security

struct Credentials {
    let email: String
    let password: String
}

/// The share extension's view of the *same* credential item the app uses.
///
/// These used to be two unrelated keychain items — the app under
/// `com.oglimmer.photosync`, the extension under `PhotoUploadCredentials` — so signing
/// into one did not sign into the other, and signing out of the app left the share sheet
/// fully authenticated. This now delegates to ``KeychainHelper``, which both targets
/// compile.
///
/// No `kSecAttrAccessGroup` is passed anywhere. Both targets declare exactly one
/// `keychain-access-groups` entry (`$(AppIdentifierPrefix)com.oglimmer.PhotoCloudSync`),
/// and the system uses the first entry as the default access group — so items already
/// land in the shared group. Naming it explicitly would mean hardcoding the team prefix
/// and would risk stranding every existing user's item in a group we stopped querying.
enum CredentialsManager {
    /// Both seams exist purely so tests can operate on a scratch keychain item instead of
    /// the signed-in user's credentials — the same rationale as ``KeychainHelper/init(service:)``.
    /// Production never assigns them.
    static var keychain = KeychainHelper.shared
    static var legacyService = "PhotoUploadCredentials"

    // Where the extension kept its own separate item before the collapse.
    private static let legacyAccount = "upload_credentials"

    static func save(_ creds: Credentials) -> Bool {
        keychain.save(username: creds.email, password: creds.password)
    }

    static func load() -> Credentials? {
        if let stored = keychain.load() {
            return Credentials(email: stored.username, password: stored.password)
        }
        return adoptLegacyExtensionCredentials()
    }

    static func clear() {
        keychain.delete()
        // Also purge the pre-collapse item, or a logout could be undone the next time the
        // share sheet opened and adopted it.
        deleteLegacyItem()
    }

    /// Someone who signed in through the share sheet but never through the app has their
    /// credentials only in the old extension-private item. Move it across once, then delete
    /// it so it can't outlive a later logout.
    private static func adoptLegacyExtensionCredentials() -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: legacyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let email = obj["email"],
              let password = obj["password"]
        else { return nil }

        _ = keychain.save(username: email, password: password)
        deleteLegacyItem()
        return Credentials(email: email, password: password)
    }

    private static func deleteLegacyItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: legacyAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
