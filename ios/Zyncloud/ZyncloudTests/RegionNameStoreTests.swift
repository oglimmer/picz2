import Foundation
import Testing

@testable import Zyncloud

/// The place-name cache behind every "By Day & Place" heading.
///
/// Nothing here is decoration-only from the store's point of view: it decides how many requests
/// an album lays out, whether a coordinate is ever asked about twice, and what happens when the
/// endpoint says no. All of that used to run only against a live server.
@MainActor
struct RegionNameStoreTests {
    // MARK: - A recording stand-in for the server

    /// Records what was asked for, and answers with whatever the test lined up.
    final class FakeGeocoder {
        /// One entry per request the store made, in order.
        private(set) var batches: [[LatLng]] = []
        private(set) var languages: [String?] = []

        /// Names to answer with, by the store's own snapped key. Anything absent comes back
        /// named `nil`, which is what the server sends for a coordinate it knows no name for.
        var names: [String: String] = [:]

        /// When set, every request fails with this instead of answering.
        var failure: Error?

        var requestCount: Int { batches.count }

        func geocode(_ points: [LatLng], _ language: String?) -> Result<[ReverseGeocodedPlace], Error> {
            batches.append(points)
            languages.append(language)
            if let failure {
                return .failure(failure)
            }
            return .success(points.map { point in
                ReverseGeocodedPlace(
                    lat: point.lat,
                    lng: point.lng,
                    name: names[String(format: "%.4f,%.4f", point.lat, point.lng)],
                )
            })
        }
    }

    private struct Offline: Error {}

    /// A store wired to `fake`, with the batch timer removed so tests do not sleep.
    private func store(
        _ fake: FakeGeocoder,
        maxPointsPerRequest: Int = 60,
        now: @escaping () -> Date = Date.init,
    ) -> RegionNameStore {
        RegionNameStore(
            maxPointsPerRequest: maxPointsPerRequest,
            batchDelay: .zero,
            now: now,
            geocode: { points, language in fake.geocode(points, language) },
        )
    }

    private func munich() -> LatLng { LatLng(lat: 48.1372, lng: 11.5755) }

    // MARK: - Snapping

    /// The key is the contract with the server: it snaps to 4 decimal places, which is about
    /// 11 m. Both sides have to agree, or the client caches under a key the server never used.
    @Test func theKeySnapsToFourDecimalPlaces() {
        let store = store(FakeGeocoder())

        #expect(store.key(for: LatLng(lat: 48.1372, lng: 11.5755)) == "48.1372,11.5755")
        #expect(store.key(for: LatLng(lat: 48.13724, lng: 11.57551)) == "48.1372,11.5755")
        #expect(store.key(for: LatLng(lat: -0.00004, lng: -0.00004)) == "-0.0000,-0.0000")
        #expect(store.key(for: LatLng(lat: 48, lng: 11)) == "48.0000,11.0000")
    }

    /// Two coordinates 11 m apart are one place as far as naming is concerned, so they must be
    /// one lookup, not two.
    @Test func twoCoordinatesInsideOneSnapAreOneLookup() async {
        let fake = FakeGeocoder()
        let store = store(fake)

        _ = store.name(for: LatLng(lat: 48.13721, lng: 11.57552))
        _ = store.name(for: LatLng(lat: 48.13723, lng: 11.57554))
        await store.awaitPendingLookups()

        #expect(fake.requestCount == 1)
        #expect(fake.batches[0].count == 1)
    }

    // MARK: - Labels

    /// The heading shows coordinates the instant it is drawn, and swaps to a name only if one
    /// turns up. It never shows nothing.
    @Test func theLabelIsCoordinatesUntilANameLands() async {
        let fake = FakeGeocoder()
        fake.names["48.1372,11.5755"] = "Munich"
        let store = store(fake)

        #expect(store.label(for: munich()) == formatCoordinates(munich()))

        await store.awaitPendingLookups()

        #expect(store.label(for: munich()) == "Munich")
        #expect(store.name(for: munich()) == "Munich")
    }

