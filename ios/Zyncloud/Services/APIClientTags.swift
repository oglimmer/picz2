import Foundation

/// Putting tags on files and taking them off — one file at a time, or every file in an album.
///
/// The server has no endpoint for "these particular files", so a selection is applied file by
/// file by the caller. Only the whole-album case has a bulk endpoint, and it is worth using:
/// it is one request instead of one per photo.
extension APIClient {
    // MARK: - One file

    func addTag(fileId: Int, tagName: String, completion: @escaping (Result<[String], Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/files/\(fileId)/tags"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addBasicAuth(to: &request)

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["tagName": tagName])
        } catch {
            completion(.failure(error))
            return
        }

        performRequest(request, expecting: FileTagsResponse.self) { result in
            completion(result.map(\.tags))
        }
    }

    func removeTag(fileId: Int, tagName: String, completion: @escaping (Result<[String], Error>) -> Void) {
        guard let url = tagURL(prefix: "api/files/\(fileId)/tags", tagName: tagName) else {
            completion(.failure(AppError.api(message: "\"\(tagName)\" cannot be used in a web address.", statusCode: nil)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addBasicAuth(to: &request)

        performRequest(request, expecting: FileTagsResponse.self) { result in
            completion(result.map(\.tags))
        }
    }

    // MARK: - Every file in an album

    /// Answers how many files actually changed. Files that already carry the tag are skipped.
    func addTagToAllFiles(albumId: Int, tagName: String, completion: @escaping (Result<Int, Error>) -> Void) {
        bulkTagRequest(albumId: albumId, tagName: tagName, method: "POST", completion: completion)
    }

    func removeTagFromAllFiles(albumId: Int, tagName: String, completion: @escaping (Result<Int, Error>) -> Void) {
        bulkTagRequest(albumId: albumId, tagName: tagName, method: "DELETE", completion: completion)
    }

    private func bulkTagRequest(
        albumId: Int,
        tagName: String,
        method: String,
        completion: @escaping (Result<Int, Error>) -> Void,
    ) {
        guard let url = tagURL(prefix: "api/albums/\(albumId)/files/tags", tagName: tagName) else {
            completion(.failure(AppError.api(message: "\"\(tagName)\" cannot be used in a web address.", statusCode: nil)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        addBasicAuth(to: &request)

        performRequest(request, expecting: BulkTagResponse.self) { result in
            completion(result.map(\.updatedCount))
        }
    }

    // MARK: - Which tags an album allows

    /// The tags this album accepts. The server refuses to put any other tag on a file in it
    /// (`FileStorageService.addTagToFile`), so this — not the account-wide list — is what the
    /// pickers offer. The `all` system tag is always in the answer.
    func fetchEnabledTags(albumId: Int, completion: @escaping (Result<[Tag], Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/albums/\(albumId)/enabled-tags"))
        request.httpMethod = "GET"
        addBasicAuth(to: &request)

        performRequest(request, expecting: TagsListResponse.self) { result in
            completion(result.map(\.tags))
        }
    }

    /// Replaces the album's allowed tags with exactly `tagIds`. It is a whole-list write, not a
    /// toggle — any id left out is switched off. System tag ids may be sent; the server drops
    /// them because those are always on.
    func setEnabledTags(albumId: Int, tagIds: [Int], completion: @escaping (Result<[Tag], Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/albums/\(albumId)/enabled-tags"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addBasicAuth(to: &request)

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["tagIds": tagIds])
        } catch {
            completion(.failure(error))
            return
        }

        performRequest(request, expecting: TagsListResponse.self) { result in
            completion(result.map(\.tags))
        }
    }

    // MARK: - URL building

    /// Splices a tag name into the last path segment.
    ///
    /// Built by hand rather than with `appendingPathComponent`, which leaves a `/` in the name
    /// alone: a tag called "a/b" would then address a different endpoint instead of naming a
    /// tag. Percent-encoding first and appending the encoded text keeps the name one segment.
    ///
    /// The base is pasted in as text rather than passed as a relative URL's base, because
    /// relative resolution drops the last path segment of the base — a `ZYNCLOUD_BASE_URL`
    /// with a path on it would silently lose that path.
    private func tagURL(prefix: String, tagName: String) -> URL? {
        guard let encoded = tagName.addingPercentEncoding(withAllowedCharacters: .zyncTagPathSegment) else {
            return nil
        }

        var root = baseURL.absoluteString
        while root.hasSuffix("/") {
            root.removeLast()
        }

        return URL(string: "\(root)/\(prefix)/\(encoded)")
    }
}

private extension CharacterSet {
    /// What may stay literal inside one path segment. `urlPathAllowed` is too generous — it
    /// permits `/`, `;` and `%`, all of which change what the segment means.
    static let zyncTagPathSegment: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}
