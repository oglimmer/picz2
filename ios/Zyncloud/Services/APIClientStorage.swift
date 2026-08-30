import Foundation

/// "Bring your own storage" — the endpoints behind `/api/storage-backends`.
///
/// The list always includes the site's own storage, so a picker can render one list without
/// special-casing the default.
extension APIClient {
    func fetchStorageBackends(completion: @escaping @Sendable (Result<[StorageBackend], Error>) -> Void) {
        send(.get, "api/storage-backends", expecting: [StorageBackend].self, completion: completion)
    }

    func createStorageBackend(
        _ body: StorageBackendBody,
        completion: @escaping @Sendable (Result<StorageBackend, Error>) -> Void,
    ) {
        send(.post, "api/storage-backends", body: body, expecting: StorageBackend.self, completion: completion)
    }

    func updateStorageBackend(
        id: Int,
        body: StorageBackendBody,
        completion: @escaping @Sendable (Result<StorageBackend, Error>) -> Void,
    ) {
        send(.put, "api/storage-backends/\(id)", body: body, expecting: StorageBackend.self, completion: completion)
    }

    func deleteStorageBackend(id: Int, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        send(.delete, "api/storage-backends/\(id)", completion: completion)
    }

    /// Try settings without saving them. Answers 200 with `ok: false` when the storage itself is
    /// the problem, so only a transport failure lands in the `.failure` case here.
    func testStorageBackend(
        id: Int?,
        body: StorageBackendBody,
        completion: @escaping @Sendable (Result<StorageBackendTestResult, Error>) -> Void,
    ) {
        let path = id.map { "api/storage-backends/\($0)/test" } ?? "api/storage-backends/test"
        send(.post, path, body: body, expecting: StorageBackendTestResult.self, completion: completion)
    }
}
