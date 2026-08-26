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