    /// A coordinate the server knows no name for keeps its coordinates — and, crucially, is not
    /// asked about again. Otherwise every scroll past that heading is another request.
    @Test func aCoordinateWithNoNameIsNotAskedAboutTwice() async {
        let fake = FakeGeocoder()
        let store = store(fake)

        _ = store.name(for: munich())
        await store.awaitPendingLookups()
        #expect(fake.requestCount == 1)
        #expect(store.label(for: munich()) == formatCoordinates(munich()))

        _ = store.name(for: munich())
        await store.awaitPendingLookups()

        #expect(fake.requestCount == 1, "a nameless coordinate must not be re-requested")
    }

    /// An empty string is the same as no name — showing a blank heading would be worse than
    /// showing the coordinates.
    @Test func anEmptyNameIsTreatedAsNoName() async {
        let fake = FakeGeocoder()
        fake.names["48.1372,11.5755"] = ""
        let store = store(fake)

        _ = store.name(for: munich())
        await store.awaitPendingLookups()

        #expect(store.name(for: munich()) == nil)
        #expect(store.label(for: munich()) == formatCoordinates(munich()))
    }

    /// A name already known answers straight away and sends nothing.
    @Test func aKnownNameCostsNoRequest() async {
        let fake = FakeGeocoder()
        fake.names["48.1372,11.5755"] = "Munich"
        let store = store(fake)

        _ = store.name(for: munich())
        await store.awaitPendingLookups()
        let afterFirst = fake.requestCount

        for _ in 0 ..< 20 {
            #expect(store.name(for: munich()) == "Munich")
        }
        await store.awaitPendingLookups()

        #expect(fake.requestCount == afterFirst)
    }

    // MARK: - Batching

    /// A grouped album draws every heading in one pass. The whole point of the batch delay is
    /// that this becomes one request, not one per heading.
    @Test func awholeScreenOfHeadingsBecomesOneRequest() async {
        let fake = FakeGeocoder()
        let store = store(fake)

        for index in 0 ..< 20 {
            _ = store.name(for: LatLng(lat: 48.0 + Double(index) * 0.01, lng: 11.0))
        }
        await store.awaitPendingLookups()

        #expect(fake.requestCount == 1)
        #expect(fake.batches[0].count == 20)
    }

    /// Over the server's per-request cap the batch is split, and every coordinate still gets
    /// asked about — the leftovers must not be dropped on the floor.
    @Test func abatchOverTheServerCapIsSplitAndNothingIsLost() async {
        let fake = FakeGeocoder()
        let store = store(fake, maxPointsPerRequest: 10)

        for index in 0 ..< 25 {
            _ = store.name(for: LatLng(lat: 48.0 + Double(index) * 0.01, lng: 11.0))
        }
        await store.awaitPendingLookups()

        #expect(fake.requestCount == 3)
        #expect(fake.batches.map(\.count).sorted() == [5, 10, 10])
        #expect(fake.batches.allSatisfy { $0.count <= 10 })

        let asked = Set(fake.batches.flatMap { $0 }.map { store.key(for: $0) })
        #expect(asked.count == 25)
    }

    /// Every name in a split batch still lands, not just the first request's.
    @Test func namesFromEverySplitBatchAreKept() async {
        let fake = FakeGeocoder()
        for index in 0 ..< 25 {
            fake.names[String(format: "%.4f,%.4f", 48.0 + Double(index) * 0.01, 11.0)] = "Place \(index)"
        }
        let store = store(fake, maxPointsPerRequest: 10)

        for index in 0 ..< 25 {
            _ = store.name(for: LatLng(lat: 48.0 + Double(index) * 0.01, lng: 11.0))
        }
        await store.awaitPendingLookups()

        for index in 0 ..< 25 {
            #expect(store.name(for: LatLng(lat: 48.0 + Double(index) * 0.01, lng: 11.0)) == "Place \(index)")
        }
    }

