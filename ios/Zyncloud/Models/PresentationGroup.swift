import Foundation

/// A labelled section marker inside one album's presentation of one tag.
///
/// A group is an **anchor**, not a membership list: it names the photo it starts at
/// (``startFileId``) and owns that photo plus every following one until the next anchor. Sections
/// are therefore derived by walking the tag-filtered list in its display order — which is why
/// reordering an album reshuffles its sections for free, and why a group whose anchor is not in
/// the current list (deleted, untagged, filtered out) simply stops rendering.
///
/// Mirrors `PresentationGroupInfo` on the server and `PresentationGroup` in the web app. The tag
/// and the anchor are fixed once created — the server ignores both on update, so moving a chapter
/// is delete plus create.
struct PresentationGroup: Codable, Identifiable, Hashable {
    let id: Int
    let albumId: Int

    /// Tag **name**, the same value the presentation filter holds — not the tag's id.
    let tag: String

    let startFileId: Int

    /// The heading. Required by the server, so it is not optional here.
    let label: String

    /// The optional paragraph under the heading. `body_text` in the database, `text` on the wire.
    let text: String?
}

struct PresentationGroupsListResponse: Codable {
    let success: Bool
    let count: Int?
    let groups: [PresentationGroup]
}

/// The answer to a create or an update: the group as it was actually stored, which is what the
/// caller keeps. The server trims the label and collapses a blank body to null, so echoing back
/// what was sent would leave the screen showing something slightly different from the truth.
struct PresentationGroupResponse: Codable {
    let success: Bool
    let message: String?
    let group: PresentationGroup
}
