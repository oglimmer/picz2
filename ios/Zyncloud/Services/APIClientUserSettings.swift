import Foundation

/// Narration languages and tags — the two user-level settings the web app exposes from its
/// account menu. Kept in their own file so `APIClientExtensions.swift` stops growing.
extension APIClient {
    // MARK: - Narration Languages

    func fetchLanguageSettings(completion: @escaping (Result<LanguageSettingsResponse, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/settings/languages"))
        request.httpMethod = "GET"
        addBasicAuth(to: &request)

        performRequest(request, expecting: LanguageSettingsResponse.self, completion: completion)
    }

    /// `slot` is 1 or 2 — the server exposes one endpoint per language rather than a single
    /// payload with both, so the slot is part of the path.
    func setLanguageName(slot: Int, name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/settings/languages/\(slot)"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addBasicAuth(to: &request)

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["value": name])
        } catch {
            completion(.failure(error))
            return
        }

        performRequestIgnoringBody(request, completion: completion)
    }

    // MARK: - Tags

    func fetchTags(completion: @escaping (Result<[Tag], Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.httpMethod = "GET"
        addBasicAuth(to: &request)

        performRequest(request, expecting: TagsListResponse.self) { result in
            completion(result.map(\.tags))
        }
    }

    func createTag(name: String, completion: @escaping (Result<Tag?, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addBasicAuth(to: &request)

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["tagName": name])
        } catch {
            completion(.failure(error))
            return
        }

        performRequest(request, expecting: TagResponse.self) { result in
            completion(result.map(\.tag))
        }
    }

    func updateTag(id: Int, name: String, completion: @escaping (Result<Tag?, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags/\(id)"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addBasicAuth(to: &request)

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["tagName": name])
        } catch {
            completion(.failure(error))
            return
        }

        performRequest(request, expecting: TagResponse.self) { result in
            completion(result.map(\.tag))
        }
    }

    func deleteTag(id: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags/\(id)"))
        request.httpMethod = "DELETE"
        addBasicAuth(to: &request)

        performRequestIgnoringBody(request, completion: completion)
    }
}
