import Foundation

/// A user-level tag, mirroring `TagInfo` on the server.
///
/// Two names are system tags the gallery relies on, and the server puts one of them on every newly
/// uploaded asset — which one is the account's ``NewAssetTag`` setting (D68, D70). Both are shown
/// read-only in the tag manager rather than hidden: a tag that exists but cannot be renamed is
/// less confusing than one that silently is not listed.
///
/// `hidden` is derived, not assigned (D79): the server keeps it on a photo exactly while the photo
/// has no other tag, refuses to add it by hand and refuses to take a lone one off. So the pickers
/// that put tags on photos leave it out — giving a photo any tag is what publishes it, and taking
/// the last tag off hides it again. It still shows on tiles and in the tag filter, so the owner
/// can find what is waiting in the holding pen.
struct Tag: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let createdAt: String?

    /// The holding pen's name, as the server spells it.
    static let hiddenName = "hidden"

    private static let systemNames: Set<String> = ["all", hiddenName]

    var isSystem: Bool {
        Self.systemNames.contains(name)
    }

    /// The holding pen (D70). Derived by the server since D79, so no picker offers it.
    var isHidden: Bool {
        name == Self.hiddenName
    }

    /// Whether a picker may offer this tag to put on or take off photos.
    var isAssignable: Bool {
        !isHidden
    }
}

/// The tag every newly uploaded photo or video gets, an account-level setting (D70).
///
/// The raw values are the tag names themselves, because that is what the endpoint carries.
enum NewAssetTag: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The holding pen. The server keeps these assets out of every public listing, so a published
    /// album shows nothing new until the owner has reviewed it and removed the tag.
    case hidden

    /// The older behaviour: visible on the share link within seconds of the upload, no review.
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hidden: "Keep new photos hidden"
        case .all: "Publish new photos straight away"
        }
    }

    var explanation: String {
        switch self {
        case .hidden:
            "New uploads get the \"hidden\" tag. Nobody with your share link can see them. "
                + "Open the photo in your gallery, remove \"hidden\", and only then does it go public."
        case .all:
            "New uploads get the \"all\" tag. In a published album they appear on the share link "
                + "within seconds of the upload, with no review. Photos your phone uploads "
                + "automatically are included."
        }
    }
}

/// Answer to `GET`/`PUT /api/settings/new-asset-tag`.
struct NewAssetTagResponse: Codable {
    let success: Bool
    let tagName: String?
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
