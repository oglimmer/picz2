import Foundation

/// Where one tag stands across a set of photos.
enum TagSelectionState {
    /// Every picked photo carries it.
    case all
    /// Some do, some do not.
    case some
    /// None do.
    case none
}

/// Tagging, for one photo and for many.
///
/// Split off the main view model file because it is a self-contained job: which tags this album
/// accepts, what is on each photo, and the two ways of changing that.
@MainActor
extension AlbumDetailViewModel {
    // MARK: - Loading the tag lists

    /// Called when a tag screen opens. Does nothing if the lists are already here — an album
    /// that is only looked at never fetches them.
    func loadTagsIfNeeded() {
        guard albumTags.isEmpty, !isLoadingTags else { return }
        Task { await reloadTags() }
    }

    func reloadTags() async {
        guard let apiClient else { return }

        isLoadingTags = true

        let albumResult: Result<[Tag], Error> = await withCheckedContinuation { continuation in
            apiClient.fetchEnabledTags(albumId: album.id) { continuation.resume(returning: $0) }
        }
        let accountResult: Result<[Tag], Error> = await withCheckedContinuation { continuation in
            apiClient.fetchTags { continuation.resume(returning: $0) }
        }

        isLoadingTags = false

        switch albumResult {
        case let .success(tags):
            albumTags = tags
        case let .failure(error):
            handleError(error)
            return
        }

        switch accountResult {
        case let .success(tags):
            accountTags = tags
        case let .failure(error):
            handleError(error)
        }
    }

    // MARK: - Which tags this album accepts

    /// Ids of the album's own tags. The system ones are left out: the server always treats them
    /// as on and drops their ids from a write, so sending them back would be noise.
    var enabledTagIds: [Int] {
        albumTags.filter { !$0.isSystem }.map(\.id)
    }

    /// Replaces the album's accepted tags with exactly `tagIds`.
    ///
    /// Switching a tag off here does **not** strip it from photos that already carry it — the
    /// server keeps those rows. It only stops the tag being offered.
    func setAlbumTags(_ tagIds: [Int]) {
        guard let apiClient else {
            reportNotAuthenticated()
            return
        }
        guard !isApplyingTags else { return }

        isApplyingTags = true

        Task {
            let result: Result<[Tag], Error> = await withCheckedContinuation { continuation in
                apiClient.setEnabledTags(albumId: album.id, tagIds: tagIds) { continuation.resume(returning: $0) }
            }

            isApplyingTags = false

            switch result {
            case let .success(tags):
                albumTags = tags
            case let .failure(error):
                handleError(error)
            }
        }
    }

