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
    let tags: [String]
    let albumId: Int
    let albumName: String?

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
