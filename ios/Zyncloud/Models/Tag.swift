import Foundation

/// A user-level tag, mirroring `TagInfo` on the server.
///
/// `all` is a system tag the gallery relies on: the server puts it on every newly uploaded asset
/// (D68). It is shown read-only rather than hidden — a tag that exists but cannot be renamed is
/// less confusing than one that silently is not listed.
struct Tag: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let createdAt: String?

    private static let systemNames: Set<String> = ["all"]

    var isSystem: Bool {
        Self.systemNames.contains(name)
    }
}

struct TagsListResponse: Codable {
    let success: Bool
    let tags: [Tag]
}

struct TagResponse: Codable {
    let success: Bool
    let message: String?
    let tag: Tag?
}

/// Answer to `GET /api/settings/languages`. The two narration languages are free-text names
/// (e.g. "German", "English"), not locale codes — the server stores whatever the user typed.
struct LanguageSettingsResponse: Codable {
    let success: Bool
    let language1: String?
    let language2: String?
}

/// Answer to the per-file tag endpoints (`POST`/`DELETE /api/files/{id}/tags`).
///
/// `tags` is the file's whole tag list after the change, so it replaces the local list rather
/// than being merged into it.
struct FileTagsResponse: Codable {
    let success: Bool
    let message: String?
    let tags: [String]
}

/// Answer to the album-wide tag endpoints (`POST`/`DELETE /api/albums/{id}/files/tags/{name}`).
///
/// `updatedCount` counts only the files that actually changed; files already in the wanted
/// state are skipped server-side.
struct BulkTagResponse: Codable {
    let success: Bool
    let message: String?
    let tagName: String?
    let updatedCount: Int
}
