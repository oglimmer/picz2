import Foundation

/// The album's saved map framing (D35). Owner-scoped on the server, so these are the album
/// owner's calls — a share-link visitor only ever reads the framing off the album itself.
extension APIClient {
    func setMapView(
        albumId: Int,
        view: SavedMapView,
        completion: @escaping @Sendable (Result<Album, Error>) -> Void,
    ) {
        send(
            .put,
            "api/albums/\(albumId)/map-view",
            body: MapViewBody(
                centerLat: view.centerLat,
                centerLng: view.centerLng,
                spanLat: view.spanLat,
                spanLng: view.spanLng,
            ),
            expecting: AlbumResponse.self,
        ) { result in
            completion(result.map(\.album))
        }
    }

    /// Puts the map back to framing every pin.
    func clearMapView(albumId: Int, completion: @escaping @Sendable (Result<Album, Error>) -> Void) {
        send(.delete, "api/albums/\(albumId)/map-view", expecting: AlbumResponse.self) { result in
            completion(result.map(\.album))
        }
    }
}

/// Matches `MapViewRequest` on the server: MapKit's `region` as four plain degrees.
private struct MapViewBody: Encodable {
    let centerLat: Double
    let centerLng: Double
    let spanLat: Double
    let spanLng: Double
}
