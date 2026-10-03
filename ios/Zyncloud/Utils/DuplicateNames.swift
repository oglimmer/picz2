import Foundation

/// Which photos in an album carry a name another photo also carries — the rule behind
/// "Find Duplicates".
///
/// A port of the web gallery's `useDuplicateMode.ts`, so the same album finds the same copies in
/// the browser and on the phone. Change one, change both.
enum DuplicateNames {
    /// A JPEG and a HEIC of the same shot are the same photo, so these extensions share one key.
    /// A video is left out on purpose: a Live Photo's IMG_1.MOV belongs to IMG_1.HEIC and is no
    /// copy.
    private static let samePhotoExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif"]

    /// iOS exports every edited Live Photo as "FullSizeRender.heic", so that name is never a
    /// duplicate worth flagging.
    private static let excludedStem = "fullsizerender"

    /// "IMG_1.jpg", "IMG_1.JPEG" and "IMG_1.heic" all give "IMG_1.jpg"; any other name is itself.
    static func key(for name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        let ext = name[name.index(after: dot)...].lowercased()
        guard samePhotoExtensions.contains(ext) else { return name }
        return String(name[..<dot]) + ".jpg"
    }

    /// The photos that share a name with another, in album order.
    static func duplicates(in photos: [Photo]) -> [Photo] {
        var counts: [String: Int] = [:]
        for photo in photos where !isExcluded(photo) {
            counts[key(of: photo), default: 0] += 1
        }
        return photos.filter { !isExcluded($0) && counts[key(of: $0), default: 0] > 1 }
    }

    /// Every copy but the first of each name — what the mode picks for the user, so one Delete
    /// removes the extras and keeps one of each.
    static func extraCopies(in photos: [Photo]) -> Set<Int> {
        var seen: Set<String> = []
        var extras: Set<Int> = []
        for photo in photos where !isExcluded(photo) {
            if !seen.insert(key(of: photo)).inserted {
                extras.insert(photo.id)
            }
        }
        return extras
    }

    private static func name(of photo: Photo) -> String {
        photo.originalName.isEmpty ? (photo.filename ?? "") : photo.originalName
    }

    private static func key(of photo: Photo) -> String {
        key(for: name(of: photo))
    }

    /// A text card's name is its headline (D86), and two chapters may well share one.
    private static func isExcluded(_ photo: Photo) -> Bool {
        photo.isTextCard || key(of: photo).lowercased() == "\(excludedStem).jpg"
    }
}
