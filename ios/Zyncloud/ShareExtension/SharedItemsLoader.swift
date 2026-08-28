import Foundation
import UniformTypeIdentifiers
import os

/// Loads the attachments handed to the share extension into `MediaItem`s.
///
/// `NSItemProvider` calls its completions on whichever thread it likes; this type owns all
/// the hops back to the main actor and the `AttachmentLoadTally` bookkeeping, so the view
/// controller sees exactly one callback with the finished batch instead of a
/// per-attachment trickle it has to reassemble.
@MainActor
final class SharedItemsLoader {
    /// Everything one share produced: the usable media, plus how many attachments were not.
    struct Batch {
        var items: [MediaItem] = []
        var skippedCount = 0
    }

    // Accounting for the shared attachments. Every attachment must reach exactly one of
    // recordLoaded/recordSkipped or the batch never completes — see AttachmentLoadTally.
    private var tally = AttachmentLoadTally(total: 0)
    private var batch = Batch()
    private var didFinish = false
    private var completion: ((Batch) -> Void)?

    /// Kicks off a load for every attachment in `items` and returns how many were found.
    /// `completion` runs once, on the main actor, when all of them are accounted for.
    /// When the return value is zero there is nothing to wait for and `completion` is
    /// never called — the caller decides what an empty share means.
    @discardableResult
    func load(from items: [NSExtensionItem], completion: @escaping (Batch) -> Void) -> Int {
        AppLog.share.debug("Found \(items.count, privacy: .public) extension items")

        let totalItemCount = items.reduce(0) { $0 + ($1.attachments?.count ?? 0) }
        tally = AttachmentLoadTally(total: totalItemCount)
        batch = Batch()
        didFinish = false
        self.completion = completion

        AppLog.share.debug("Total attachments: \(totalItemCount, privacy: .public)")

        guard totalItemCount > 0 else { return 0 }

        for item in items {
            guard let attachments = item.attachments else { continue }

            for (index, attachment) in attachments.enumerated() {
                AppLog.share.debug("Processing attachment \(index + 1, privacy: .public)/\(attachments.count, privacy: .public)")
                AppLog.share.debug("Registered types: \(attachment.registeredTypeIdentifiers, privacy: .public)")
                route(attachment)
            }
        }
        return totalItemCount
    }

    // MARK: - Routing

