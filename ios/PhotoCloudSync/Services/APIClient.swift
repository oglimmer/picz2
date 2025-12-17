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

    func createMultipartBody(
        fileURL: URL,
        filename: String,
        mimeType: String,
        boundary: String,
        contentId: String? = nil,
    ) throws -> Data {
        var body = Data()

        // Add contentId if provided (e.g., iOS PHAsset.localIdentifier for duplicate detection)
        if let contentId {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"contentId\"\r\n\r\n")
            body.append(contentId)
            body.append("\r\n")
        }

        // Add file data (no albumId needed - server uses user's target album)
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")

        let fileData = try Data(contentsOf: fileURL)
        body.append(fileData)
        body.append("\r\n")

        // End boundary
        body.append("--\(boundary)--\r\n")

        return body
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

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let data else {
                let error = NSError(
                    domain: "APIClient",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No data received"],
                )
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NSError(
                    domain: "APIClient",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response"],
                )
                completion(.failure(error))
                return
            }

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                let error = NSError(
                    domain: "APIClient",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"],
                )
                completion(.failure(error))
                return
            }

            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(AlbumsResponse.self, from: data)
                completion(.success(response.albums))
            } catch {
                completion(.failure(error))
            }
        }

        task.resume()
    }

    func fetchUploadedChecksums(days: Int, completion: @escaping (Result<[String], Error>) -> Void) {
        let syncURL = baseURL.appendingPathComponent("api/sync/uploaded-checksums")
        var urlComponents = URLComponents(url: syncURL, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "days", value: String(days))]

        guard let url = urlComponents.url else {
            let error = NSError(
                domain: "APIClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid URL"],
            )
            completion(.failure(error))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addBasicAuth(to: &request)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let data else {
                let error = NSError(
                    domain: "APIClient",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No data received"],
                )
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NSError(
                    domain: "APIClient",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response"],
                )
                completion(.failure(error))
                return
            }

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                let error = NSError(
                    domain: "APIClient",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"],
                )
                completion(.failure(error))
                return
            }

            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(SyncChecksumsResponse.self, from: data)
                completion(.success(response.checksums))
            } catch {
                completion(.failure(error))
            }
        }

        task.resume()
    }

    func getTargetAlbum(completion: @escaping (Result<Int?, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/settings/target-album"))
        request.httpMethod = "GET"
        addBasicAuth(to: &request)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let data else {
                let error = NSError(
                    domain: "APIClient",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No data received"],
                )
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NSError(
                    domain: "APIClient",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response"],
                )
                completion(.failure(error))
                return
            }

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                let error = NSError(
                    domain: "APIClient",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"],
                )
                completion(.failure(error))
                return
            }

            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(TargetAlbumResponse.self, from: data)
                completion(.success(response.albumId))
            } catch {
                completion(.failure(error))
            }
        }

        task.resume()
    }

    func setTargetAlbum(albumId: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/settings/target-album"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addBasicAuth(to: &request)

        let body = ["albumId": albumId]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NSError(
                    domain: "APIClient",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response"],
                )
                completion(.failure(error))
                return
            }

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                let error = NSError(
                    domain: "APIClient",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"],
                )
                completion(.failure(error))
                return
            }

            completion(.success(()))
        }

        task.resume()
    }

    func clearTargetAlbum(completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/settings/target-album"))
        request.httpMethod = "DELETE"
        addBasicAuth(to: &request)

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NSError(
                    domain: "APIClient",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response"],
                )
                completion(.failure(error))
                return
            }

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                let error = NSError(
                    domain: "APIClient",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"],
                )
                completion(.failure(error))
                return
            }

            completion(.success(()))
        }

        task.resume()
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
