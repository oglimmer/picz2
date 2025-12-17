import Foundation

class UploadService {
    static let shared = UploadService()

    // Configuration - Points to configured server
    private var apiEndpoint = AppConfiguration.uploadEndpoint
    private var email: String?
    private var password: String?

    private init() {}

    /// Configure the API endpoint for uploads
    func configure(apiEndpoint: String) {
        self.apiEndpoint = apiEndpoint
    }

    /// Get the API base URL
    func getApiBaseUrl() -> String {
        apiEndpoint.replacingOccurrences(of: "/upload", with: "")
    }

    /// Set Basic Auth credentials
    func setCredentials(email: String, password: String) {
        self.email = email
        self.password = password
    }

    /// Clear credentials
    func clearCredentials() {
        email = nil
        password = nil
    }

    /// Return the Authorization header value if credentials are present
    func getAuthorizationHeader() -> String? {
        guard let email, let password else { return nil }
        let creds = "\(email):\(password)"
        guard let data = creds.data(using: .utf8) else { return nil }
        let token = data.base64EncodedString()
        return "Basic \(token)"
    }

    /// Verify credentials via /auth/check
    func checkAuth(completion: @escaping (Result<String, Error>) -> Void) {
        let urlString = getApiBaseUrl() + "/auth/check"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "UploadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid auth URL"])))
            return
        }
        var request = URLRequest(url: url)
        if let auth = getAuthorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "UploadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])))
                return
            }
            guard 200 ... 299 ~= http.statusCode, let data else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(.failure(NSError(domain: "UploadService", code: code, userInfo: [NSLocalizedDescriptionKey: "Auth failed"])))
                return
            }
            // Parse email (optional)
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let email = obj["email"] as? String {
                completion(.success(email))
            } else {
                completion(.success(""))
            }
        }.resume()
    }

    /// Upload media items to the configured REST API
    func upload(
        mediaItems: [MediaItem],
        albumId: Int? = nil,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Int, Error>) -> Void,
    ) {
        performActualUpload(mediaItems: mediaItems, albumId: albumId, progress: progress, completion: completion)
    }

    /// Upload files to the API sequentially (one at a time)
    private func performActualUpload(
        mediaItems: [MediaItem],
        albumId: Int?,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Int, Error>) -> Void,
    ) {
        var uploadedCount = 0
        var failedError: Error?
        let totalCount = mediaItems.count

        // Upload files sequentially using recursion
        func uploadNext(index: Int) {
            guard index < mediaItems.count else {
                // All uploads complete
                DispatchQueue.main.async {
                    if let error = failedError {
                        completion(.failure(error))
                    } else {
                        completion(.success(uploadedCount))
                    }
                }
                return
            }

            let item = mediaItems[index]
            uploadFile(item: item, albumId: albumId) { result in
                switch result {
                case .success:
                    uploadedCount += 1
                    let currentProgress = Double(uploadedCount) / Double(totalCount)
                    DispatchQueue.main.async {
                        progress(currentProgress)
                    }
                case let .failure(error):
                    if failedError == nil {
                        failedError = error
                    }
                }

                // Upload next file
                uploadNext(index: index + 1)
            }
        }

        // Start with first file
        uploadNext(index: 0)
    }

    private func uploadFile(
        item: MediaItem,
        albumId: Int?,
        completion: @escaping (Result<Void, Error>) -> Void,
    ) {
        var urlString = apiEndpoint
        if let albumId {
            urlString += "?albumId=\(albumId)"
        }

        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "UploadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API endpoint"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        if let auth = getAuthorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        // Create multipart form data (streamed to file)
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Compose multipart to a temp file to avoid loading entire payload in memory
        let multipartURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("multipart")

        do {
            try writeMultipart(to: multipartURL, item: item, boundary: boundary)
        } catch {
            completion(.failure(error))
            return
        }

        // Note: size is unknown here without reading; omit from log or compute from file attributes
        print("📤 Uploading: \(item.filename)")

        let task = URLSession.shared.uploadTask(with: request, fromFile: multipartURL) { data, response, error in
            if let error {
                print("❌ Upload failed: \(item.filename) - \(error.localizedDescription)")
                // Cleanup temp file
                try? FileManager.default.removeItem(at: multipartURL)
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if 200 ... 299 ~= httpResponse.statusCode {
                    print("✅ Upload successful: \(item.filename)")
                    try? FileManager.default.removeItem(at: multipartURL)
                    completion(.success(()))
                } else {
                    let errorMessage = if let data, let responseString = String(data: data, encoding: .utf8) {
                        "Server returned \(httpResponse.statusCode): \(responseString)"
                    } else {
                        "Server returned status code \(httpResponse.statusCode)"
                    }
                    print("❌ Upload failed: \(item.filename) - \(errorMessage)")
                    let error = NSError(
                        domain: "UploadService",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: errorMessage],
                    )
                    try? FileManager.default.removeItem(at: multipartURL)
                    completion(.failure(error))
                }
            }
        }

        task.resume()
    }

    private func writeMultipart(to destinationURL: URL, item: MediaItem, boundary: String) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        fileManager.createFile(atPath: destinationURL.path, contents: nil, attributes: nil)
        let out = try FileHandle(forWritingTo: destinationURL)
        defer { try? out.close() }

        // File header
        out.write(Data("--\(boundary)\r\n".utf8))
        out.write(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(item.filename)\"\r\n".utf8))

        let contentType = if item.type == .image {
            "image/\(item.url.pathExtension.lowercased())"
        } else {
            "video/\(item.url.pathExtension.lowercased())"
        }
        out.write(Data("Content-Type: \(contentType)\r\n\r\n".utf8))

        // Stream file contents
        let inHandle = try FileHandle(forReadingFrom: item.url)
        defer { try? inHandle.close() }
        let chunkSize = 64 * 1024
        while true {
            let data = try inHandle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            out.write(data)
        }
        out.write(Data("\r\n".utf8))
        out.write(Data("--\(boundary)--\r\n".utf8))
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MediaItem struct for type safety
struct MediaItem {
    let url: URL
    let type: MediaType
    let filename: String

    enum MediaType {
        case image
        case video
    }
}
