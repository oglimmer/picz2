import Foundation
import Photos
import os

struct APIClient {
    var baseURL = AppConfiguration.apiBaseURL
    var username: String?
    var password: String?

    init(username: String? = nil, password: String? = nil) {
        self.username = username
        self.password = password
    }

    func addBasicAuth(to request: inout URLRequest) {
        guard let username, let password else {
            AppLog.api.warning("Cannot add authentication headers: credentials are nil")
            return
        }
        let credentials = "\(username):\(password)"
        if let data = credentials.data(using: .utf8) {
            let base64Credentials = data.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        }
    }

    // MARK: - Request building

    /// The verbs this client uses. An enum rather than the bare strings the endpoints used to
    /// pass around, so a typo is a compile error instead of a 405 at runtime.
    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    /// Builds an authenticated request for `path` under ``baseURL``.
    ///
    /// Every endpoint used to open-code this: append the path, sometimes build `URLComponents`
    /// for the query, sometimes force-unwrap the result, then remember to call
    /// ``addBasicAuth(to:)``. Two of those force-unwraps would have crashed the app on a
    /// malformed base URL, and forgetting the auth call fails as a 401 that looks like a
    /// wrong password.
    ///
    /// - Throws: ``AppError/api(message:statusCode:)`` when path and query cannot form a URL.
    func makeRequest(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        authenticated: Bool = true,
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false,
        ) else {
            throw AppError.api(message: "Could not build a web address for \(path)", statusCode: nil)
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw AppError.api(message: "Could not build a web address for \(path)", statusCode: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        if authenticated {
            addBasicAuth(to: &request)
        }
        return request
    }

    /// The same, carrying a JSON body.
    ///
    /// Takes an `Encodable` rather than the `[String: Any]` the endpoints used to hand to
    /// `JSONSerialization`. That dictionary could hold anything, so a wrong-typed value threw at
    /// runtime and a misspelled key reached the server as valid JSON the server did not
    /// understand. A struct makes both a compile error, and sets the content type for free.
    func makeRequest(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: some Encodable,
        authenticated: Bool = true,
    ) throws -> URLRequest {
        var request = try makeRequest(method, path, query: query, authenticated: authenticated)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    // MARK: - Build and send

    /// Build a request and send it, decoding the reply as `T`.
    ///
    /// This is what an endpoint should call. Building can throw and endpoints are
    /// completion-based, so without it every one of them carries the same
    /// `do { … } catch { completion(.failure(error)); return }` — thirty copies of a block whose
    /// only job is to move an error four lines sideways.
    func send<T: Decodable & Sendable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        expecting: T.Type,
        authenticated: Bool = true,
        completion: @escaping @Sendable (Result<T, Error>) -> Void,
    ) {
        do {
            let request = try makeRequest(method, path, query: query, authenticated: authenticated)
            performRequest(request, expecting: expecting, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    /// The same, with a JSON body.
    func send<T: Decodable & Sendable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: some Encodable,
        expecting: T.Type,
        authenticated: Bool = true,
        completion: @escaping @Sendable (Result<T, Error>) -> Void,
    ) {
        do {
            let request = try makeRequest(method, path, query: query, body: body, authenticated: authenticated)
            performRequest(request, expecting: expecting, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    /// For endpoints whose reply is only a status code.
    func send(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        authenticated: Bool = true,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void,
    ) {
        do {
            let request = try makeRequest(method, path, query: query, authenticated: authenticated)
            performRequestIgnoringBody(request, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    /// A JSON body in, a status code out.
    func send(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: some Encodable,
        authenticated: Bool = true,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void,
    ) {
        do {
            let request = try makeRequest(method, path, query: query, body: body, authenticated: authenticated)
            performRequestIgnoringBody(request, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    func makeUploadRequest(for _: PHAsset, filename _: String, mimeType _: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/upload"))
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        addBasicAuth(to: &request)

        return request
    }

    // Stream a multipart body directly to a file to avoid holding large files in memory
    func writeMultipartBody(to destinationURL: URL,
                            fileURL: URL,
                            filename: String,
                            mimeType: String,
                            boundary: String,
                            contentId: String? = nil,
                            // Names the destination album. Left nil the server files the asset
                            // under the account's target album, which is what background sync
                            // wants; the album screen's upload button passes what it is showing.
                            albumId: Int? = nil) throws
    {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        fileManager.createFile(atPath: destinationURL.path, contents: nil, attributes: nil)
        let out = try FileHandle(forWritingTo: destinationURL)
        defer { try? out.close() }

        // Write contentId part if present
        if let contentId {
            out.write(Data("--\(boundary)\r\n".utf8))
            out.write(Data("Content-Disposition: form-data; name=\"contentId\"\r\n\r\n".utf8))
            out.write(Data(contentId.utf8))
            out.write(Data("\r\n".utf8))
        }

        // Write albumId part if present
        if let albumId {
            out.write(Data("--\(boundary)\r\n".utf8))
            out.write(Data("Content-Disposition: form-data; name=\"albumId\"\r\n\r\n".utf8))
            out.write(Data(String(albumId).utf8))
            out.write(Data("\r\n".utf8))
        }

        // Write file header
        out.write(Data("--\(boundary)\r\n".utf8))
        out.write(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        out.write(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))

        // Stream file contents
        let chunkSize = 64 * 1024
        let inHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? inHandle.close() }
        while true {
            let data = try inHandle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            out.write(data)
        }
        out.write(Data("\r\n".utf8))

        // Closing boundary
        out.write(Data("--\(boundary)--\r\n".utf8))
    }

    func fetchAlbums(completion: @escaping @Sendable (Result<[Album], Error>) -> Void) {
        send(.get, "api/albums", expecting: AlbumsResponse.self) { result in
            completion(result.map(\.albums))
        }
    }

    func fetchUploadedChecksums(days: Int, completion: @escaping @Sendable (Result<[String], Error>) -> Void) {
        send(.get, "api/sync/uploaded-checksums",
             query: [URLQueryItem(name: "days", value: String(days))],
             expecting: SyncChecksumsResponse.self)
        { result in
            completion(result.map(\.checksums))
        }
    }

    /// ContentIds the server already holds for this user.
    ///
    /// Companion to ``fetchUploadedChecksums(days:completion:)``. That one can only ever mark
    /// assets this install has already seen, because the client matches the returned checksums
    /// against a local map that a fresh install has not built yet — so it was inert exactly
    /// where it was needed (§5.8). ContentIds are `PHAsset.localIdentifier` values, which belong
    /// to the photo library and still match after a delete-and-reinstall.
    func fetchUploadedContentIds(days: Int, completion: @escaping @Sendable (Result<[String], Error>) -> Void) {
        send(.get, "api/sync/uploaded-content-ids",
             query: [URLQueryItem(name: "days", value: String(days))],
             expecting: SyncContentIdsResponse.self)
        { result in
            completion(result.map(\.contentIds))
        }
    }

    /// Mints a scoped upload token (§5.9).
    ///
    /// Authenticated like any other call — the point is not to skip logging in, it is to keep the
    /// account password out of `Upload-Metadata`, which tusd persists to storage for the life of
    /// an upload. See ``UploadTokenStore``.
    func fetchUploadToken(completion: @escaping @Sendable (Result<UploadTokenResponse, Error>) -> Void) {
        send(.post, "api/upload-tokens", expecting: UploadTokenResponse.self, completion: completion)
    }

    func getTargetAlbum(completion: @escaping @Sendable (Result<Int?, Error>) -> Void) {
        send(.get, "api/settings/target-album", expecting: TargetAlbumResponse.self) { result in
            completion(result.map(\.albumId))
        }
    }

    func setTargetAlbum(albumId: Int, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(.put, "api/settings/target-album",
             body: TargetAlbumBody(albumId: albumId), completion: completion)
    }

    func clearTargetAlbum(completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(.delete, "api/settings/target-album", completion: completion)
    }
}

struct TargetAlbumResponse: Codable {
    let success: Bool
    let albumId: Int?
}

/// The body of `PUT /api/settings/target-album`.
struct TargetAlbumBody: Encodable {
    let albumId: Int
}

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
