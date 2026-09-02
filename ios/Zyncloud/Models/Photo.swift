import Foundation

// FileInfo model matching server's FileInfo.java
struct FileInfo: Codable, Identifiable {
    let id: Int
    let originalName: String
    let filename: String? // Can be null in server response
    let publicToken: String
    let size: Int64
    let mimetype: String?
    let path: String? // Can be null in server response
    let uploadedAt: String
    let displayOrder: Int?
    /// `var` for the same reason as ``processingStatus``: tagging one photo answers with that
    /// photo's whole new tag list, and writing it back in place is cheaper and steadier than
    /// reloading the album to learn one row changed.
    var tags: [String]
    let albumId: Int
    let albumName: String?

    /// Where the worker pod has got to with this asset, straight from the file list.
    ///
    /// Kept as the raw string rather than ``AssetProcessingStatus``: decoding an optional enum
    /// from an unknown raw value *throws*, so one status a future server adds would fail the
    /// decode of the whole album rather than of one row. `var` because the poller patches it in
    /// place as the worker progresses — reloading the entire list every two seconds to learn
    /// one photo finished would be a poor trade in an album of several hundred.
    var processingStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case originalName
        case filename
        case publicToken
        case size
        case mimetype
        case path
        case uploadedAt
        case displayOrder
        case tags
        case albumId
        case albumName
        case processingStatus
        case exifDateTimeOriginal
        case captureUtcOffsetSeconds
        case gpsLatitude
        case gpsLongitude
        case caption
    }

    /// When the shutter fired, as the server read it out of the file. An ISO-8601 instant, or
    /// nil for an asset that carried no capture date.
    ///
    /// Declared after ``processingStatus`` on purpose: an optional `var` gets an implicit `nil`
    /// in the memberwise initialiser, so appending fields at the end leaves every existing
    /// `FileInfo(...)` call untouched.
    var exifDateTimeOriginal: String?

    /// UTC offset in seconds at the place the photo was taken, or nil when the server never
    /// knew one. Added back to ``exifDateTimeOriginal`` it gives the wall clock the camera saw,
    /// which is the only honest way to say which day a photo belongs to.
    var captureUtcOffsetSeconds: Int?

    /// Capture position in signed decimal degrees (WGS 84), or nil when the asset carries none.
    var gpsLatitude: Double?

    var gpsLongitude: Double?

    /// The owner's caption for this photo (D69), or nil when it has none. Shown under the
    /// thumbnail in the grid and over the picture in the full-screen view — the same two places
    /// a public visitor sees it on the web.
    ///
    /// `var` for the same reason as ``tags``: saving a caption answers with the updated photo,
    /// and writing that one field back beats reloading the whole album.
    var caption: String?

    var processing: AssetProcessingStatus? {
        processingStatus.flatMap(AssetProcessingStatus.init(rawValue:))
    }

    /// True when the server has something to serve for this asset.
    ///
    /// Asking for a derivative before the worker has made it answers `202 Accepted` with an
    /// empty body, which is not an image — rendering it is what made every freshly uploaded
    /// photo show the red "Failed" icon.
    ///
    /// Compared as a raw string, deliberately, so the rule is the web gallery's exactly: an
    /// *absent* status is an older row and counts as ready, while a status this build does not
    /// recognise counts as not ready. Waiting on a status we cannot read is the safe way round
    /// — the other way shows a broken picture.
    var isThumbnailReady: Bool {
        guard let processingStatus else { return true }
        return processingStatus == AssetProcessingStatus.done.rawValue
    }

    /// The worker gave up. Distinct from "not ready yet": no amount of waiting fixes it.
    var processingFailed: Bool {
        processing == .failed || processing == .deadLetter
    }

    /// True when the stored asset is a video. The gallery has to know, because a video's
    /// bytes are not an image: asking `/api/i/{token}?size=large` for one returns the video
    /// itself (videos get no `large` derivative), and `UIImage(data:)` on that is nil.
    var isVideo: Bool {
        mimetype?.lowercased().hasPrefix("video/") ?? false
    }

    // Computed properties for backwards compatibility
    var thumbnailPath: String? { nil }
    var mediumPath: String? { nil }
    var largePath: String? { nil }
    var transcodedVideoPath: String? { nil }
    var width: Int? { nil }
    var height: Int? { nil }
    var duration: Int64? { nil }
}

struct FilesResponse: Codable {
    let success: Bool
    let files: [FileInfo]
    let count: Int?
    let totalSize: Int64?
}

// Backwards compatibility typealias
typealias Photo = FileInfo
typealias PhotosResponse = FilesResponse
