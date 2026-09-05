import Foundation
import os

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
        completion: @escaping @Sendable (Result<Int, Error>) -> Void,
    ) {
        send(.get, "api/assets/by-content",
             query: [
                 URLQueryItem(name: "albumId", value: String(albumId)),
                 URLQueryItem(name: "contentId", value: contentId),
             ],
             expecting: AssetProcessingStatusResponse.self)
        { result in
            completion(result.map(\.id))
        }
    }
}

// MARK: - Server Capabilities (Phase 5)

extension APIClient {
    /// Fetch ingest-path capabilities. Unauthenticated; safe to call before login. The result
    /// is cached briefly by the caller (SyncCoordinator) — there's no point re-asking on every
    /// upload, the server flips this only at deploy boundaries.
    func fetchCapabilities(completion: @escaping @Sendable (Result<Capabilities, Error>) -> Void) {
        send(.get, "api/capabilities", expecting: Capabilities.self,
             authenticated: false, completion: completion)
    }
}

// MARK: - Album Management Extensions

extension APIClient {
    // MARK: - Create Album

    /// - Parameter storageBackendId: which storage to put the photos in. `nil` means the site's
    ///   own. Only honoured here, at creation — the server rejects a later change.
    func createAlbum(
        name: String,
        description: String?,
        storageBackendId: Int? = nil,
        completion: @escaping @Sendable (Result<Album, Error>) -> Void,
    ) {
        send(.post, "api/albums",
             body: AlbumBody(
                 name: name,
                 description: description ?? "",
                 storageBackendId: storageBackendId,
             ),
             expecting: AlbumResponse.self)
        { result in
            completion(result.map(\.album))
        }
    }

    // MARK: - Update Album

    func updateAlbum(id: Int, name: String, description: String?, completion: @escaping @Sendable (Result<Album, Error>) -> Void) {
        send(.put, "api/albums/\(id)",
             body: AlbumBody(name: name, description: description ?? ""),
             expecting: AlbumResponse.self)
        { result in
            completion(result.map(\.album))
        }
    }

    // MARK: - Delete Album

    func deleteAlbum(id: Int, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(.delete, "api/albums/\(id)", completion: completion)
    }

    // MARK: - Duplicate Album

    /// Copies an album, the metadata of every photo in it and its enabled tags into a new album.
    ///
    /// The bytes are not copied: the new rows point at the source album's storage keys, so this
    /// costs no storage and returns as fast as any other write. Mirrors `duplicateAlbum` in the
    /// web app's `useAlbums` composable.
    ///
    /// The copy always comes back unpublished, however public the source was, so a caller must
    /// not promise a working share link for it.
    func duplicateAlbum(id: Int, completion: @escaping @Sendable (Result<Album, Error>) -> Void) {
        send(.post, "api/albums/\(id)/duplicate", expecting: AlbumResponse.self) { result in
            completion(result.map(\.album))
        }
    }

    // MARK: - Fetch Files in Album

    func fetchFiles(albumId: Int, tag: String? = nil, completion: @escaping @Sendable (Result<FilesResponse, Error>) -> Void) {
        send(.get, "api/albums/\(albumId)/files",
             query: tag.map { [URLQueryItem(name: "tag", value: $0)] } ?? [],
             expecting: FilesResponse.self, completion: completion)
    }

    /// Backwards compatibility - fetchPhotos now calls fetchFiles
    func fetchPhotos(albumId: Int, page _: Int = 1, limit _: Int = 50, completion: @escaping @Sendable (Result<PhotosResponse, Error>) -> Void) {
        fetchFiles(albumId: albumId, tag: nil, completion: completion)
    }

    // MARK: - Asset Processing Status

