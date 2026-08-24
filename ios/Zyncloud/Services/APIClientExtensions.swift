import Foundation

// MARK: - TUS asset-id lookup (Phase 5 follow-up)

extension APIClient {
    /// Resolve the server-side asset id for a freshly TUS-uploaded file. The TUS PATCH
    /// response carries only protocol headers, not the asset id, so iOS calls this with the
    /// client-side `contentId` (PHAsset.localIdentifier) to find the row that the post-finish
    /// hook just inserted.
    ///
    /// Returns 404 when the row hasn't appeared yet — most often that means the post-finish
    /// hook is still running (~200 ms race window). Callers retry briefly with backoff.
    func lookupAssetByContentId(
        albumId: Int,
        contentId: String,
        completion: @escaping (Result<Int, Error>) -> Void,
    ) {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/assets/by-content"),
            resolvingAgainstBaseURL: false,
        )!
        components.queryItems = [
            URLQueryItem(name: "albumId", value: String(albumId)),
            URLQueryItem(name: "contentId", value: contentId),
        ]
        var request = URLRequest(url: components.url!)
        addBasicAuth(to: &request)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "APIClient.lookupAssetByContentId", code: -1)))
                return
            }
            if http.statusCode == 404 {
                completion(.failure(NSError(
                    domain: "APIClient.lookupAssetByContentId",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "asset not found yet"],
                )))
                return
            }
            guard (200 ... 299).contains(http.statusCode), let data else {
                completion(.failure(NSError(
                    domain: "APIClient.lookupAssetByContentId",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"],
                )))
                return
            }
            do {
                let resp = try JSONDecoder().decode(AssetProcessingStatusResponse.self, from: data)
                completion(.success(resp.id))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

// MARK: - Server Capabilities (Phase 5)

extension APIClient {
    /// Fetch ingest-path capabilities. Unauthenticated; safe to call before login. The result
    /// is cached briefly by the caller (SyncCoordinator) — there's no point re-asking on every
    /// upload, the server flips this only at deploy boundaries.
    func fetchCapabilities(completion: @escaping (Result<Capabilities, Error>) -> Void) {
        let request = URLRequest(url: baseURL.appendingPathComponent("api/capabilities"))
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode), let data else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(.failure(NSError(domain: "APIClient.fetchCapabilities", code: code,
                                            userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])))
                return
            }
            do {
                let caps = try JSONDecoder().decode(Capabilities.self, from: data)
                completion(.success(caps))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

// MARK: - Album Management Extensions

extension APIClient {
    // MARK: - Create Album

    func createAlbum(name: String, description: String?, completion: @escaping (Result<Album, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/albums"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addBasicAuth(to: &request)

        let body: [String: Any] = [
            "name": name,
            "description": description ?? "",
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        performRequest(request, expecting: AlbumResponse.self) { result in
            completion(result.map(\.album))
        }
    }

    // MARK: - Update Album

    func updateAlbum(id: Int, name: String, description: String?, completion: @escaping (Result<Album, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/albums/\(id)"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addBasicAuth(to: &request)

        let body: [String: Any] = [
            "name": name,
            "description": description ?? "",
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        performRequest(request, expecting: AlbumResponse.self) { result in
            completion(result.map(\.album))
        }
    }

    // MARK: - Delete Album

    func deleteAlbum(id: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/albums/\(id)"))
        request.httpMethod = "DELETE"
        addBasicAuth(to: &request)

        performRequest(request, expecting: SuccessResponse.self) { result in
            switch result {
            case .success:
                completion(.success(()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Fetch Files in Album

    func fetchFiles(albumId: Int, tag: String? = nil, completion: @escaping (Result<FilesResponse, Error>) -> Void) {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/albums/\(albumId)/files"), resolvingAgainstBaseURL: false)

        // Add optional tag filter
        if let tag {
            components?.queryItems = [URLQueryItem(name: "tag", value: tag)]
        }

        guard let url = components?.url else {
            completion(.failure(AppError.api(message: "Invalid URL", statusCode: nil)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addBasicAuth(to: &request)

        performRequest(request, expecting: FilesResponse.self, completion: completion)
    }

    // Backwards compatibility - fetchPhotos now calls fetchFiles
    func fetchPhotos(albumId: Int, page _: Int = 1, limit _: Int = 50, completion: @escaping (Result<PhotosResponse, Error>) -> Void) {
        fetchFiles(albumId: albumId, tag: nil, completion: completion)
    }

    // MARK: - Asset Processing Status

    func getAssetStatus(id: Int, completion: @escaping (Result<AssetProcessingStatusResponse, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/assets/\(id)/status"))
        request.httpMethod = "GET"
        addBasicAuth(to: &request)
        performRequest(request, expecting: AssetProcessingStatusResponse.self, completion: completion)
    }

    // MARK: - Helper: Perform Request

    /// The error ladder every endpoint needs: transport failure, missing body, non-HTTP
    /// response, then a non-2xx status carrying the server's own message when it sent one.
    /// Returns the body on success.
    ///
    /// Extracted because `fetchAlbums`, `fetchUploadedChecksums`, `getTargetAlbum`,
    /// `setTargetAlbum` and `clearTargetAlbum` each re-implemented it by hand — roughly 200
    /// lines that could drift apart one fix at a time.
    /// Returns the body **and** the status code — the decode-failure path downstream reports the
    /// status alongside the decoding error, and dropping it would make that message less useful.
    static func validate(
        data: Data?, response: URLResponse?, error: Error?
    ) -> Result<(body: Data, statusCode: Int), Error> {
        if let error {
            print("❌ Network Error: \(error)")
            return .failure(AppError.network(error))
        }
        guard let data else {
            print("❌ No data received")
            return .failure(AppError.api(message: "No data received", statusCode: nil))
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response")
            return .failure(AppError.api(message: "Invalid response", statusCode: nil))
        }
        #if DEBUG
            print("📦 Received \(data.count) bytes — HTTP \(httpResponse.statusCode)")
        #endif
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let errorMessage = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                return .failure(AppError.api(message: errorMessage.message, statusCode: httpResponse.statusCode))
            }
            return .failure(AppError.api(message: "HTTP \(httpResponse.statusCode)", statusCode: httpResponse.statusCode))
        }
        return .success((data, httpResponse.statusCode))
    }


    /// For endpoints that answer with a status code and nothing worth decoding. Reuses the same
    /// error ladder — a 2xx is success, anything else is an ``AppError/api`` carrying the
    /// server's message when it sent one.
    func performRequestIgnoringBody(_ request: URLRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            switch APIClient.validate(data: data, response: response, error: error) {
            case .success:
                completion(.success(()))
            case let .failure(err):
                completion(.failure(err))
            }
        }
        task.resume()
    }


    /// Internal rather than private so the endpoints in `APIClient.swift` can share it —
    /// they each used to re-implement this error ladder by hand.
    func performRequest<T: Decodable>(_ request: URLRequest, expecting _: T.Type, completion: @escaping (Result<T, Error>) -> Void) {
        #if DEBUG
            // DEBUG: Print request details (redacting sensitive headers)
            var redactedHeaders = request.allHTTPHeaderFields ?? [:]
            if redactedHeaders["Authorization"] != nil {
                redactedHeaders["Authorization"] = "<redacted>"
            }
            print("🌐 API Request:")
            print("   URL: \(request.url?.absoluteString ?? "unknown")")
            print("   Method: \(request.httpMethod ?? "GET")")
            print("   Headers: \(redactedHeaders)")
        #endif

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let validated: (body: Data, statusCode: Int)
            switch APIClient.validate(data: data, response: response, error: error) {
            case let .failure(err):
                completion(.failure(err))
                return
            case let .success(ok):
                validated = ok
            }
            let data = validated.body
            let statusCode = validated.statusCode

            do {
                #if DEBUG
                    // DEBUG: Print raw JSON response
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("📥 API Response [\(request.url?.path ?? "unknown")]:")
                        print(jsonString)
                    }
                #endif

                let decoder = JSONDecoder()
                let decodedResponse = try decoder.decode(T.self, from: data)
                completion(.success(decodedResponse))
            } catch {
                #if DEBUG
                    // DEBUG: Print decoding error details
                    print("❌ Decoding Error for \(T.self):")
                    print("   Error: \(error)")
                    if let decodingError = error as? DecodingError {
                        switch decodingError {
                        case let .keyNotFound(key, context):
                            print("   Missing key: \(key.stringValue)")
                            print("   Context: \(context.debugDescription)")
                        case let .typeMismatch(type, context):
                            print("   Type mismatch: expected \(type)")
                            print("   Context: \(context.debugDescription)")
                        case let .valueNotFound(type, context):
                            print("   Value not found: \(type)")
                            print("   Context: \(context.debugDescription)")
                        case let .dataCorrupted(context):
                            print("   Data corrupted")
                            print("   Context: \(context.debugDescription)")
                        @unknown default:
                            print("   Unknown decoding error")
                        }
                    }
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("   Raw JSON: \(jsonString)")
                    }
                #endif
                completion(.failure(AppError.api(message: "Failed to decode response: \(error.localizedDescription)", statusCode: statusCode)))
            }
        }

        task.resume()
    }
}

// MARK: - Device Token Management Extensions

extension APIClient {
    func registerDeviceToken(body: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/device-tokens"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addBasicAuth(to: &request)

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

    func unregisterDeviceToken(token: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let urlString = baseURL.appendingPathComponent("api/device-tokens").absoluteString
        let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        guard let url = URL(string: "\(urlString)?deviceToken=\(encodedToken)") else {
            let error = NSError(
                domain: "APIClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid URL"],
            )
            completion(.failure(error))
            return
        }

        var request = URLRequest(url: url)
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

// MARK: - Authentication Endpoints

extension APIClient {
    /// Validate the credentials currently set on this client against `/api/auth/check`.
    /// Returns the server-side email and `emailVerified` flag.
    func checkAuth(completion: @escaping (Result<AuthCheckResponse, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/auth/check"))
        request.httpMethod = "GET"
        addBasicAuth(to: &request)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(AppError.network(error)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(AppError.api(message: "Invalid response", statusCode: nil)))
                return
            }
            guard (200 ... 299).contains(http.statusCode), let data else {
                completion(.failure(AppError.authentication("Invalid email or password")))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(AuthCheckResponse.self, from: data)
                if decoded.success {
                    completion(.success(decoded))
                } else {
                    completion(.failure(AppError.authentication("Invalid email or password")))
                }
            } catch {
                completion(.failure(AppError.api(message: "Failed to decode response: \(error.localizedDescription)", statusCode: http.statusCode)))
            }
        }.resume()
    }

    /// Create a new account. Unauthenticated POST to `/api/users`. On success the server
    /// has emailed a verification link; the user can't sign in until they click it.
    static func register(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: AppConfiguration.apiBaseURL.appendingPathComponent("api/users"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["email": email, "password": password]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(AppError.network(error)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(AppError.api(message: "Invalid response", statusCode: nil)))
                return
            }
            guard (200 ... 299).contains(http.statusCode) else {
                let message = data
                    .flatMap { try? JSONDecoder().decode(ErrorResponse.self, from: $0) }?
                    .message ?? "Failed to create account"
                completion(.failure(AppError.api(message: message, statusCode: http.statusCode)))
                return
            }
            completion(.success(()))
        }.resume()
    }

    /// Request a password-reset email. Unauthenticated POST to
    /// `/api/users/password-reset-request`. Server returns 200 even if the email is unknown
    /// (to avoid leaking account existence) — mirror that behavior in the UI.
    static func requestPasswordReset(email: String, completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: AppConfiguration.apiBaseURL.appendingPathComponent("api/users/password-reset-request"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["email": email]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(AppError.network(error)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(AppError.api(message: "Invalid response", statusCode: nil)))
                return
            }
            guard (200 ... 299).contains(http.statusCode) else {
                let message = data
                    .flatMap { try? JSONDecoder().decode(ErrorResponse.self, from: $0) }?
                    .message ?? "Failed to send reset link"
                completion(.failure(AppError.api(message: message, statusCode: http.statusCode)))
                return
            }
            completion(.success(()))
        }.resume()
    }
}

// MARK: - Response Models

struct AlbumResponse: Codable {
    let success: Bool
    let album: Album
}

struct SuccessResponse: Codable {
    let success: Bool
    let message: String?
}

struct ErrorResponse: Codable {
    let success: Bool
    let message: String
}

struct AuthCheckResponse: Codable {
    let success: Bool
    let email: String?
    let emailVerified: Bool
}

// MARK: - Reordering

/// The three sort actions the web gallery offers under its "Sort" menu. Kept as one enum so the
/// view can drive a menu from `allCases` and the view model only needs a single entry point.
enum AlbumSortAction: String, CaseIterable, Identifiable {
    case filename
    case exifDate

    var id: String {
        rawValue
    }

    /// Wording copied from the web gallery so both clients read the same.
    var title: String {
        switch self {
        case .filename: "Number in filename"
        case .exifDate: "Date the photo was taken"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .filename:
            "Reorder all files in this album by filename numbers? This will sort files based on numbers found in their filenames."
        case .exifDate:
            "Reorder all files in this album by EXIF date? This will sort files based on the date the photo was taken (from EXIF metadata). Files without EXIF dates will be sorted by upload date."
        }
    }

    /// Path segment of the server endpoint that performs this sort.
    fileprivate var endpointSuffix: String {
        switch self {
        case .filename: "reorder-by-filename"
        case .exifDate: "reorder-by-exif"
        }
    }
}

extension APIClient {
    /// Re-sorts every file in an album server-side and answers how many rows changed.
    /// Mirrors `reorderByFilename` / `reorderByExif` in the web app's `useFiles` composable.
    func reorderAlbum(albumId: Int, by action: AlbumSortAction, completion: @escaping (Result<Int, Error>) -> Void) {
        var request = URLRequest(
            url: baseURL.appendingPathComponent("api/albums/\(albumId)/\(action.endpointSuffix)"),
        )
        request.httpMethod = "POST"
        addBasicAuth(to: &request)

        performRequest(request, expecting: ReorderResponse.self) { result in
            completion(result.map(\.updatedCount))
        }
    }

    /// Persists a hand-made order. `fileIds` must be the album's files in the wanted order —
    /// the server writes each file's `displayOrder` from its index, same as the web app's
    /// "Arrange by hand" mode.
    func reorderFiles(fileIds: [Int], completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/files/reorder"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addBasicAuth(to: &request)

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["fileIds": fileIds])
        } catch {
            completion(.failure(error))
            return
        }

        performRequestIgnoringBody(request, completion: completion)
    }
}

// MARK: - Single-file actions

extension APIClient {
    /// Deletes one file. Irreversible — the server drops the stored objects as well as the row.
    func deleteFile(id: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/files/\(id)"))
        request.httpMethod = "DELETE"
        addBasicAuth(to: &request)

        performRequestIgnoringBody(request, completion: completion)
    }

    /// Queues a 90° left rotation. Answers 202 as soon as the job is enqueued — the worker pod
    /// does the work, so the caller has to poll ``getAssetStatus(id:completion:)`` before the
    /// new image is there to show. Rotating also swaps the asset's `publicToken`, which is why
    /// the file list has to be reloaded afterwards rather than just the image.
    func rotateImageLeft(id: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/files/\(id)/rotate"))
        request.httpMethod = "POST"
        addBasicAuth(to: &request)

        performRequestIgnoringBody(request, completion: completion)
    }
}

struct ReorderResponse: Codable {
    let success: Bool
    let message: String?
    let updatedCount: Int
}
