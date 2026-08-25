import Foundation

/// One of the two narration tracks an album can carry.
///
/// The wire value is the *slot key* (`language1` / `language2`), not the name the user typed —
/// the name lives in the account settings and can be renamed without orphaning a recording. This
/// is exactly what the web gallery sends.
enum NarrationLanguage: String, CaseIterable, Identifiable {
    case language1
    case language2

    var id: String {
        rawValue
    }

    var slot: Int {
        self == .language1 ? 1 : 2
    }
}

/// A saved slideshow narration, mirroring `RecordingInfo` on the server.
///
/// `filterTag` is null for a recording made over the whole album; otherwise it is the tag the
/// slideshow was filtered by. Together with `language` it is the identity the gallery looks a
/// recording up by — one recording per (tag, language) pair.
struct RecordingInfo: Codable, Identifiable, Hashable {
    let id: Int
    let albumId: Int?
    let filterTag: String?
    let language: String?
    let audioFilename: String?
    let publicToken: String?
    let durationMs: Int?
    let createdAt: String?

    /// When each slide was on screen, in the order it was recorded. This is what a preview
    /// replays against the audio — without it the audio is just a voice with no pictures.
    let images: [RecordingImageInfo]?

    var narrationLanguage: NarrationLanguage? {
        language.flatMap(NarrationLanguage.init(rawValue:))
    }

    /// Where the audio is served from.
    ///
    /// The public-token route, not `/api/recordings/{id}/audio`, because `AVPlayer` fetches on
    /// its own and cannot be handed the app's Basic auth without wrapping every request. `GET
    /// /api/r/**` is `permitAll` on the server — the token *is* the credential — which is the
    /// same deal the image loader already takes for `/api/i/{token}`.
    ///
    /// **`format=m4a` is not optional.** The server stores commentaries as Opus in a WebM
    /// container, which Apple's media stack cannot open at all — `AVPlayer` given the master
    /// simply never starts, with no error the user can see. That parameter asks for the AAC
    /// sibling instead, which the server makes on upload (and on first request for older
    /// recordings). Browsers keep getting the Opus master by not passing it.
    var audioURL: URL? {
        guard let publicToken else { return nil }
        var components = URLComponents(
            url: AppConfiguration.apiBaseURL
                .appendingPathComponent("api/r")
                .appendingPathComponent(publicToken)
                .appendingPathComponent("audio"),
            resolvingAgainstBaseURL: false,
        )
        components?.queryItems = [URLQueryItem(name: "format", value: "m4a")]
        return components?.url
    }

    /// The slides in recorded order, with anything the server could not time left out.
    var orderedImages: [RecordingImageInfo] {
        (images ?? []).sorted { ($0.sequenceOrder ?? 0) < ($1.sequenceOrder ?? 0) }
    }
}

/// One slide of a saved commentary: which asset, and the window of the audio it belongs to.
struct RecordingImageInfo: Codable, Hashable {
    let fileId: Int
    let startTimeMs: Int?
    let durationMs: Int?
    let sequenceOrder: Int?
}

/// Answer from `GET /api/r/{token}/audio/status`.
///
/// The server holds the commentary as Opus in a WebM container, which Apple's media stack cannot
/// open, and makes an AAC sibling for iPhone on a background worker. `ready` says that sibling is
/// on storage; `failed` says making it was given up on, so waiting longer is pointless. Neither
/// flag means "being made — ask again shortly".
///
/// This is asked *before* the audio is handed to `AVPlayer`, because `AVPlayer` reports any HTTP
/// failure as an undifferentiated decode error: "not made yet" and "broken" look the same to it.
struct RecordingAudioStatusResponse: Codable {
    let success: Bool
    let ready: Bool
    let failed: Bool
}

struct RecordingsListResponse: Codable {
    let success: Bool
    let count: Int?
    let recordings: [RecordingInfo]
}

struct RecordingResponse: Codable {
    let success: Bool
    let message: String?
    let recording: RecordingInfo?
}

/// The `data` part of the multipart upload. Sent as JSON alongside the audio file, matching
/// `RecordingRequest` on the server.
struct RecordingUploadRequest: Encodable {
    let filterTag: String?
    let language: String
    let durationMs: Int
    let images: [ImageTiming]

    /// When each asset came on screen, relative to the start of the audio, and how long it
    /// stayed. This is the whole point of the feature — playback uses it to advance the
    /// slideshow in step with the voice.
    struct ImageTiming: Encodable {
        let fileId: Int
        let startTimeMs: Int
        let durationMs: Int
    }
}