    /// Makes a new tag on the account and switches it on for this album in one go.
    ///
    /// Both halves are needed: a tag the album does not accept cannot be put on any photo in it,
    /// so creating one without enabling it would look like the app quietly ignoring the name.
    func createTag(named name: String) {
        guard let apiClient else {
            reportNotAuthenticated()
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isApplyingTags else { return }

        isApplyingTags = true

        Task {
            let created: Result<Tag?, Error> = await withCheckedContinuation { continuation in
                apiClient.createTag(name: trimmed) { continuation.resume(returning: $0) }
            }

            switch created {
            case let .success(tag):
                if let tag {
                    let result: Result<[Tag], Error> = await withCheckedContinuation { continuation in
                        apiClient.setEnabledTags(
                            albumId: album.id,
                            tagIds: enabledTagIds + [tag.id],
                        ) { continuation.resume(returning: $0) }
                    }
                    switch result {
                    case let .success(tags):
                        albumTags = tags
                        accountTags.append(tag)
                    case let .failure(error):
                        handleError(error)
                    }
                } else {
                    // Made, but the server did not echo the row back — refetch rather than
                    // guess at an id we would then have to send back to it.
                    await reloadTags()
                }
            case let .failure(error):
                handleError(error)
            }

            isApplyingTags = false
        }
    }

    // MARK: - Tagging photos

    /// Puts `tagName` on the photo, or takes it off if it is already there.
    func toggleTag(_ tagName: String, on photo: Photo) {
        applyTag(tagName, add: !photo.tags.contains(tagName), to: [photo.id])
    }

    /// Same for every picked photo. `add` is decided by the caller, not per photo, so that one
    /// tap means one thing across the whole selection.
    func applyTagToSelection(_ tagName: String, add: Bool) {
        applyTag(tagName, add: add, to: selectedPhotoIds)
    }

    /// The one path both of the above take.
    ///
    /// Photos already in the wanted state are skipped rather than sent: the server answers a
    /// duplicate add — and a remove of a tag that is not there — with an error, so asking would
    /// turn "nothing to do" into a failure report.
    private func applyTag(_ tagName: String, add: Bool, to photoIds: Set<Int>) {
        guard let apiClient else {
            reportNotAuthenticated()
            return
        }
        guard !photoIds.isEmpty, !isApplyingTags else { return }

        isApplyingTags = true

        Task {
            // Every photo in the album: one request instead of one per photo. Only worth the
            // different code path for a real selection — a single photo goes the plain way,
            // which answers with that photo's new tag list and so needs no reload.
            if photoIds.count > 1, photoIds.count == photos.count {
                await applyTagToWholeAlbum(tagName, add: add, using: apiClient)
            } else {
                await applyTagPhotoByPhoto(tagName, add: add, to: photoIds, using: apiClient)
            }

            isApplyingTags = false
        }
    }

    private func applyTagToWholeAlbum(_ tagName: String, add: Bool, using apiClient: APIClient) async {
        let result: Result<Int, Error> = await withCheckedContinuation { continuation in
            if add {
                apiClient.addTagToAllFiles(albumId: album.id, tagName: tagName) { continuation.resume(returning: $0) }
            } else {
                apiClient.removeTagFromAllFiles(albumId: album.id, tagName: tagName) { continuation.resume(returning: $0) }
            }
        }

        switch result {
        case let .success(changed):
            // The whole-album endpoints answer with a count, not with the new tag lists, so
            // the grid has to be re-read to know what each photo now carries.
            await refreshPhotos()
            reportTagOutcome(tagName, add: add, changed: changed, failed: 0, total: photos.count)
        case let .failure(error):
            handleError(error)
        }
    }

    private func applyTagPhotoByPhoto(
        _ tagName: String,
        add: Bool,
        to photoIds: Set<Int>,
        using apiClient: APIClient,
    ) async {
        var changed = 0
        var failed = 0
        var firstError: Error?

        for id in photoIds {
            guard let photo = photos.first(where: { $0.id == id }) else { continue }
            guard photo.tags.contains(tagName) != add else { continue }

            let result: Result<[String], Error> = await withCheckedContinuation { continuation in
                if add {
                    apiClient.addTag(fileId: id, tagName: tagName) { continuation.resume(returning: $0) }
                } else {
                    apiClient.removeTag(fileId: id, tagName: tagName) { continuation.resume(returning: $0) }
                }
            }

            switch result {
            case let .success(tags):
                changed += 1
                if let index = photos.firstIndex(where: { $0.id == id }) {
                    photos[index].tags = tags
                }
            case let .failure(error):
                failed += 1
                if firstError == nil {
                    firstError = error
                }
            }
        }

        // One photo is a tap on a menu item — it either worked, and the tick moves, or it did
        // not, and the error is worth a word. Nothing to announce in between.
        if photoIds.count == 1 {
            if let firstError {
                handleError(firstError)
            }
            return
        }

        if failed > 0, changed == 0, let firstError {
            handleError(firstError)
            return
        }

        reportTagOutcome(tagName, add: add, changed: changed, failed: failed, total: photoIds.count)
    }

    private func reportTagOutcome(_ tagName: String, add: Bool, changed: Int, failed: Int, total: Int) {
        if failed > 0 {
            alertState = AlertState(
                title: add ? "Some Photos Not Tagged" : "Some Tags Not Removed",
                message: "\(changed) of \(total) photos changed. \(failed) failed — pull down to refresh and try those again.",
            )
            return
        }

        guard changed > 0 else {
            alertState = AlertState(
                title: "Nothing to Change",
                message: add
                    ? "Every one of those photos already has \"\(tagName)\"."
                    : "None of those photos had \"\(tagName)\".",
            )
            return
        }

        let photoWord = changed == 1 ? "photo" : "photos"
        alertState = AlertState(
            title: add ? "Tagged" : "Tag Removed",
            message: add
                ? "Added \"\(tagName)\" to \(changed) \(photoWord)."
                : "Removed \"\(tagName)\" from \(changed) \(photoWord).",
        )
    }

    // MARK: - Picking photos

    var selectedPhotos: [Photo] {
        photos.filter { selectedPhotoIds.contains($0.id) }
    }

    /// How `tagName` sits across the picked photos, which is what tells the bulk sheet whether
    /// a tap should add or remove.
    func selectionState(of tagName: String) -> TagSelectionState {
        let picked = selectedPhotos
        guard !picked.isEmpty else { return .none }

        let carrying = picked.filter { $0.tags.contains(tagName) }.count
        if carrying == 0 { return .none }
        return carrying == picked.count ? .all : .some
    }

    func beginSelecting() {
        selectedPhotoIds = []
        isSelecting = true
    }

    func endSelecting() {
        isSelecting = false
        selectedPhotoIds = []
    }

    func toggleSelection(of photo: Photo) {
        if selectedPhotoIds.contains(photo.id) {
            selectedPhotoIds.remove(photo.id)
        } else {
            selectedPhotoIds.insert(photo.id)
        }
    }

    func selectAllPhotos() {
        selectedPhotoIds = Set(photos.map(\.id))
    }

    private func reportNotAuthenticated() {
        alertState = AlertState(
            title: "Error",
            message: "Not authenticated. Please log in again.",
        )
    }
}

extension Photo {
    /// The tags worth showing. `no_tag` is the server's own marker for "this photo has none",
    /// so printing it would say the opposite of what it means.
    var visibleTags: [String] {
        tags.filter { $0 != "no_tag" }
    }
}
