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

    private func performRequest<T: Decodable>(_ request: URLRequest, expecting _: T.Type, completion: @escaping (Result<T, Error>) -> Void) {
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
            if let error {
                print("❌ Network Error: \(error)")
                completion(.failure(AppError.network(error)))
                return
            }

            guard let data else {
                print("❌ No data received")
                completion(.failure(AppError.api(message: "No data received", statusCode: nil)))
                return
            }

            #if DEBUG
                print("📦 Received \(data.count) bytes")
            #endif

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid HTTP response")
                completion(.failure(AppError.api(message: "Invalid response", statusCode: nil)))
                return
            }

            #if DEBUG
                print("📡 HTTP Status: \(httpResponse.statusCode)")
            #endif

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                // Try to parse error message from response
                if let errorMessage = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    completion(.failure(AppError.api(message: errorMessage.message, statusCode: httpResponse.statusCode)))
                } else {
                    completion(.failure(AppError.api(message: "HTTP \(httpResponse.statusCode)", statusCode: httpResponse.statusCode)))
                }
                return
            }

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
                completion(.failure(AppError.api(message: "Failed to decode response: \(error.localizedDescription)", statusCode: httpResponse.statusCode)))
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
