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

    /// Applies a batch of staged tag changes to the picked photos.
    ///
    /// `changes` maps a tag name to what it should become across the whole selection: `true`
    /// puts it on every picked photo, `false` takes it off all of them. Untouched tags are not
    /// in the map and are not sent.
    ///
    /// The bulk sheet stages taps and hands the lot over here on Done, so the batch reports once
    /// instead of once per tag — an alert per tag is what used to force the sheet shut on the
    /// first tap.
    func applyTagChangesToSelection(_ changes: [String: Bool]) {
        guard let apiClient else {
            reportNotAuthenticated()
            return
        }

        let photoIds = selectedPhotoIds
        guard !changes.isEmpty, !photoIds.isEmpty, !isApplyingTags else { return }

        isApplyingTags = true

        Task {
            var changed = 0
            var failed = 0
            var firstError: Error?

            // Sorted so a half-failed run reports the same way twice. Dictionary order is not
            // stable, and the error carried out is the first one seen.
            for (tagName, add) in changes.sorted(by: { $0.key < $1.key }) {
                let outcome = await change(tagName, add: add, on: photoIds, using: apiClient)
                changed += outcome.changed
                failed += outcome.failed
                if firstError == nil {
                    firstError = outcome.firstError
                }
            }

            isApplyingTags = false
            reportBatchOutcome(changed: changed, failed: failed, firstError: firstError, photoCount: photoIds.count)
        }
    }

    /// The path a single tag change takes, from the one-photo menu and the album-wide sheet.
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
            let outcome = await change(tagName, add: add, on: photoIds, using: apiClient)
            isApplyingTags = false

            // One photo is a tap on a menu item — it either worked, and the tick moves, or it
            // did not, and the error is worth a word. Nothing to announce in between.
            if photoIds.count == 1 {
                if let error = outcome.firstError {
                    handleError(error)
                }
                return
            }

            if outcome.failed > 0, outcome.changed == 0, let error = outcome.firstError {
                handleError(error)
                return
            }

            reportTagOutcome(
                tagName,
                add: add,
                changed: outcome.changed,
                failed: outcome.failed,
                total: outcome.total,
            )
        }
    }

    /// What one tag's change did. Handed back rather than alerted about, so a batch of tags can
    /// report once for the lot instead of once each.
    private struct TagChangeOutcome {
        var changed = 0
        var failed = 0
        var total = 0
        var firstError: Error?
    }

    /// Puts `tagName` into the wanted state on every one of `photoIds`. Reports nothing — the
    /// caller decides what to say.
    private func change(
        _ tagName: String,
        add: Bool,
        on photoIds: Set<Int>,
        using apiClient: APIClient,
    ) async -> TagChangeOutcome {
        // Every photo in the album: one request instead of one per photo. Only worth the
        // different code path for a real selection — a single photo goes the plain way,
        // which answers with that photo's new tag list and so needs no reload.
        if photoIds.count > 1, photoIds.count == photos.count {
            return await applyTagToWholeAlbum(tagName, add: add, using: apiClient)
        }
        return await applyTagPhotoByPhoto(tagName, add: add, to: photoIds, using: apiClient)
    }

    private func applyTagToWholeAlbum(
        _ tagName: String,
        add: Bool,
        using apiClient: APIClient,
    ) async -> TagChangeOutcome {
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
            return TagChangeOutcome(changed: changed, failed: 0, total: photos.count, firstError: nil)
        case let .failure(error):
            return TagChangeOutcome(changed: 0, failed: 1, total: photos.count, firstError: error)
        }
    }

    private func applyTagPhotoByPhoto(
        _ tagName: String,
        add: Bool,
        to photoIds: Set<Int>,
        using apiClient: APIClient,
    ) async -> TagChangeOutcome {
        var outcome = TagChangeOutcome(total: photoIds.count)

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
                outcome.changed += 1
                if let index = photos.firstIndex(where: { $0.id == id }) {
                    photos[index].tags = tags
                }
            case let .failure(error):
                outcome.failed += 1
                if outcome.firstError == nil {
                    outcome.firstError = error
                }
            }
        }

        return outcome
    }

    /// One word for a whole batch. `changed` and `failed` count photo-by-tag changes, not
    /// photos: two tags across five photos is ten of them.
    private func reportBatchOutcome(changed: Int, failed: Int, firstError: Error?, photoCount: Int) {
        if changed == 0, failed > 0, let firstError {
            handleError(firstError)
            return
        }

        if failed > 0 {
            alertState = AlertState(
                title: "Some Changes Not Saved",
                message: "\(failed) of \(changed + failed) changes failed — pull down to refresh and try those again.",
            )
            return
        }

        guard changed > 0 else {
            alertState = AlertState(
                title: "Nothing to Change",
                message: "Those photos already had the tags you picked.",
            )
            return
        }

        let photoWord = photoCount == 1 ? "photo" : "photos"
        let changeWord = changed == 1 ? "change" : "changes"
        alertState = AlertState(
            title: "Tags Saved",
            message: "\(changed) \(changeWord) across \(photoCount) \(photoWord).",
        )
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

    /// Starts picking with `photo` already picked. This is what a long press on a tile does, so
    /// that the gesture that opens the mode also counts as the first tap in it.
    func beginSelecting(with photo: Photo) {
        selectedPhotoIds = [photo.id]
        isSelecting = true
    }

    /// Whether Rotate has anything to work on. Videos cannot be rotated, so a selection of only
    /// videos leaves the button off rather than failing on every one of them.
    var selectionHasRotatablePhoto: Bool {
        selectedPhotos.contains { !$0.isVideo }
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
