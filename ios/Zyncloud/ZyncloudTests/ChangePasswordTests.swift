import Foundation
import Testing
@testable import Zyncloud

/// The form rules of the Change Password screen, and the client behaviour that makes a changed
/// password reach every screen without a restart.
@MainActor
struct ChangePasswordTests {
    private func form(current: String = "", new: String = "", confirm: String = "") -> ChangePasswordViewModel {
        let model = ChangePasswordViewModel(apiClient: nil, storeCredentials: { _ in true })
        model.currentPassword = current
        model.newPassword = new
        model.confirmPassword = confirm
        return model
    }

    @Test func aCompleteMatchingFormCanBeSent() {
        #expect(form(current: "old-secret", new: "new-secret", confirm: "new-secret").isFormValid)
    }

    @Test func theCurrentPasswordIsRequired() {
        #expect(!form(new: "new-secret", confirm: "new-secret").isFormValid)
    }

    @Test func aShortNewPasswordIsRefusedWithAReason() {
        let model = form(current: "old-secret", new: "short", confirm: "short")
        #expect(!model.isFormValid)
        #expect(model.validationHint?.contains("8 characters") == true)
    }

    @Test func mismatchedNewPasswordsAreRefusedWithAReason() {
        let model = form(current: "old-secret", new: "new-secret", confirm: "new-secreT")
        #expect(!model.isFormValid)
        #expect(model.validationHint == "The new passwords do not match.")
    }

    /// The screen opens empty and must not open with a complaint.
    @Test func anEmptyFormSaysNothingIsWrong() {
        #expect(form().validationHint == nil)
    }
}

/// A client from ``APIClientProvider`` is held by a view model for the whole session. It has to
/// send the password the keychain holds now, not the one it was built with — otherwise every
/// screen fails with 401 after a password change until the app is restarted.
struct SignedInClientTests {
    /// Stands in for the keychain.
    private final class Account: @unchecked Sendable {
        private let lock = NSLock()
        private var value: (username: String, password: String)?

        init(_ value: (username: String, password: String)?) {
            self.value = value
        }

        func set(_ newValue: (username: String, password: String)?) {
            lock.lock()
            value = newValue
            lock.unlock()
        }

        func get() -> (username: String, password: String)? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private func authorization(_ client: APIClient) throws -> String? {
        try client.makeRequest(.get, "api/auth/check").value(forHTTPHeaderField: "Authorization")
    }

    private func basic(_ user: String, _ password: String) -> String {
        "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }

    @Test func aHeldClientSendsTheNewPasswordAfterAChange() throws {
        let account = Account((username: "a@example.test", password: "old-secret"))
        let client = APIClient { account.get() }

        #expect(try authorization(client) == basic("a@example.test", "old-secret"))
        account.set((username: "a@example.test", password: "new-secret"))
        #expect(try authorization(client) == basic("a@example.test", "new-secret"))
    }

    /// Signed out: no header at all, rather than the credentials of the session that ended.
    @Test func aHeldClientSendsNoCredentialsAfterSignOut() throws {
        let account = Account((username: "a@example.test", password: "old-secret"))
        let client = APIClient { account.get() }

        account.set(nil)
        #expect(try authorization(client) == nil)
    }

    /// A client built with fixed credentials keeps them — the sign-in check relies on that.
    @Test func aClientWithFixedCredentialsKeepsThem() throws {
        let client = APIClient(username: "a@example.test", password: "typed-in")
        #expect(try authorization(client) == basic("a@example.test", "typed-in"))
    }
}
