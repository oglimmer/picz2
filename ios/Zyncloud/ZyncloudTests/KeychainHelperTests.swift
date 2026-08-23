import Foundation
import Security
import Testing

@testable import Zyncloud

/// Regression coverage for the credential store.
///
/// The bug these exist for: credentials used to be stored as `"username:password"` and read
/// back with `components(separatedBy: ":")` plus `guard parts.count == 2`. Any password
/// containing a colon saved fine and then failed to load, which the app surfaced as a silent
/// sign-out. The current format is JSON, with a one-shot migration for existing items.
struct KeychainHelperTests {
    /// Every test gets its own service name so it never touches the signed-in user's item,
    /// and cleans up after itself.
    private func withKeychain(_ body: (KeychainHelper, String) throws -> Void) rethrows {
        let service = "com.oglimmer.photosync.tests.\(UUID().uuidString)"
        let helper = KeychainHelper(service: service)
        defer { helper.delete() }
        try body(helper, service)
    }

    // MARK: - Round trip

    @Test func savesAndLoadsCredentials() {
        withKeychain { helper, _ in
            #expect(helper.save(username: "user@example.com", password: "hunter2"))

            let loaded = helper.load()
            #expect(loaded?.username == "user@example.com")
            #expect(loaded?.password == "hunter2")
        }
    }

    @Test func loadReturnsNilWhenNothingStored() {
        withKeychain { helper, _ in
            #expect(helper.load() == nil)
        }
    }

    @Test func saveReplacesAnExistingItem() {
        withKeychain { helper, _ in
            #expect(helper.save(username: "first@example.com", password: "one"))
            #expect(helper.save(username: "second@example.com", password: "two"))

            let loaded = helper.load()
            #expect(loaded?.username == "second@example.com")
            #expect(loaded?.password == "two")
        }
    }

    @Test func deleteRemovesTheItem() {
        withKeychain { helper, _ in
            #expect(helper.save(username: "user@example.com", password: "hunter2"))
            helper.delete()
            #expect(helper.load() == nil)
        }
    }

    // MARK: - The regression

    @Test func passwordContainingAColonSurvivesARoundTrip() {
        withKeychain { helper, _ in
            #expect(helper.save(username: "user@example.com", password: "pass:word"))

            let loaded = helper.load()
            #expect(loaded?.username == "user@example.com")
            #expect(loaded?.password == "pass:word")
        }
    }

    @Test(arguments: [
        "a:b:c",
        ":leading",
        "trailing:",
        "::",
        "http://example.com/reset?token=abc",
    ])
    func passwordsFullOfColonsSurviveARoundTrip(password: String) {
        withKeychain { helper, _ in
            #expect(helper.save(username: "user@example.com", password: password))
            #expect(helper.load()?.password == password)
        }
    }

    @Test(arguments: [
        "pässwörd",
        "🔐🔐🔐",
        "  leading and trailing  ",
        "line\nbreak",
        "quote\"and\\backslash",
    ])
    func awkwardPasswordsSurviveARoundTrip(password: String) {
        withKeychain { helper, _ in
            #expect(helper.save(username: "user@example.com", password: password))
            #expect(helper.load()?.password == password)
        }
    }

    // MARK: - Migration from the legacy "username:password" format

    /// Writes a raw item in the pre-JSON format, the way a build before the fix would have.
    /// `account` mirrors the private constant in KeychainHelper.
    private func writeLegacyItem(_ raw: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "credentials",
        ]
        SecItemDelete(query as CFDictionary)

        var attrs = query
        attrs[kSecValueData as String] = Data(raw.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        #expect(SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess)
    }

    /// Reads the stored bytes directly, bypassing KeychainHelper's parsing.
    private func rawStoredData(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @Test func readsCredentialsWrittenInTheLegacyFormat() {
        withKeychain { helper, service in
            writeLegacyItem("user@example.com:hunter2", service: service)

            let loaded = helper.load()
            #expect(loaded?.username == "user@example.com")
            #expect(loaded?.password == "hunter2")
        }
    }

    /// The whole point of the fix: a legacy item whose password contains a colon was
    /// previously unreadable. It must now split on the FIRST colon only.
    @Test func legacyCredentialsWithAColonInThePasswordSplitOnTheFirstColon() {
        withKeychain { helper, service in
            writeLegacyItem("user@example.com:pass:word:!", service: service)

            let loaded = helper.load()
            #expect(loaded?.username == "user@example.com")
            #expect(loaded?.password == "pass:word:!")
        }
    }

    @Test func legacyCredentialsAreRewrittenInTheNewFormat() throws {
        try withKeychain { helper, service in
            writeLegacyItem("user@example.com:hunter2", service: service)
            _ = helper.load()

            let stored = try #require(rawStoredData(service: service))
            let decoded = try? JSONDecoder().decode([String: String].self, from: stored)
            #expect(decoded?["username"] == "user@example.com")
            #expect(decoded?["password"] == "hunter2")

            // And the migrated item still reads back correctly.
            #expect(helper.load()?.password == "hunter2")
        }
    }

    @Test(arguments: [
        "no-colon-at-all",
        ":password-with-no-username",
        "username-with-no-password:",
    ])
    func unparseableLegacyDataLoadsAsNil(raw: String) {
        withKeychain { helper, service in
            writeLegacyItem(raw, service: service)
            #expect(helper.load() == nil)
        }
    }
}
