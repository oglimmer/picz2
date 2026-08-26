import Foundation

@testable import Zyncloud

/// One request the client actually put on the wire.
struct RecordedRequest {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data

    var path: String { url.path }

    /// The path exactly as it went out, percent-encoding intact. `URL.path` decodes it, which
    /// hides precisely the bug the tag-name tests are looking for.
    var encodedPath: String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
    }

    /// Query items as a dictionary. Repeated names keep the last value, which is enough for
    /// every endpoint here.
    var query: [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } }) { _, last in last }
    }

    var json: [String: Any] {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    }

    var bodyText: String { String(decoding: body, as: UTF8.self) }
}

/// Intercepts `URLSession.shared` so the endpoint builders can be checked without a server.
///
/// `APIClient` reaches straight for `URLSession.shared`, so there is no session to inject. A
/// registered `URLProtocol` is the one seam that works on the shared session, and it has the
/// advantage of testing the real request the real code built — URL, method, headers and body —
/// rather than a rehearsal of it.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status: Int
        var body: Data
    }

    private static let lock = NSLock()
    /// `nonisolated(unsafe)`: every read and write of this pair is between a ``lock`` and its
    /// matching unlock, which is exactly the guarantee the compiler is asking for and cannot
    /// verify for itself.
    nonisolated(unsafe) private static var handler: (@Sendable (RecordedRequest) -> Stub)?
    nonisolated(unsafe) private static var recorded: [RecordedRequest] = []

    static func begin(_ handler: @escaping @Sendable (RecordedRequest) -> Stub) {
        lock.lock()
        self.handler = handler
        recorded = []
        lock.unlock()
        URLProtocol.registerClass(StubURLProtocol.self)
    }

    static func end() -> [RecordedRequest] {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        lock.lock()
        defer { lock.unlock() }
        handler = nil
        let requests = recorded
        recorded = []
        return requests
    }

    private static var isArmed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return handler != nil
    }

    private static func serve(_ request: RecordedRequest) -> Stub {
        lock.lock()
        let handler = self.handler
        recorded.append(request)
        lock.unlock()
        return handler?(request) ?? Stub(status: 200, body: Data("{}".utf8))
    }

    /// `URLSession` turns a set `httpBody` into a stream by the time a protocol sees it, so both
    /// shapes have to be read or every body assertion silently passes on empty data.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let capacity = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: capacity)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    // MARK: - URLProtocol

    override class func canInit(with _: URLRequest) -> Bool { isArmed }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let recorded = RecordedRequest(
            url: url,
            method: request.httpMethod ?? "GET",
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.body(of: request),
        )
        let stub = Self.serve(recorded)

        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"],
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - One capture at a time, across every suite

/// Lets exactly one capture hold the stub at a time.
///
/// ``StubURLProtocol`` registers itself process-wide, so two captures running at once overwrite
/// each other's handler and record each other's requests. `@Suite(.serialized)` does not prevent
/// that: it orders tests *within* one suite, and Swift Testing runs separate suites in parallel —
/// three suites use this stub. The symptom was a test failing perhaps one run in five, always a
/// different one, always passing when run alone.
///
/// An `actor` on its own would not be enough either. Actors are reentrant, so a second capture
/// would slip in the moment the first suspended on `await work()` — which is exactly where a
/// capture spends all of its time. Hence an explicit gate with a queue of waiters.
actor StubGate {
    static let shared = StubGate()

    private var isHeld = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Hands the stub straight to the next waiter rather than clearing the flag, so a queue of
    /// waiters cannot let a newcomer jump in between two of them.
    func release() {
        if waiting.isEmpty {
            isHeld = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}

// MARK: - The shape tests read this way round

enum StubServer {
    /// Runs `work` with every `URLSession.shared` request answered by the stub, and hands back
    /// the requests it made.
    ///
    /// Suites that use this must be `.serialized`: the interception is process-wide.
    static func capture(
        status: Int = 200,
        json: String = "{\"success\":true}",
        _ work: () async -> Void,
    ) async -> [RecordedRequest] {
        await StubGate.shared.acquire()
        URLCache.shared.removeAllCachedResponses()
        StubURLProtocol.begin { _ in
            StubURLProtocol.Stub(status: status, body: Data(json.utf8))
        }
        await work()
        let requests = StubURLProtocol.end()
        await StubGate.shared.release()
        return requests
    }

    /// The same, for a body that is not JSON — an image, say. Goes through the same gate.
    ///
    /// `isolation: #isolation` so the caller's actor comes along: the image tests are a
    /// `@MainActor` suite, and without it their `work` closure would have to cross out of the
    /// main actor to get here, which the compiler refuses.
    static func serving(
        status: Int,
        body: Data,
        isolation: isolated (any Actor)? = #isolation,
        _ work: () async -> Void,
    ) async {
        await StubGate.shared.acquire()
        URLCache.shared.removeAllCachedResponses()
        StubURLProtocol.begin { _ in StubURLProtocol.Stub(status: status, body: body) }
        await work()
        _ = StubURLProtocol.end()
        await StubGate.shared.release()
    }

    /// The single request `work` made. Fails the calling test if it made none.
    static func captureOne(
        status: Int = 200,
        json: String = "{\"success\":true}",
        _ work: () async -> Void,
    ) async -> RecordedRequest? {
        await capture(status: status, json: json, work).first
    }
}

// MARK: - Bridging the completion-handler API into a test

extension APIClient {
    /// The credentials the shape tests sign with, so the `Authorization` header has something
    /// predictable in it.
    static var stubbed: APIClient {
        APIClient(username: "user@example.test", password: "hunter2")
    }

    /// `Basic` header value for ``stubbed``.
    static var stubbedAuthHeader: String {
        "Basic " + Data("user@example.test:hunter2".utf8).base64EncodedString()
    }
}

/// Turns one completion-handler call into something a test can `await`.
func awaiting<T: Sendable>(_ call: (@escaping @Sendable (Result<T, Error>) -> Void) -> Void) async -> Result<T, Error> {
    await withCheckedContinuation { continuation in
        call { continuation.resume(returning: $0) }
    }
}

/// The same, for the endpoints that fold failure into their answer instead of returning a
/// `Result` — `fetchRecordingAudioStatus` is the one that does.
func awaitingValue<T: Sendable>(_ call: (@escaping @Sendable (T) -> Void) -> Void) async -> T {
    await withCheckedContinuation { continuation in
        call { continuation.resume(returning: $0) }
    }
}
