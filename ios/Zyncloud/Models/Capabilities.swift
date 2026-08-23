import Foundation

/// Server-advertised ingest paths. Phase 5d/R1 ships with `tus.enabled=false`; R2 flips it.
/// Clients combine `tus.enabled` with the local `Settings.useTus` toggle when picking which
/// uploader to use — both must be true for a TUS upload, otherwise the multipart path runs.
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
