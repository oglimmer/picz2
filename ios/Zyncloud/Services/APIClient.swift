import Foundation
import Photos

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
            print("APIClient: WARNING - Cannot add authentication headers: credentials are nil")
            return
        }
        let credentials = "\(username):\(password)"
        if let data = credentials.data(using: .utf8) {
            let base64Credentials = data.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
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
                            contentId: String? = nil) throws
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

    func fetchAlbums(completion: @escaping (Result<[Album], Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/albums"))
        request.httpMethod = "GET"
        addBasicAuth(to: &request)

        performRequest(request, expecting: AlbumsResponse.self) { result in
            completion(result.map(\.albums))
        }
    }

    func fetchUploadedChecksums(days: Int, completion: @escaping (Result<[String], Error>) -> Void) {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/sync/uploaded-checksums"),
            resolvingAgainstBaseURL: false,
        )
        components?.queryItems = [URLQueryItem(name: "days", value: String(days))]
        guard let url = components?.url else {
            completion(.failure(AppError.api(message: "Invalid URL", statusCode: nil)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addBasicAuth(to: &request)

        performRequest(request, expecting: SyncChecksumsResponse.self) { result in
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
    func fetchUploadedContentIds(days: Int, completion: @escaping (Result<[String], Error>) -> Void) {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/sync/uploaded-content-ids"),
            resolvingAgainstBaseURL: false,
        )
        components?.queryItems = [URLQueryItem(name: "days", value: String(days))]
        guard let url = components?.url else {
            completion(.failure(AppError.api(message: "Invalid URL", statusCode: nil)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addBasicAuth(to: &request)

        performRequest(request, expecting: SyncContentIdsResponse.self) { result in
            completion(result.map(\.contentIds))
        }
    }

    /// Mints a scoped upload token (§5.9).
    ///
    /// Authenticated like any other call — the point is not to skip logging in, it is to keep the
    /// account password out of `Upload-Metadata`, which tusd persists to storage for the life of
    /// an upload. See ``UploadTokenStore``.
    func fetchUploadToken(completion: @escaping (Result<UploadTokenResponse, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/upload-tokens"))
        request.httpMethod = "POST"
        addBasicAuth(to: &request)

        performRequest(request, expecting: UploadTokenResponse.self, completion: completion)
    }

    func getTargetAlbum(completion: @escaping (Result<Int?, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/settings/target-album"))
        request.httpMethod = "GET"
        addBasicAuth(to: &request)

        performRequest(request, expecting: TargetAlbumResponse.self) { result in
            completion(result.map(\.albumId))
        }
    }

    func setTargetAlbum(albumId: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/settings/target-album"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addBasicAuth(to: &request)

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["albumId": albumId])
        } catch {
            completion(.failure(error))
            return
        }

        performRequestIgnoringBody(request, completion: completion)
    }

    func clearTargetAlbum(completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/settings/target-album"))
        request.httpMethod = "DELETE"
        addBasicAuth(to: &request)

        performRequestIgnoringBody(request, completion: completion)
    }
}

struct TargetAlbumResponse: Codable {
    let success: Bool
    let albumId: Int?
}

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
