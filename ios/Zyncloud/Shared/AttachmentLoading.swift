import Foundation
import UniformTypeIdentifiers

#if canImport(MobileCoreServices)
    import MobileCoreServices
#endif

/// Which of the share extension's three load paths an attachment takes.
///
/// The `unusable` case is the point of this type. The original code was a bare
/// `if / else if / else if` with no final branch, so an attachment conforming to none of
/// the three simply fell through — never loaded, never counted, and the UI waited on it
/// forever. Making the outcome an enum means "none of them" is a value someone has to
/// handle rather than a gap in a chain.
enum AttachmentRoute: Equatable {
    case fileURL
    case image
    case movie
    case unusable
}

extension AttachmentRoute {
    /// The routing decision as a pure function of the three type checks, in the order the
    /// extension applies them. Split out from `NSItemProvider` so the truth table can be
    /// tested exhaustively without constructing providers.
    static func route(
        conformsToFileURL: Bool,
        conformsToImage: Bool,
        conformsToMovie: Bool
    ) -> AttachmentRoute {
        if conformsToFileURL { return .fileURL }
        if conformsToImage { return .image }
        if conformsToMovie { return .movie }
        return .unusable
    }

    /// The fallback used when a file-URL load yields neither a URL nor URL-shaped `Data`.
    /// File URL is deliberately not reconsidered — it is the path that just failed.
    static func fallbackRoute(conformsToImage: Bool, conformsToMovie: Bool) -> AttachmentRoute {
        if conformsToImage { return .image }
        if conformsToMovie { return .movie }
        return .unusable
    }

    static func route(for provider: NSItemProvider) -> AttachmentRoute {
        route(
            conformsToFileURL: provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
            conformsToImage: provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
            conformsToMovie: provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
        )
    }

    static func fallbackRoute(for provider: NSItemProvider) -> AttachmentRoute {
        fallbackRoute(
            conformsToImage: provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
            conformsToMovie: provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
        )
    }
}

/// Tracks how many shared attachments have been accounted for, so the extension knows when
/// the batch is done.
///
/// `total` is fixed up front from the attachment count rather than accumulated as loads are
/// dispatched: an attachment that completes instantly would otherwise satisfy the
/// completion condition before the loop had finished queueing the rest.
struct AttachmentLoadTally: Equatable {
    let total: Int
    private(set) var processed = 0
    private(set) var skipped = 0

    init(total: Int) {
        self.total = total
    }

    /// Accounted for, and produced a usable media item.
    mutating func noteLoaded() {
        processed += 1
    }

    /// Accounted for, but produced nothing usable — an unsupported type, a load error, or a
    /// payload that came back as something other than a file URL.
    mutating func noteSkipped() {
        processed += 1
        skipped += 1
    }

    /// Deliberately `>=` and not `==`. If anything ever double-counts, an equality test
    /// would step straight past the completion point and hang exactly like the bug this
    /// type replaced; `>=` degrades to "finish early" instead of "never finish".
    var isComplete: Bool {
        processed >= total
    }
}
