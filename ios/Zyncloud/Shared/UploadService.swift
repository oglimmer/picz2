import Foundation

class UploadService {
    static let shared = UploadService()

    private var email: String?
    private var password: String?

    /// Scoped upload token for the TUS metadata (§5.9), fetched once per share and kept only in
    /// memory. The extension's lifetime is one share sheet, so there is nothing to expire here —
    /// the point is simply that the account password no longer travels in `Upload-Metadata`,
    /// which tusd writes to a `.info` object in storage for the life of the upload.
    private var uploadToken: String?

    private init() {}

    /// Base URL for the JSON API surface (auth, albums). Distinct from the TUS upload
    /// endpoint, which lives under /files/ and is reached via ``AppConfiguration/tusEndpointURL``.
    func getApiBaseUrl() -> String {
        AppConfiguration.apiBaseURL.appendingPathComponent("api").absoluteString
    }

    func setCredentials(email: String, password: String) {
        self.email = email
        self.password = password
    }

    func clearCredentials() {
        email = nil
        password = nil
        uploadToken = nil
    }

    func getAuthorizationHeader() -> String? {
        guard let email, let password else { return nil }
        let creds = "\(email):\(password)"
        guard let data = creds.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
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
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let email = obj["email"] as? String {
                completion(.success(email))
            } else {
                completion(.success(""))
            }
        }.resume()
    }

    /// Upload media items via TUS, sequentially, reporting per-file progress.
    /// The legacy `auth` metadata value — the account's own `email:password`.
    private var legacyAuthValue: String? {
        guard let email, let password else { return nil }
        return "\(email):\(password)"
    }

    /// Mints a scoped upload token, if the server offers them.
    ///
    /// Failure is not an error: an older server has no such endpoint, and the upload proceeds on
    /// the legacy credential value instead.
    private func fetchUploadToken(completion: @escaping () -> Void) {
        guard let url = URL(string: getApiBaseUrl() + "/upload-tokens"),
              let authorization = getAuthorizationHeader()
        else {
            completion()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            defer { completion() }
            guard let self,
                  let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
                  let data,
                  let decoded = try? JSONDecoder().decode(ShareUploadTokenResponse.self, from: data)
            else { return }
            uploadToken = decoded.token
        }.resume()
    }

    func upload(
        mediaItems: [MediaItem],
        albumId: Int? = nil,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Int, Error>) -> Void,
    ) {
        // One token for the whole share, minted before the first byte moves.
        fetchUploadToken { [weak self] in
            self?.performUpload(mediaItems: mediaItems, albumId: albumId,
                               progress: progress, completion: completion)
        }
    }

    private func performUpload(
        mediaItems: [MediaItem],
        albumId: Int?,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        var uploadedCount = 0
        var failedError: Error?
        let totalCount = mediaItems.count

        func uploadNext(index: Int) {
            guard index < mediaItems.count else {
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
                    DispatchQueue.main.async { progress(currentProgress) }
                case let .failure(error):
                    if failedError == nil { failedError = error }
                }
                uploadNext(index: index + 1)
            }
        }

        uploadNext(index: 0)
    }

    private func uploadFile(
        item: MediaItem,
        albumId: Int?,
        completion: @escaping (Result<Void, Error>) -> Void,
    ) {
        // Auth via Upload-Metadata is required by the server (D26) — Authorization header is
        // sent too as belt-and-braces, but tusd does not forward arbitrary headers to hooks.
        guard email != nil, password != nil else {
            completion(.failure(NSError(domain: "UploadService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])))
            return
        }

        let fileSize: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: item.url.path)
            fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            completion(.failure(error))
            return
        }

        let tusURL = AppConfiguration.tusEndpointURL
        var request = URLRequest(url: tusURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(fileSize), forHTTPHeaderField: "Upload-Length")
        request.setValue(buildUploadMetadata(item: item, albumId: albumId), forHTTPHeaderField: "Upload-Metadata")
        if let auth = getAuthorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        print("📤 Creating TUS upload: \(item.filename) (\(fileSize) bytes)")
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            if let error {
                print("❌ TUS create failed: \(item.filename) - \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "UploadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])))
                return
            }
            switch http.statusCode {
            case 200, 201:
                guard let location = http.value(forHTTPHeaderField: "Location"),
                      let uploadURL = self.resolveLocation(location, against: tusURL)
                else {
                    completion(.failure(NSError(domain: "UploadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Location header"])))
                    return
                }
                self.patchUpload(item: item, uploadURL: uploadURL, completion: completion)
            case 401, 403:
                completion(.failure(NSError(domain: "UploadService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Authentication failed"])))
            case 429, 503:
                let retry = http.value(forHTTPHeaderField: "Retry-After") ?? "?"
                completion(.failure(NSError(domain: "UploadService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server busy (retry after \(retry)s)"])))
            default:
                let body = "POST /files/ returned \(http.statusCode)"
                completion(.failure(NSError(domain: "UploadService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])))
            }
        }.resume()
    }

    private func patchUpload(
        item: MediaItem,
        uploadURL: URL,
        completion: @escaping (Result<Void, Error>) -> Void,
    ) {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 600
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue("0", forHTTPHeaderField: "Upload-Offset")
        request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
        if let auth = getAuthorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        let task = URLSession.shared.uploadTask(with: request, fromFile: item.url) { _, response, error in
            if let error {
                print("❌ TUS PATCH failed: \(item.filename) - \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse {
                if 200 ... 299 ~= http.statusCode {
                    print("✅ Upload successful: \(item.filename)")
                    completion(.success(()))
                } else {
                    let msg = "PATCH returned \(http.statusCode)"
                    print("❌ TUS PATCH failed: \(item.filename) - \(msg)")
                    completion(.failure(NSError(domain: "UploadService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])))
                }
            } else {
                completion(.failure(NSError(domain: "UploadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])))
            }
        }
        task.resume()
    }

    /// Build the TUS Upload-Metadata header. Each value is base64-encoded per the spec.
    /// We omit ``contentId`` deliberately: a user re-sharing the same photo through the share
    /// sheet expects a new asset (matching the legacy multipart endpoint), not a 409 dedupe.
    private func buildUploadMetadata(item: MediaItem, albumId: Int?) -> String {
        var parts: [(String, String)] = [
            ("filename", item.filename),
            ("filetype", contentType(for: item)),
        ]
        if let albumId {
            parts.append(("albumId", String(albumId)))
        }
        // Prefer the scoped token; fall back to the account credentials only when the server
        // has no token endpoint (§5.9).
        if let auth = uploadToken ?? legacyAuthValue {
            parts.append(("auth", auth))
        }
        return parts
            .map { key, value in
                let b64 = Data(value.utf8).base64EncodedString()
                return "\(key) \(b64)"
            }
            .joined(separator: ",")
    }

    private func contentType(for item: MediaItem) -> String {
        let ext = item.url.pathExtension.lowercased()
        return item.type == .image ? "image/\(ext)" : "video/\(ext)"
    }

    private func resolveLocation(_ location: String, against base: URL) -> URL? {
        if let abs = URL(string: location), abs.scheme != nil { return abs }
        return URL(string: location, relativeTo: base)?.absoluteURL
    }
}

/// `POST /api/upload-tokens`. Only the token is read here — the extension lives for one share,
/// so it never needs to reason about expiry.
private struct ShareUploadTokenResponse: Decodable {
    let token: String
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
