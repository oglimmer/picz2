import Foundation

/// Narration languages and tags — the two user-level settings the web app exposes from its
/// account menu. Kept in their own file so `APIClientExtensions.swift` stops growing.
extension APIClient {
    // MARK: - Narration Languages

    func fetchLanguageSettings(completion: @escaping @Sendable (Result<LanguageSettingsResponse, Error>) -> Void) {
        send(.get, "api/settings/languages", expecting: LanguageSettingsResponse.self, completion: completion)
    }

    /// `slot` is 1 or 2 — the server exposes one endpoint per language rather than a single
    /// payload with both, so the slot is part of the path.
    func setLanguageName(slot: Int, name: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(.put, "api/settings/languages/\(slot)",
             body: SettingValueBody(value: name), completion: completion)
    }

    // MARK: - New Photo Visibility

    /// Which tag new uploads get for this account — `hidden` or `all` (D70).
    func fetchNewAssetTag(completion: @escaping @Sendable (Result<NewAssetTag, Error>) -> Void) {
        send(.get, "api/settings/new-asset-tag", expecting: NewAssetTagResponse.self) { result in
            completion(result.map { NewAssetTag(rawValue: $0.tagName ?? "") ?? .hidden })
        }
    }

    /// Change it.
    ///
    /// `confirmed` is always sent as true: the server refuses an unconfirmed switch to `all`, and
    /// the only caller runs its own confirmation dialog first. It is a handshake with the server,
    /// not a second piece of UI state.
    func setNewAssetTag(_ tag: NewAssetTag, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(.put, "api/settings/new-asset-tag",
             body: NewAssetTagBody(tagName: tag.rawValue, confirmed: true), completion: completion)
    }

    // MARK: - Tags

    func fetchTags(completion: @escaping @Sendable (Result<[Tag], Error>) -> Void) {
        send(.get, "api/tags", expecting: TagsListResponse.self) { result in
            completion(result.map(\.tags))
        }
    }

    func createTag(name: String, completion: @escaping @Sendable (Result<Tag?, Error>) -> Void) {
        send(.post, "api/tags", body: TagNameBody(tagName: name), expecting: TagResponse.self) { result in
            completion(result.map(\.tag))
        }
    }

    func updateTag(id: Int, name: String, completion: @escaping @Sendable (Result<Tag?, Error>) -> Void) {
        send(.put, "api/tags/\(id)", body: TagNameBody(tagName: name), expecting: TagResponse.self) { result in
            completion(result.map(\.tag))
        }
    }

    func deleteTag(id: Int, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(.delete, "api/tags/\(id)", completion: completion)
    }
}

/// The body of the settings endpoints that take a single value, such as a language name.
struct SettingValueBody: Encodable {
    let value: String
}

/// The body of every endpoint that names a tag: create, rename, and put-on-file.
struct TagNameBody: Encodable {
    let tagName: String
}

/// The body of `PUT /api/settings/new-asset-tag`.
struct NewAssetTagBody: Encodable {
    let tagName: String
    let confirmed: Bool
}