    private func route(_ attachment: NSItemProvider) {
        switch AttachmentRoute.route(for: attachment) {
        case .fileURL:
            AppLog.share.debug("Attachment has a file URL — loading")
            // `NSItemProvider` is not `Sendable`, but the fallback path needs this exact
            // one — it asks the same provider for a different representation. Capturing it
            // is safe because `loadItem` is documented as callable from any thread and
            // nothing here mutates the provider.
            nonisolated(unsafe) let attachment = attachment
            attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] urlData, error in
                if let error {
                    AppLog.share.error("Could not load the file URL: \(error.localizedDescription, privacy: .public)")
                }
                if let url = urlData as? URL {
                    self?.handleLoadedURL(url: url, error: error)
                } else if let urlData = urlData as? Data,
                          let urlString = String(data: urlData, encoding: .utf8),
                          let url = URL(string: urlString)
                {
                    self?.handleLoadedURL(url: url, error: nil)
                } else {
                    self?.loadItemAlternative(attachment: attachment)
                }
            }
        case .image:
            attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, error in
                self?.handleLoadedItem(item: item, error: error, type: .image)
            }
        case .movie:
            attachment.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { [weak self] item, error in
                self?.handleLoadedItem(item: item, error: error, type: .video)
            }
        case .unusable:
            // Matches none of the three types we handle. Without this branch the
            // attachment is never accounted for, the tally never completes, and the
            // UI sits on "Preparing media files…" with Upload disabled — forever.
            AppLog.share.notice("Skipping an unsupported attachment: \(attachment.registeredTypeIdentifiers, privacy: .public)")
            noteUnusableAttachment()
        }
    }

    /// `nonisolated` because `NSItemProvider` calls its completion on whichever thread it
    /// likes, and this is called from one of those. It touches no loader state.
    nonisolated private func loadItemAlternative(attachment: NSItemProvider) {
        switch AttachmentRoute.fallbackRoute(for: attachment) {
        case .image:
            attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, error in
                self?.handleLoadedItem(item: item, error: error, type: .image)
            }
        case .movie:
            attachment.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { [weak self] item, error in
                self?.handleLoadedItem(item: item, error: error, type: .video)
            }
        case .fileURL, .unusable:
            // The file-URL load produced neither a URL nor URL-shaped Data, and the
            // attachment conforms to nothing else we handle. Nothing has counted it yet.
            AppLog.share.notice("Skipping an attachment with no usable representation")
            noteUnusableAttachment()
        }
    }

    // MARK: - Load callbacks

    /// Counts an attachment we cannot use, and completes the batch if it was the last one.
    /// `nonisolated`: reached both from the main-actor routing loop and from an
    /// `NSItemProvider` callback on an arbitrary thread. It hops before touching anything.
    nonisolated private func noteUnusableAttachment() {
        Task { @MainActor [weak self] in
            self?.recordSkipped()
        }
    }

    /// `nonisolated`, and everything it sends to the main actor is a value type.
    ///
    /// The `Error` stays on this side of the hop: `any Error` is not `Sendable`, and all
    /// that is wanted from it is a line for the log.
    nonisolated private func handleLoadedURL(url: URL, error: Error?) {
        let errorText = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let errorText {
                AppLog.share.error("Could not load the URL: \(errorText, privacy: .public)")
                recordSkipped()
                return
            }
            recordLoaded(MediaItem(
                url: url,
                type: Self.mediaType(forPathExtension: url.pathExtension),
                filename: url.lastPathComponent
            ))
        }
    }

    /// `nonisolated`, like its two neighbours.
    ///
    /// The loaded item is unwrapped **here**, before the hop, so that only a `URL` and two
    /// strings cross to the main actor. `NSSecureCoding` is not `Sendable` — handing one to
    /// another thread is a real hazard rather than a paperwork one — and the two things this
    /// method wants from it, "is it a file URL" and "what was it instead", are both
    /// answerable on the thread it arrived on.
    nonisolated private func handleLoadedItem(item: NSSecureCoding?, error: Error?, type: MediaItem.MediaType) {
        let errorText = error?.localizedDescription
        let url = item as? URL
        let describedType = String(describing: item.map { Swift.type(of: $0) })

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let errorText {
                AppLog.share.error("Could not load the item: \(errorText, privacy: .public)")
                recordSkipped()
                return
            }
            if let url {
                recordLoaded(MediaItem(url: url, type: type, filename: url.lastPathComponent))
            } else {
                // In-memory UIImage/Data rather than a file on disk. Uploading those means
                // materialising them to a temp file first, which this extension does not do
                // yet — so count it as skipped instead of dropping it without a trace.
                AppLog.share.notice("Item loaded as \(describedType, privacy: .public), not a URL — skipping")
                recordSkipped()
            }
        }
    }

    // MARK: - Accounting

    private func recordLoaded(_ item: MediaItem) {
        batch.items.append(item)
        tally.noteLoaded()
        finishIfComplete()
    }

    private func recordSkipped() {
        tally.noteSkipped()
        finishIfComplete()
    }

    /// Fires the completion exactly once. The tally's `isComplete` is deliberately `>=`, so
    /// a double-count degrades to "finish early" — the flag keeps that from also meaning
    /// "finish twice".
    private func finishIfComplete() {
        guard tally.isComplete, !didFinish else { return }
        didFinish = true
        batch.skippedCount = tally.skipped
        completion?(batch)
        completion = nil
    }

    /// Image vs video, guessed from the filename; unknown extensions fall back to image.
    private static func mediaType(forPathExtension ext: String) -> MediaItem.MediaType {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp"]
        let videoExtensions = ["mov", "mp4", "m4v", "avi", "wmv", "flv", "mkv", "webm"]
        let lowered = ext.lowercased()
        if imageExtensions.contains(lowered) { return .image }
        if videoExtensions.contains(lowered) { return .video }
        return .image
    }
}
