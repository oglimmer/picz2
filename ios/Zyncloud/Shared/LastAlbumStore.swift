import Foundation

/// Remembers which album the share sheet last uploaded to, so the picker opens on it instead of
/// on whatever album happens to sort first.
///
/// This is the *extension's* own `UserDefaults`, not a shared one: the app and the extension have
/// no App Group between them, only the keychain access group (see ``CredentialsManager``). Adding
/// an App Group would mean a provisioning change, and the app already keeps its own destination in
/// ``Settings/albumId``. So the two remember separately, which matches how they are used —
/// the app syncs a camera roll, the share sheet files one-off items.
enum LastAlbumStore {
    /// Test seam only — production never assigns it. Same rationale as
    /// ``CredentialsManager/keychain``, including the `nonisolated(unsafe)`.
    nonisolated(unsafe) static var defaults = UserDefaults.standard

    private static let key = "shareExtension.lastSelectedAlbumId"

    /// The remembered album, or nil if nothing has been picked yet. Read through `object(forKey:)`
    /// rather than `integer(forKey:)`, which cannot tell "never chosen" from album 0.
    static var albumId: Int? {
        defaults.object(forKey: key) as? Int
    }

    static func remember(albumId: Int) {
        defaults.set(albumId, forKey: key)
    }

    /// Dropped on sign-out: album ids belong to one account, and the next person to sign in on
    /// this device must not inherit a destination they never picked.
    static func forget() {
        defaults.removeObject(forKey: key)
    }
}

/// Which album the picker opens on.
enum AlbumPreselection {
    /// The remembered album if the account still has it, otherwise the first one.
    ///
    /// The fallback is what makes a deleted album harmless: without it, remembering an album that
    /// no longer exists would leave the picker showing nothing and Upload disabled, with no hint
    /// as to why.
    static func choose(from albumIds: [Int], remembered: Int?) -> Int? {
        if let remembered, albumIds.contains(remembered) { return remembered }
        return albumIds.first
    }
}
