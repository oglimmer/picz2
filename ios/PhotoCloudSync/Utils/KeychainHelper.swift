import Foundation
import Security

final class KeychainHelper {
    static let shared = KeychainHelper()

    private let service = "com.oglimmer.photosync"

    private init() {}

    func save(username: String, password: String) -> Bool {
        let credentials = "\(username):\(password)"
        guard let data = credentials.data(using: .utf8) else {
            print("KeychainHelper: Failed to encode credentials")
            return false
        }

        // Delete any existing item
        delete()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "credentials",
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
            kSecAttrAccount as String: "credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            print("KeychainHelper: Load credentials - FAILED with status \(status)")
            return nil
        }

        guard let data = result as? Data,
              let credentials = String(data: data, encoding: .utf8)
        else {
            print("KeychainHelper: Load credentials - Failed to decode data")
            return nil
        }

        let parts = credentials.components(separatedBy: ":")
        guard parts.count == 2 else {
            print("KeychainHelper: Load credentials - Invalid format")
            return nil
        }

        print("KeychainHelper: Load credentials - SUCCESS (username: \(parts[0]))")
        return (username: parts[0], password: parts[1])
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "credentials",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
