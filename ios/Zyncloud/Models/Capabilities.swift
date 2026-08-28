import Foundation

/// Server-advertised ingest paths. Phase 5d/R1 ships with `tus.enabled=false`; R2 flips it.
/// `tus.enabled` alone picks the uploader — when it is false the multipart path runs.
struct Capabilities: Decodable {
    let tus: TusCapability
    let multipart: MultipartCapability
}

struct TusCapability: Decodable {
    let enabled: Bool
    let endpoint: String
    let version: String
    let maxSize: Int64
}

struct MultipartCapability: Decodable {
    let enabled: Bool
    let endpoint: String
}
