import Foundation
import Photos
import UniformTypeIdentifiers

/// What to call an exported asset on disk, and what to tell the server it is.
///
/// Extracted rather than left inline for the same reason as ``ExportRetryPolicy`` and
/// ``UploadSizeLimit``: it is a decision with edge cases, and it needs to be testable without a
/// photo library.
///
/// The bug it exists for: ``Uploader/exportAssetToTempFile(_:completion:)`` used to switch on
/// ``PHAssetResourceType`` alone and label **everything that was not a video** `image/jpeg` with a
/// `.jpg` extension. An iPhone photo is HEIC, so every one of them was uploaded describing itself
/// as a JPEG. That survived only because the server also sniffs the filename — see
/// `FileProcessingService.processFile`, which treats a file as HEIC when the mime type *or* the
/// extension says so. Take the extension away — `PHAssetResource.originalFilename` without one,
/// so the client invents `<uuid>.jpg` — and the rescue is gone: HEIC bytes labelled JPEG reach
/// libvips, thumbnail generation produces nothing, and the asset lands in FAILED.
///
/// The resource already knows what it is. `uniformTypeIdentifier` is the answer, and it carries
/// both halves.
enum ExportFormat {
    struct Format: Equatable {
        let fileExtension: String
        let mimeType: String
    }

    /// Used when the resource has no usable UTI. These are the values the old switch produced,
    /// so an asset that cannot describe itself behaves exactly as it did before.
    static let photoFallback = Format(fileExtension: "jpg", mimeType: "image/jpeg")
    static let videoFallback = Format(fileExtension: "mov", mimeType: "video/quicktime")

    /// - Parameter uniformTypeIdentifier: `PHAssetResource.uniformTypeIdentifier`, e.g.
    ///   `public.heic`. Optional because the fallback has to be reachable from a test.
    static func forResource(type: PHAssetResourceType, uniformTypeIdentifier: String?) -> Format {
        let fallback = isVideo(type) ? videoFallback : photoFallback
        guard let uniformTypeIdentifier,
              let utType = UTType(uniformTypeIdentifier),
              let mimeType = utType.preferredMIMEType,
              let fileExtension = utType.preferredFilenameExtension
        else { return fallback }
        return Format(fileExtension: fileExtension, mimeType: mimeType)
    }

    /// Both halves of a Live Photo count: the paired-video resources are movies, and picking the
    /// photo fallback for one would name an MOV `.jpg`.
    private static func isVideo(_ type: PHAssetResourceType) -> Bool {
        switch type {
        case .video, .fullSizeVideo, .pairedVideo, .fullSizePairedVideo:
            return true
        default:
            return false
        }
    }
}
