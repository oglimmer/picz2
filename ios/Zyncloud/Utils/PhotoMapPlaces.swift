import CoreLocation
import Foundation

/// Where the album's map opens: MapKit's `CoordinateRegion` as the server stores it — a centre
/// plus a span in degrees, not a zoom level, because that is the value that round-trips through
/// MapKit untouched (D35). A smaller span shows less ground, i.e. is zoomed in.
struct SavedMapView: Equatable {
    let centerLat: Double
    let centerLng: Double
    let spanLat: Double
    let spanLng: Double
}

/// One pin: the photos taken at one spot.
struct PhotoPlace: Identifiable {
    /// The key the photos were bucketed under. Stable across reloads, so a pin the user has open
    /// stays open when the album is fetched again.
    let id: String

    let latitude: Double
    let longitude: Double

    let photos: [Photo]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Turning an album's photos into map pins. A port of `PhotoMap.vue`'s `places`, kept pure so the
/// bucketing can be checked without a map on screen.
enum PhotoMapPlaces {
    /// How many decimal places the bucketing key keeps. Four is about 11 m: a burst shot from one
    /// spot becomes one pin instead of a smear of overlapping ones, while two ends of a street
    /// stay apart. Anything closer together than that on screen is MapKit's own clustering's job,
    /// which merges by distance in pixels rather than in degrees.
    static let keyDecimals = 4

    /// The photos that can appear on a map at all.
    ///
    /// A location lives only in the original, so a photo uploaded before GPS extraction existed —
    /// or one whose original retention has purged — carries none and is simply not on the map.
    static func located(in photos: [Photo]) -> [Photo] {
        photos.filter { $0.gpsLatitude != nil && $0.gpsLongitude != nil }
    }

    /// Groups located photos into pins, keeping the album's own order both between pins and
    /// inside them — the map re-shelves the album, it does not re-sort it.
    static func places(from photos: [Photo]) -> [PhotoPlace] {
        var order: [String] = []
        var byKey: [String: [Photo]] = [:]

        for photo in located(in: photos) {
            guard let latitude = photo.gpsLatitude, let longitude = photo.gpsLongitude else {
                continue
            }
            let key = self.key(latitude: latitude, longitude: longitude)
            if byKey[key] == nil {
                order.append(key)
                byKey[key] = []
            }
            byKey[key]?.append(photo)
        }

        return order.compactMap { key in
            guard let bucket = byKey[key], let first = bucket.first,
                  let latitude = first.gpsLatitude, let longitude = first.gpsLongitude
            else {
                return nil
            }
            // The pin sits on the first photo's real coordinates, not on the rounded key: the key
            // decides what shares a pin, it is not itself a position.
            return PhotoPlace(id: key, latitude: latitude, longitude: longitude, photos: bucket)
        }
    }

    /// The bucket a coordinate falls in.
    static func key(latitude: Double, longitude: Double) -> String {
        "\(rounded(latitude)),\(rounded(longitude))"
    }

    private static func rounded(_ value: Double) -> String {
        String(format: "%.\(keyDecimals)f", value)
    }

    /// What a pin says. A count only earns the number when there is something to count — a lone
    /// pin reading "1" is noise — and three digits is where a marker glyph starts to clip.
    static func glyph(forPhotoCount count: Int) -> String {
        guard count > 1 else { return "📷" }
        return count > 99 ? "99+" : String(count)
    }

    static func title(forPhotoCount count: Int) -> String {
        count == 1 ? "1 photo" : "\(count) photos"
    }
}
