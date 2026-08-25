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
    private static var handler: ((RecordedRequest) -> Stub)?
    private static var recorded: [RecordedRequest] = []

    static func begin(_ handler: @escaping (RecordedRequest) -> Stub) {
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
        URLCache.shared.removeAllCachedResponses()
        StubURLProtocol.begin { _ in
            StubURLProtocol.Stub(status: status, body: Data(json.utf8))
        }
        await work()
        return StubURLProtocol.end()
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
func awaiting<T>(_ call: (@escaping (Result<T, Error>) -> Void) -> Void) async -> Result<T, Error> {
    await withCheckedContinuation { continuation in
        call { continuation.resume(returning: $0) }
    }
}

/// The same, for the endpoints that fold failure into their answer instead of returning a
/// `Result` — `fetchRecordingAudioStatus` is the one that does.
func awaitingValue<T>(_ call: (@escaping (T) -> Void) -> Void) async -> T {
    await withCheckedContinuation { continuation in
        call { continuation.resume(returning: $0) }
    }
}