    func getAssetStatus(id: Int, completion: @escaping @Sendable (Result<AssetProcessingStatusResponse, Error>) -> Void) {
        send(.get, "api/assets/\(id)/status",
             expecting: AssetProcessingStatusResponse.self, completion: completion)
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
        data: Data?, response: URLResponse?, error: Error?,
    ) -> Result<(body: Data, statusCode: Int), Error> {
        if let error {
            AppLog.api.error("Network error: \(error.localizedDescription, privacy: .public)")
            return .failure(AppError.network(error))
        }
        guard let data else {
            AppLog.api.error("No data received")
            return .failure(AppError.api(message: "No data received", statusCode: nil))
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLog.api.error("Reply was not an HTTP response")
            return .failure(AppError.api(message: "Invalid response", statusCode: nil))
        }
        AppLog.api.debug(
            "Received \(data.count, privacy: .public) bytes — HTTP \(httpResponse.statusCode, privacy: .public)",
        )
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let errorMessage = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                return .failure(AppError.api(message: errorMessage.message, statusCode: httpResponse.statusCode))
            }
            return .failure(AppError.api(message: plainMeaning(of: httpResponse.statusCode),
                                         statusCode: httpResponse.statusCode))
        }
        return .success((data, httpResponse.statusCode))
    }

    /// A sentence for a status code the server did not explain itself.
    ///
    /// The fallback used to be the bare string `"HTTP 404"`, which ``AppError`` then rendered as
    /// "API error (404): HTTP 404" — the number twice and no help either time. The server does
    /// send an `ErrorResponse` for most refusals, so this is only for when it does not; the
    /// code stays on the end of every one of them, because that is what a bug report needs.
    static func plainMeaning(of statusCode: Int) -> String {
        let sentence = switch statusCode {
        case 401: "Your email or password was not accepted."
        case 403: "You are not allowed to do that."
        case 404: "The server has no such item."
        case 409: "The server already has this."
        case 413: "That file is too big for the server."
        case 429: "Too many requests — try again in a moment."
        case 500 ... 599: "The server had a problem. Try again later."
        default: "The server refused the request."
        }
        return "\(sentence) (HTTP \(statusCode))"
    }

    /// For endpoints that answer with a status code and nothing worth decoding. Reuses the same
    /// error ladder — a 2xx is success, anything else is an ``AppError/api`` carrying the
    /// server's message when it sent one.
    func performRequestIgnoringBody(_ request: URLRequest, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
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
    func performRequest<T: Decodable & Sendable>(_ request: URLRequest, expecting _: T.Type, completion: @escaping @Sendable (Result<T, Error>) -> Void) {
        // The method and path are safe to read in a support log; the full URL can carry a tag
        // name or an album id in the query, so it stays redacted.
        AppLog.api.debug("""
        \(request.httpMethod ?? "GET", privacy: .public) \
        \(request.url?.path ?? "unknown", privacy: .public) \(request.url?.query ?? "")
        """)

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

            do {
                // The body is the user's own album and file names, so it is redacted in the
                // unified log and only visible when a debugger is attached.
                if let jsonString = String(data: data, encoding: .utf8) {
                    AppLog.api.debug("Response \(request.url?.path ?? "unknown", privacy: .public): \(jsonString)")
                }

                let decoder = JSONDecoder()
                let decodedResponse = try decoder.decode(T.self, from: data)
                completion(.success(decodedResponse))
            } catch {
                // Which field broke, not what was in it — the key path and the decoder's own
                // description name the shape, and the shape is not user data.
                AppLog.api.error("""
                Could not decode \(String(describing: T.self), privacy: .public) \
                from \(request.url?.path ?? "unknown", privacy: .public): \
                \(Self.describe(decodingError: error), privacy: .public)
                """)
                completion(.failure(AppError.decoding(Self.describe(decodingError: error))))
            }
        }

        task.resume()
    }

    /// Names the field a decode tripped over.
    ///
    /// `DecodingError.localizedDescription` is the useless "The data couldn't be read because it
    /// is missing." — it does not say which key, which is the only thing worth knowing when a
    /// server field is renamed. Contains no values from the body, so it is safe to log in the
    /// clear.
    private static func describe(decodingError error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        switch decodingError {
        case let .keyNotFound(key, context):
            return "missing key '\(key.stringValue)' — \(context.debugDescription)"
        case let .typeMismatch(type, context):
            return "expected \(type) — \(context.debugDescription)"
        case let .valueNotFound(type, context):
            return "no value for \(type) — \(context.debugDescription)"
        case let .dataCorrupted(context):
            return "data corrupted — \(context.debugDescription)"
        @unknown default:
            return "unrecognised decoding error"
        }
    }
}

// MARK: - Device Token Management Extensions

extension APIClient {
    func registerDeviceToken(_ body: DeviceTokenBody, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(.post, "api/device-tokens", body: body, completion: completion)
    }

    func unregisterDeviceToken(token: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(.delete, "api/device-tokens",
             query: [URLQueryItem(name: "deviceToken", value: token)],
             completion: completion)
    }
}

/// What `POST /api/device-tokens` wants: the push address, plus enough about the device to tell
/// two installs apart in the server's token table.
struct DeviceTokenBody: Encodable {
    let deviceToken: String
    let email: String
    let appVersion: String
    let deviceModel: String
    let osVersion: String
}

// MARK: - Authentication Endpoints

