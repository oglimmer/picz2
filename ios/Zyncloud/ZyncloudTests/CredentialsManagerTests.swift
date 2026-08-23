import Foundation
import Security
import Testing
@testable import Zyncloud

/// Covers §5.1 / §3.7 — the app and the share extension having separate credential stores, so
/// signing out of the app left the share sheet authenticated.
///
/// Every case scopes both the shared item and the legacy extension item to UUID service names
/// and restores the production seams afterwards, so the signed-in user's credentials are never
/// touched.
///
/// `.serialized` because the seams are static: Swift Testing runs cases in parallel by
/// default, and concurrent cases would otherwise overwrite each other's scratch stores.
@Suite(.serialized)
struct CredentialsManagerTests {
    private let service = "test.credentials.\(UUID().uuidString)"
    private let legacyService = "test.legacy.\(UUID().uuidString)"
    private let legacyAccount = "upload_credentials"

    /// Runs `body` with CredentialsManager pointed at scratch keychain items.
    private func withScratchStores(_ body: (KeychainHelper) throws -> Void) rethrows {
        let helper = KeychainHelper(service: service)
        let previousKeychain = CredentialsManager.keychain
        let previousLegacy = CredentialsManager.legacyService

        CredentialsManager.keychain = helper
        CredentialsManager.legacyService = legacyService

        defer {
            helper.delete()
            deleteLegacyItem()
            CredentialsManager.keychain = previousKeychain
            CredentialsManager.legacyService = previousLegacy
        }

        try body(helper)
    }

    private func writeLegacyItem(email: String, password: String) {
        let payload = ["email": email, "password": password]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: legacyAccount,
            kSecValueData as String: data,
        ]
        SecItemDelete(attrs as CFDictionary)
        #expect(SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess)
    }

    private func legacyItemExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: legacyAccount,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private func deleteLegacyItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: legacyAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - One store

    /// The core of the finding: what the extension saves, the app reads, and vice versa.
    @Test func theExtensionAndTheAppShareOneItem() {
        withScratchStores { helper in
            #expect(CredentialsManager.save(Credentials(email: "user@example.com", password: "hunter2")))

            let viaApp = helper.load()
            #expect(viaApp?.username == "user@example.com")
            #expect(viaApp?.password == "hunter2")
        }
    }

    @Test func whatTheAppSavesTheExtensionReads() {
        withScratchStores { helper in
            #expect(helper.save(username: "app@example.com", password: "from-the-app"))

            let viaExtension = CredentialsManager.load()
            #expect(viaExtension?.email == "app@example.com")
            #expect(viaExtension?.password == "from-the-app")
        }
    }

    /// The security expectation the finding was really about.
    @Test func loggingOutOfTheAppSignsTheExtensionOutToo() {
        withScratchStores { helper in
            #expect(helper.save(username: "user@example.com", password: "hunter2"))
            #expect(CredentialsManager.load() != nil)

            CredentialsManager.clear()

            #expect(CredentialsManager.load() == nil)
            #expect(helper.load() == nil)
        }
    }

    @Test func passwordsContainingAColonSurviveTheSharedStore() {
        withScratchStores { _ in
            let password = "pa:ss:word"
            #expect(CredentialsManager.save(Credentials(email: "user@example.com", password: password)))
            #expect(CredentialsManager.load()?.password == password)
        }
    }

    // MARK: - Legacy extension item

    @Test func credentialsLeftInTheOldExtensionItemAreAdopted() {
        withScratchStores { helper in
            writeLegacyItem(email: "shared@example.com", password: "sheet-only")

            let loaded = CredentialsManager.load()
            #expect(loaded?.email == "shared@example.com")
            #expect(loaded?.password == "sheet-only")

            // Adopted into the shared store...
            #expect(helper.load()?.username == "shared@example.com")
            // ...and removed, so a later logout cannot be undone by a leftover.
            #expect(!legacyItemExists())
        }
    }

    /// The regression that would reintroduce the bug: if the legacy item outlived a logout,
    /// the next share-sheet open would silently sign the user back in.
    @Test func logoutRemovesTheLegacyItemSoItCannotResurrectASession() {
        withScratchStores { _ in
            writeLegacyItem(email: "shared@example.com", password: "sheet-only")
            #expect(legacyItemExists())

            CredentialsManager.clear()

            #expect(!legacyItemExists())
            #expect(CredentialsManager.load() == nil)
        }
    }

    /// The shared store wins — adoption is a fallback, not an override.
    @Test func theSharedStoreTakesPrecedenceOverALegacyItem() {
        withScratchStores { helper in
            #expect(helper.save(username: "current@example.com", password: "current"))
            writeLegacyItem(email: "stale@example.com", password: "stale")

            #expect(CredentialsManager.load()?.email == "current@example.com")
            // Untouched, because nothing needed adopting.
            #expect(legacyItemExists())
        }
    }

    @Test func nothingStoredAnywhereLoadsAsNil() {
        withScratchStores { _ in
            #expect(CredentialsManager.load() == nil)
        }
    }

    @Test func anUnreadableLegacyItemLoadsAsNilRatherThanCrashing() {
        withScratchStores { _ in
            let attrs: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyService,
                kSecAttrAccount as String: legacyAccount,
                kSecValueData as String: Data([0xFF, 0xFE, 0x00, 0x01]),
            ]
            SecItemDelete(attrs as CFDictionary)
            #expect(SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess)

            #expect(CredentialsManager.load() == nil)
        }
    }
}
