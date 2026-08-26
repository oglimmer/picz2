import Combine
import Foundation

/// Puts a place name on a region heading ("Munich", "Sankt Peter-Ording") by asking our own
/// `/api/geocode/reverse`, which answers from its cache and only falls through to Apple for a
/// coordinate nobody has ever asked about. Same endpoint the web gallery uses, so both clients
/// label the same spot the same way.
///
/// Deliberately not `CLGeocoder`: that re-asks Apple once per device, spends the quota on every
/// scroll, and needs no cache to be slow. One shared server-side cache costs one lookup per
/// place, ever.
///
/// This is decoration, never data. Coordinates are shown the moment a label is asked for and a
/// name replaces them if one arrives; an unreachable server, a throttled endpoint or an install
/// with no Apple credentials all leave the coordinates standing.
@MainActor
final class RegionNameStore: ObservableObject {
    /// How a batch of coordinates is turned into names. The app passes the server; a test passes
    /// its own so the batching, the de-duplication and the back-off can be checked without a
    /// network — none of which is reachable otherwise, because the store owns its API client.
    typealias Geocoder = (_ points: [LatLng], _ language: String?) async -> Result<[ReverseGeocodedPlace], Error>

    /// Shared because names are account-wide: switching albums, or turning the grouping off and
    /// on, never re-asks for a place already known.
    static let shared = RegionNameStore()

    /// Resolved names by snapped key. Published so every heading re-renders when names land.
    @Published private(set) var names: [String: String] = [:]

    /// Keys already sent, whatever came back. A coordinate the server has no name for is not
    /// asked about twice.
    private var asked: Set<String> = []

    /// Keys waiting for the next batch.
    private var pending: [String: LatLng] = [:]

    private var flushTask: Task<Void, Never>?

    /// After a 429 or a network error, stop asking until this moment rather than hammering.
    private var backoffUntil: Date = .distantPast

    /// Server cap (`maps.geocode.max-points-per-request`); larger batches are split.
    private let maxPointsPerRequest: Int

    /// How long to collect misses before sending. A grouped album lays out every heading in one
    /// pass, so a short wait turns twenty requests into one.
    private let batchDelay: Duration

    private let backoff: TimeInterval = 60

    private let geocode: Geocoder

    /// Read instead of calling `Date()` directly, so a test can walk past the back-off window
    /// rather than sleeping through a minute of it.
    private let now: () -> Date

    /// The default arguments are the whole production configuration; every one of them is a
    /// parameter only so a test can replace it.
    init(
        maxPointsPerRequest: Int = 60,
        batchDelay: Duration = .milliseconds(50),
        now: @escaping @Sendable () -> Date = { Date() },
        geocode: @escaping Geocoder = { points, language in
            await withCheckedContinuation { continuation in
                APIClient().reverseGeocode(points: points, language: language) {
                    continuation.resume(returning: $0)
                }
            }
        },
    ) {
        self.maxPointsPerRequest = maxPointsPerRequest
        self.batchDelay = batchDelay
        self.now = now
        self.geocode = geocode
    }

    /// Matches the server's snapping (degrees × 10⁴), so both sides agree what "same spot" means.
    /// Internal rather than private because a test has to be able to state that snapping
    /// independently — it is a contract with the server, not an implementation detail.
    func key(for at: LatLng) -> String {
        String(format: "%.4f,%.4f", at.lat, at.lng)
    }

    /// The name for this place, or nil while none is known. Asking also queues the lookup, so a
    /// heading only has to render itself to get named.
    func name(for at: LatLng) -> String? {
        let key = key(for: at)
        if let known = names[key] {
            return known
        }
        request(at, key: key)
        return nil
    }

    /// What a heading shows: the place name once it is known, coordinates until then.
    func label(for at: LatLng) -> String {
        name(for: at) ?? formatCoordinates(at)
    }

    private func request(_ at: LatLng, key: String) {
        guard !asked.contains(key), pending[key] == nil else { return }
        guard now() >= backoffUntil else { return }

        pending[key] = at
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }

        flushTask = Task { [weak self] in
            try? await Task.sleep(for: self?.batchDelay ?? .milliseconds(50))
            guard let self else { return }
            self.flushTask = nil
            await self.flush()
        }
    }

    private func flush() async {
        guard !pending.isEmpty else { return }
        guard now() >= backoffUntil else {
            pending.removeAll()
            return
        }

        let batch = Array(pending.prefix(maxPointsPerRequest))
        for (key, _) in batch {
            pending.removeValue(forKey: key)
            asked.insert(key)
        }

        let result = await geocode(batch.map(\.value), Locale.preferredLanguages.first)

        switch result {
        case let .success(places):
            for place in places {
                guard let name = place.name, !name.isEmpty else { continue }
                names[key(for: LatLng(lat: place.lat, lng: place.lng))] = name
            }
        case .failure:
            // Whatever went wrong — throttled, offline, no credentials — the answer is the same:
            // leave the coordinates standing and stop asking for a while. The keys stay in
            // `asked` so a scroll does not immediately retry them.
            backoffUntil = now().addingTimeInterval(backoff)
        }

        // Anything that did not fit in this batch goes out in the next one.
        if !pending.isEmpty {
            scheduleFlush()
        }
    }

    /// Waits until every queued lookup has been sent and answered, including the follow-up
    /// batches a large day splits into. Only a test calls this; the app just lets the batch
    /// timer fire.
    func awaitPendingLookups() async {
        while let task = flushTask {
            await task.value
        }
    }
}

/// One coordinate and the name the server knows for it. `name` is null when it knows none.
struct ReverseGeocodedPlace: Decodable {
    let lat: Double
    let lng: Double
    let name: String?
}

struct ReverseGeocodeResponse: Decodable {
    let places: [ReverseGeocodedPlace]
}

extension APIClient {
    /// Names a batch of coordinates. Unauthenticated on purpose — public share links group by
    /// place too, so the endpoint is open and no credentials are sent to it.
    func reverseGeocode(
        points: [LatLng],
        language: String?,
        completion: @escaping @Sendable (Result<[ReverseGeocodedPlace], Error>) -> Void,
    ) {
        guard !points.isEmpty else {
            completion(.success([]))
            return
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/geocode/reverse"),
            resolvingAgainstBaseURL: false,
        )

        var queryItems = points.map {
            URLQueryItem(name: "loc", value: String(format: "%.6f,%.6f", $0.lat, $0.lng))
        }
        if let language, !language.isEmpty {
            queryItems.append(URLQueryItem(name: "lang", value: language))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            completion(.failure(AppError.api(message: "Could not build the geocode request.", statusCode: nil)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        performRequest(request, expecting: ReverseGeocodeResponse.self) { result in
            completion(result.map(\.places))
        }
    }
}
