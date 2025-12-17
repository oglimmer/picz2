import Foundation
import Security

struct Credentials {
    let email: String
    let password: String
}

enum CredentialsManager {
    private static let service = "PhotoUploadCredentials"
    private static let account = "upload_credentials"

    static func save(_ creds: Credentials) -> Bool {
        let dict: [String: String] = ["email": creds.email, "password": creds.password]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(query as CFDictionary)

        var attrs = query
        attrs[kSecValueData as String] = data
        let status = SecItemAdd(attrs as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load() -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let email = obj["email"], let password = obj["password"] else { return nil }
        return Credentials(email: email, password: password)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
