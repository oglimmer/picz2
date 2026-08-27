import Foundation

/// One rendered block of a presentation: a heading and the photos underneath it.
struct PresentationSection: Identifiable {
    /// nil for the photos that come before the first group marker. Those genuinely belong to no
    /// group, so they are shown without a heading rather than under an invented one.
    let group: PresentationGroup?

    let photos: [Photo]

    /// Group id, or ``leadID`` for the headingless run at the top. Ids from the server are
    /// positive, so the two can never collide.
    var id: Int {
        group?.id ?? Self.leadID
    }

    static let leadID = -1
}

/// What the chapter marker over a full-screen photo says: which section it sits in, and where in
/// that section it is.
struct PresentationChapter: Equatable {
    /// The group's id. The marker re-appears when this changes, so it is keyed on the id rather
    /// than the label — two adjacent groups sharing a label still re-trigger it.
    let id: Int

    let label: String
    let text: String?

    /// 1-based place of this photo inside its group.
    let position: Int

    let total: Int
}

/// What a presentation is currently showing.
///
/// The map is its own case rather than a sentinel tag name, and that is the point: `selectedTag`
/// feeds the commentary lookup and the chapter markers, so a sentinel leaking into it would be a
/// silent data bug rather than a compile error. The web app reaches the same end through a
/// `filterSelection` proxy for the same reason (D34) — one dropdown still means one active
/// filter, so choosing the map clears the tag rather than intersecting with it.
enum PresentationFilter: Hashable {
    /// Nothing picked yet. The screen asks for a tag rather than showing the whole album.
    ///
    /// Spelled `unset` rather than `none` so the case can never be mistaken for `Optional.none`
    /// in an inferred context — a mix-up the compiler only warns about.
    case unset

    case tag(String)

    /// The album's located photos on Apple Maps.
    case map

    /// The tag this filter selects, or nil for the two cases that select no tag at all.
    var tagName: String? {
        guard case let .tag(name) = self else { return nil }
        return name
    }

    var isMap: Bool {
        self == .map
    }
}

/// A chapter about to be written: what the form holds, once it has been checked.
///
/// The rules are the server's own `PresentationGroupService.normalizedLabel` / `normalizedText`,
/// applied here so a slip is caught before the round trip: the web can lean on `maxlength` on an
/// `<input>` to make an over-long value unreachable, and a `TextField` has no such thing.
struct PresentationGroupDraft: Equatable {
    let label: String

    /// nil for a blank body. Blank collapses to nil on the server too, so this keeps both sides
    /// testing one thing rather than two.
    let text: String?

    /// Why a draft was refused. Each maps to what the server would have said, so the phone and
    /// the browser refuse the same input for the same stated reason.
    enum Problem: Error, Equatable {
        case labelMissing
        case labelTooLong
        case textTooLong

        var message: String {
            switch self {
            case .labelMissing:
                "A chapter needs a label."
            case .labelTooLong:
                "The label can be at most \(PresentationGroupDraft.maxLabelLength) characters."
            case .textTooLong:
                "The text can be at most \(PresentationGroupDraft.maxTextLength) characters."
            }
        }
    }

    static let maxLabelLength = 120
    static let maxTextLength = 4000

    static func make(label: String, text: String) -> Result<PresentationGroupDraft, Problem> {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else { return .failure(.labelMissing) }
        guard trimmedLabel.count <= maxLabelLength else { return .failure(.labelTooLong) }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count <= maxTextLength else { return .failure(.textTooLong) }

        return .success(
            PresentationGroupDraft(
                label: trimmedLabel,
                text: trimmedText.isEmpty ? nil : trimmedText,
            ),
        )
    }
}

/// How a presentation is shelved: which tags it can be read under, which sections one tag breaks
/// into, and which chapter a given photo sits in.
///
/// A port of the web app's `usePresentationGroups`, kept pure so the same album breaks into the
/// same sections on both clients.
enum PresentationGallery {
    /// A tag the presentation can be read under, and how many photos it covers.
    struct TagCount: Identifiable, Hashable {
        let name: String
        let count: Int

        var id: String {
            name
        }
    }

    /// The tags this album's photos actually carry, with their counts.
    ///
    /// `no_tag` is left out: it is the server's marker for "this photo has none", so offering it
    /// as a filter would say the opposite of what it means. Sorted by name, case-insensitively,
    /// so the list does not reshuffle between visits.
    static func tagCounts(for photos: [Photo]) -> [TagCount] {
        var counts: [String: Int] = [:]
        for photo in photos {
            for tag in photo.tags where tag != "no_tag" {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .map { TagCount(name: $0.key, count: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The photos a presentation of `tag` walks, in album order.
    ///
    /// Filtered on the phone rather than by refetching with `?tag=`: the server applies the
    /// identical `tags.contains` test, and the whole list is already here. A nil tag means the
    /// album has no tags at all, which is the one case the web gallery shows unfiltered.
    static func photos(from photos: [Photo], tag: String?) -> [Photo] {
        guard let tag else { return photos }
        return photos.filter { $0.tags.contains(tag) }
    }

    /// Breaks the tag-filtered list into sections by walking it and handing every photo to the
    /// last anchor it passed.
    ///
    /// - Parameter photos: already filtered to `tag`, in the order they are to be read.
    static func sections(
        from photos: [Photo],
        groups: [PresentationGroup],
        tag: String?,
    ) -> [PresentationSection] {
        let tagGroups = tag.map { name in groups.filter { $0.tag == name } } ?? []

        guard !tagGroups.isEmpty else {
            return photos.isEmpty ? [] : [PresentationSection(group: nil, photos: photos)]
        }

        // The server holds (album, tag, start_file_id) unique, so a collision here cannot happen;
        // keeping the later one matches what the web app's Map does if one ever did.
        let byStartFile = Dictionary(
            tagGroups.map { ($0.startFileId, $0) },
            uniquingKeysWith: { _, latest in latest },
        )

        var sections: [PresentationSection] = []
        var openGroup: PresentationGroup?
        var openPhotos: [Photo] = []

        for photo in photos {
            if let starting = byStartFile[photo.id] {
                // Drop the leading run when the very first photo already starts a group —
                // otherwise every such presentation opens with an empty headingless section.
                if openGroup != nil || !openPhotos.isEmpty {
                    sections.append(PresentationSection(group: openGroup, photos: openPhotos))
                }
                openGroup = starting
                openPhotos = []
            }
            openPhotos.append(photo)
        }

        if openGroup != nil || !openPhotos.isEmpty {
            sections.append(PresentationSection(group: openGroup, photos: openPhotos))
        }

        return sections
    }

    /// Which chapter the photo being looked at sits in, and where in it.
    ///
    /// Returns nil for a photo ahead of the first group: those belong to no group, and an empty
    /// marker would read as a bug rather than as an absence.
    static func chapter(
        in sections: [PresentationSection],
        forPhotoID photoID: Int?,
    ) -> PresentationChapter? {
        guard let photoID else { return nil }

        for section in sections {
            guard let index = section.photos.firstIndex(where: { $0.id == photoID }) else {
                continue
            }
            guard let group = section.group else { return nil }

            return PresentationChapter(
                id: group.id,
                label: group.label,
                text: group.text,
                position: index + 1,
                total: section.photos.count,
            )
        }

        return nil
    }
}
