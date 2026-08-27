import Foundation

/// Presentation image groups — the labelled sections an album is read in.
///
/// A group is an anchor on one photo, scoped to one `(album, tag)` pair, so creating one takes the
/// tag and the photo it starts at. Neither can be changed afterwards — the server ignores both on
/// update, and moving a chapter is delete plus create.
extension APIClient {
    func fetchPresentationGroups(
        albumId: Int,
        completion: @escaping @Sendable (Result<[PresentationGroup], Error>) -> Void,
    ) {
        send(
            .get,
            "api/albums/\(albumId)/presentation-groups",
            expecting: PresentationGroupsListResponse.self,
        ) { result in
            completion(result.map(\.groups))
        }
    }

    func createPresentationGroup(
        albumId: Int,
        tag: String,
        startFileId: Int,
        draft: PresentationGroupDraft,
        completion: @escaping @Sendable (Result<PresentationGroup, Error>) -> Void,
    ) {
        send(
            .post,
            "api/albums/\(albumId)/presentation-groups",
            body: PresentationGroupBody(
                tag: tag,
                startFileId: startFileId,
                label: draft.label,
                text: draft.text,
            ),
            expecting: PresentationGroupResponse.self,
        ) { result in
            completion(result.map(\.group))
        }
    }

    /// Changes a group's words. The tag and the anchor are deliberately not sent: the server
    /// ignores them on update, and sending them would suggest otherwise.
    func updatePresentationGroup(
        id: Int,
        draft: PresentationGroupDraft,
        completion: @escaping @Sendable (Result<PresentationGroup, Error>) -> Void,
    ) {
        send(
            .put,
            "api/presentation-groups/\(id)",
            body: PresentationGroupBody(
                tag: nil,
                startFileId: nil,
                label: draft.label,
                text: draft.text,
            ),
            expecting: PresentationGroupResponse.self,
        ) { result in
            completion(result.map(\.group))
        }
    }

    /// Removes the section marker. The photos stay exactly where they are — a group is an anchor,
    /// not a container.
    func deletePresentationGroup(id: Int, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(.delete, "api/presentation-groups/\(id)", completion: completion)
    }
}

/// Matches `PresentationGroupRequest` on the server. `tag` and `startFileId` are optional here
/// only because update leaves them out; create always sends both.
private struct PresentationGroupBody: Encodable {
    let tag: String?
    let startFileId: Int?
    let label: String
    let text: String?
}
