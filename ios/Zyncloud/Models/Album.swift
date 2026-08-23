import Foundation

struct Album: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let description: String?
    let createdAt: String?
    let updatedAt: String?
    let displayOrder: Int?
    let fileCount: Int?
    let coverImageFilename: String?
    let coverImageToken: String?
    let shareToken: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case createdAt
        case updatedAt
        case displayOrder
        case fileCount
        case coverImageFilename
        case coverImageToken
        case shareToken
    }

    // Computed property for backwards compatibility
    var imageCount: Int? {
        fileCount
    }
}

struct AlbumsResponse: Codable {
    let success: Bool
    let albums: [Album]
}

struct SyncChecksumsResponse: Codable {
    let success: Bool
    let checksums: [String]
    let count: Int
}