    /// The device language rides along, so a German phone gets "München" and an English one
    /// "Munich" out of the same server cache.
    @Test func theRequestCarriesThePreferredLanguage() async {
        let fake = FakeGeocoder()
        let store = store(fake)

        _ = store.name(for: munich())
        await store.awaitPendingLookups()

        #expect(fake.languages.first == Locale.preferredLanguages.first)
    }

    // MARK: - When the endpoint says no

    /// A failure leaves the coordinates standing rather than blanking the heading, and stops the
    /// store asking for a while instead of retrying on every scroll.
    @Test func afailureStopsFurtherRequestsForTheBackoffWindow() async {
        let fake = FakeGeocoder()
        fake.failure = Offline()
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = store(fake, now: { clock })

        _ = store.name(for: munich())
        await store.awaitPendingLookups()
        #expect(fake.requestCount == 1)
        #expect(store.label(for: munich()) == formatCoordinates(munich()))

        // Different coordinates, still inside the window: nothing goes out.
        fake.failure = nil
        clock = clock.addingTimeInterval(30)
        for index in 0 ..< 5 {
            _ = store.name(for: LatLng(lat: 50.0 + Double(index) * 0.01, lng: 11.0))
        }
        await store.awaitPendingLookups()

        #expect(fake.requestCount == 1, "the back-off window should have swallowed these")
    }

    /// Once the window has passed the store starts asking again.
    @Test func requestsResumeAfterTheBackoffWindowPasses() async {
        let fake = FakeGeocoder()
        fake.failure = Offline()
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = store(fake, now: { clock })

        _ = store.name(for: munich())
        await store.awaitPendingLookups()

        fake.failure = nil
        fake.names["50.0000,11.0000"] = "Somewhere"
        clock = clock.addingTimeInterval(61)

        _ = store.name(for: LatLng(lat: 50.0, lng: 11.0))
        await store.awaitPendingLookups()

        #expect(fake.requestCount == 2)
        #expect(store.name(for: LatLng(lat: 50.0, lng: 11.0)) == "Somewhere")
    }

    /// Documents a deliberate trade-off rather than endorsing it: coordinates are marked as
    /// asked *before* the request goes out, so a coordinate caught by a failing request is never
    /// retried for the life of the process — not even once the back-off window has passed. That
    /// is what stops a scroll hammering a failing endpoint. If it ever needs to change, the fix
    /// is to un-ask the batch on failure, and this test should be inverted.
    @Test func acoordinateCaughtByAFailureIsNeverRetried() async {
        let fake = FakeGeocoder()
        fake.failure = Offline()
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = store(fake, now: { clock })

        _ = store.name(for: munich())
        await store.awaitPendingLookups()

        fake.failure = nil
        fake.names["48.1372,11.5755"] = "Munich"
        clock = clock.addingTimeInterval(600)

        _ = store.name(for: munich())
        await store.awaitPendingLookups()

        #expect(fake.requestCount == 1)
        #expect(store.name(for: munich()) == nil)
    }

    /// The store answers about the coordinate it was asked about, not about the one the server
    /// happened to echo back — a server rounding differently must not name the wrong place.
    @Test func namesAreFiledUnderTheServersOwnCoordinates() async {
        let store = RegionNameStore(
            maxPointsPerRequest: 60,
            batchDelay: .zero,
            now: Date.init,
            geocode: { _, _ in
                .success([ReverseGeocodedPlace(lat: 48.13724, lng: 11.57554, name: "Munich")])
            },
        )

        _ = store.name(for: munich())
        await store.awaitPendingLookups()

        // 48.13724 snaps to the same key as 48.1372, so the name still lands on the heading.
        #expect(store.name(for: munich()) == "Munich")
    }

    /// Asking for a name is what queues the lookup, so a heading only has to draw itself to get
    /// named — but an answer that never arrives must not leave the store thinking one is due.
    @Test func anEmptyBatchIsNeverSent() async {
        let fake = FakeGeocoder()
        let store = store(fake)

        await store.awaitPendingLookups()

        #expect(fake.requestCount == 0)
    }
}
