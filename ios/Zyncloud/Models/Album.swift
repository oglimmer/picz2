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

    /// Where the album's map opens, as MapKit's `CoordinateRegion` — centre plus a span in
    /// degrees, not a zoom level (D35). All four are null together when the owner has saved no
    /// view, and the map frames every pin instead. See ``savedMapView``.
    ///
    /// `var` rather than `let`, and appended after `shareToken`: an optional `var` gets an
    /// implicit `nil` in the memberwise initialiser, so every existing `Album(...)` call keeps
    /// compiling. Optional `let`s get no such default.
    var mapCenterLat: Double?
    var mapCenterLng: Double?
    var mapSpanLat: Double?
    var mapSpanLng: Double?

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
        case mapCenterLat
        case mapCenterLng
        case mapSpanLat
        case mapSpanLng
    }

    // Computed property for backwards compatibility
    var imageCount: Int? {
        fileCount
    }

    /// The framing the owner saved for this album's map, or nil to fit every pin.
    ///
    /// All four fields or none: a half-saved view would centre the map on null island, which is
    /// exactly what the server's `MapView.of` refuses to store in the first place.
    var savedMapView: SavedMapView? {
        guard let mapCenterLat, let mapCenterLng, let mapSpanLat, let mapSpanLng else {
            return nil
        }
        return SavedMapView(
            centerLat: mapCenterLat,
            centerLng: mapCenterLng,
            spanLat: mapSpanLat,
            spanLng: mapSpanLng,
        )
    }
}

struct AlbumsResponse: Codable {
    let success: Bool
    let albums: [Album]
}

/// Answer to `GET /api/sync/uploaded-content-ids` — the reconciliation that survives a
/// reinstall, since a contentId is the photo library's own identifier rather than one this app
/// invented (§5.8).
struct SyncContentIdsResponse: Codable {
    let success: Bool
    let contentIds: [String]
    let count: Int
}

struct SyncChecksumsResponse: Codable {
    let success: Bool
    let checksums: [String]
    let count: Int
}