extension APIClient {
    /// Validate the credentials currently set on this client against `/api/auth/check`.
    /// Returns the server-side email and `emailVerified` flag.
    func checkAuth(completion: @escaping @Sendable (Result<AuthCheckResponse, Error>) -> Void) {
        send(.get, "api/auth/check", expecting: AuthCheckResponse.self) { result in
            switch result {
            case let .success(decoded) where decoded.success:
                completion(.success(decoded))
            case .success:
                // 200 with `success: false`. The server says the credentials are no good.
                completion(.failure(AppError.authentication("Invalid email or password")))
            case let .failure(error):
                // Any refusal on this endpoint means the same thing to the user, whatever the
                // status was — this is the call whose whole job is "are these credentials
                // good?". A transport failure or an unreadable body is not a refusal, and both
                // arrive with no status on them, so they pass through as themselves.
                if (error as? AppError)?.statusCode != nil {
                    completion(.failure(AppError.authentication("Invalid email or password")))
                } else {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Permanently delete the signed-in account and everything it owns — albums, files, tags
    /// and settings. Irreversible; the server cascades the delete. The caller is responsible for
    /// clearing local credentials and caches afterwards, exactly as logout does.
    func deleteAccount(completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(.delete, "api/users/account", completion: completion)
    }

    /// Create a new account. Unauthenticated POST to `/api/users`. On success the server
    /// has emailed a verification link; the user can't sign in until they click it.
    static func register(email: String, password: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        // No credentials to attach — this call is how you get some.
        APIClient().send(.post, "api/users",
                         body: RegistrationBody(email: email, password: password),
                         authenticated: false, completion: completion)
    }

    /// Request a password-reset email. Unauthenticated POST to
    /// `/api/users/password-reset-request`. Server returns 200 even if the email is unknown
    /// (to avoid leaking account existence) — mirror that behavior in the UI.
    static func requestPasswordReset(email: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        APIClient().send(.post, "api/users/password-reset-request",
                         body: PasswordResetBody(email: email),
                         authenticated: false, completion: completion)
    }
}

/// The body of `POST /api/users`.
struct RegistrationBody: Encodable {
    let email: String
    let password: String
}

/// The body of `POST /api/users/password-reset-request`.
struct PasswordResetBody: Encodable {
    let email: String
}

// MARK: - Response Models

struct AlbumResponse: Codable {
    let success: Bool
    let album: Album
}

/// The body of `POST /api/albums` and `PUT /api/albums/{id}`. The server wants a description
/// field either way, so a missing one is sent as empty rather than left out.
struct AlbumBody: Encodable {
    let name: String
    let description: String

    /// Absent on an update: the server rejects a request that tries to move an existing album,
    /// so an edit must not send the field at all. Encoded as null on create to mean "the default".
    var storageBackendId: Int?
}

struct ErrorResponse: Codable {
    let success: Bool
    let message: String
}

struct AuthCheckResponse: Codable {
    let success: Bool
    let email: String?
    let emailVerified: Bool
    /// Operator account (server D74). Optional because a server older than that answers without
    /// the field, and a missing flag must read as "not an admin", never as a decode failure.
    let admin: Bool?

    var isAdmin: Bool {
        admin ?? false
    }
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
    func reorderAlbum(albumId: Int, by action: AlbumSortAction, completion: @escaping @Sendable (Result<Int, Error>) -> Void) {
        send(.post, "api/albums/\(albumId)/\(action.endpointSuffix)",
             expecting: ReorderResponse.self)
        { result in
            completion(result.map(\.updatedCount))
        }
    }

    /// Persists a hand-made order. `fileIds` must be the album's files in the wanted order —
    /// the server writes each file's `displayOrder` from its index, same as the web app's
    /// "Arrange by hand" mode.
    func reorderFiles(fileIds: [Int], completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(.put, "api/files/reorder", body: ReorderBody(fileIds: fileIds), completion: completion)
    }
}

/// The body of `PUT /api/files/reorder` — the album's files in the order they should end up in.
struct ReorderBody: Encodable {
    let fileIds: [Int]
}

// MARK: - Single-file actions

extension APIClient {
    /// Deletes one file. Irreversible — the server drops the stored objects as well as the row.
    func deleteFile(id: Int, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(.delete, "api/files/\(id)", completion: completion)
    }

    /// Queues a 90° left rotation. Answers 202 as soon as the job is enqueued — the worker pod
    /// does the work, so the caller has to poll ``getAssetStatus(id:completion:)`` before the
    /// new image is there to show. Rotating also swaps the asset's `publicToken`, which is why
    /// the file list has to be reloaded afterwards rather than just the image.
    func rotateImageLeft(id: Int, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(.post, "api/files/\(id)/rotate", completion: completion)
    }

    /// Writes the owner's caption on one photo (D69), and answers with the photo as it now is.
    ///
    /// Synchronous on the server — nothing is re-rendered — so unlike a rotate there is no
    /// status to poll and no reload to follow. An empty `caption` clears it.
    func updateCaption(id: Int, caption: String, completion: @escaping @Sendable (Result<Photo, Error>) -> Void) {
        send(.put, "api/files/\(id)/caption", body: CaptionBody(caption: caption), expecting: Photo.self, completion: completion)
    }
}

/// The body of `PUT /api/files/{id}/caption`. Blank means "clear it" — the server stores null.
struct CaptionBody: Encodable {
    let caption: String
}

struct ReorderResponse: Codable {
    let success: Bool
    let message: String?
    let updatedCount: Int
}
