import Foundation

/// Presentation image groups — the labelled sections an album is read in.
///
/// A group is an anchor on one photo, scoped to one `(album, tag)` pair, so creating one takes the
/// tag and the photo it starts at. Neither can be changed afterwards — the server ignores both on
/// update, and moving a chapter is delete plus create. Where the chapter *stops* is movable, and
/// has ``setPresentationGroupEnd(id:endFileId:completion:)`` to itself.
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

    /// - Parameter endFileId: last photo of the chapter, or nil to let it run on until the next
    ///   chapter starts.
    func createPresentationGroup(
        albumId: Int,
        tag: String,
        startFileId: Int,
        endFileId: Int? = nil,
        draft: PresentationGroupDraft,
        completion: @escaping @Sendable (Result<PresentationGroup, Error>) -> Void,
    ) {
        send(
            .post,
            "api/albums/\(albumId)/presentation-groups",
            body: PresentationGroupBody(
                tag: tag,
                startFileId: startFileId,
                endFileId: endFileId,
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
                endFileId: nil,
                label: draft.label,
                text: draft.text,
            ),
            expecting: PresentationGroupResponse.self,
        ) { result in
            completion(result.map(\.group))
        }
    }

    /// Moves or clears the photo a chapter stops at. Passing nil reopens the chapter, so it runs
    /// on until the next one starts again.
    ///
    /// Its own endpoint, not a field on update: the update body above deliberately leaves the end
    /// out, and folding the two together would mean every plain edit wiped the end marker.
    func setPresentationGroupEnd(
        id: Int,
        endFileId: Int?,
        completion: @escaping @Sendable (Result<PresentationGroup, Error>) -> Void,
    ) {
        send(
            .put,
            "api/presentation-groups/\(id)/end",
            body: PresentationGroupEndBody(endFileId: endFileId),
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

    /// Only read on create — the server ignores it on update, where the end has its own endpoint.
    let endFileId: Int?

    let label: String
    let text: String?
}

/// Matches `PresentationGroupEndRequest` on the server. A null `endFileId` clears the end.
private struct PresentationGroupEndBody: Encodable {
    let endFileId: Int?
}
