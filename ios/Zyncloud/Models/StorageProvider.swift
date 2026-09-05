import Foundation

/// Ready-made settings for the S3-compatible services people actually use.
///
/// Every provider spells the same four things differently — what the endpoint URL looks like, what
/// they call a region, whether path-style addressing is required, and where in their console the
/// keys live. Getting any one of them wrong produces an SDK error that names none of the others,
/// so the picker fills in what it can and the hints say where to find the rest.
///
/// `endpointTemplate` deliberately keeps its angle-bracket placeholders: they land in the field
/// for the user to replace, which is clearer than an empty box and impossible to submit by
/// accident — the server rejects a host that still contains one.
struct StorageProvider: Identifiable, Hashable {
    let id: String
    let label: String

    /// Goes straight into the endpoint field; `<…>` parts are for the user to replace.
    let endpointTemplate: String

    /// Pre-filled region, or "" when the provider needs the user to pick one.
    let region: String

    /// What this provider calls a region, and an example, shown under the field.
    let regionHint: String

    let pathStyleAccess: Bool

    /// Where to create the access key and secret key in this provider's console.
    let keysHint: String

    /// Anything else that trips people up on this provider.
    let note: String?

    static let all: [StorageProvider] = [
        StorageProvider(
            id: "aws",
            label: "Amazon S3",
            endpointTemplate: "https://s3.<region>.amazonaws.com",
            region: "",
            regionHint: "The bucket's region code, e.g. \"eu-central-1\" (Frankfurt) or \"us-east-1\" (Virginia). It must match the region in the endpoint URL.",
            pathStyleAccess: false,
            keysHint: "IAM → Users → your user → Security credentials → Create access key. Choose “Application running outside AWS”.",
            note: "Give the key s3:PutObject, s3:GetObject, s3:DeleteObject and s3:ListBucket on this bucket. Keep the bucket private — this app signs its own URLs.",
        ),
        StorageProvider(
            id: "r2",
            label: "Cloudflare R2",
            endpointTemplate: "https://<account-id>.r2.cloudflarestorage.com",
            region: "auto",
            regionHint: "R2 has one region. Leave it as \"auto\".",
            pathStyleAccess: true,
            keysHint: "R2 → Manage API tokens → Create API token, with Object Read & Write. Your account ID is in the same panel and goes in the endpoint URL.",
            note: nil,
        ),
        StorageProvider(
            id: "backblaze",
            label: "Backblaze B2",
            endpointTemplate: "https://s3.<region>.backblazeb2.com",
            region: "",
            regionHint: "B2 shows this as the \"Endpoint\" on the bucket page, e.g. \"eu-central-003\". The same code goes in the endpoint URL and here.",
            pathStyleAccess: true,
            keysHint: "Account → Application Keys → Add a New Application Key, restricted to this bucket. The keyID is the access key, the applicationKey is the secret.",
            note: "The secret is shown once, when you create the key. Copy it then.",
        ),
        StorageProvider(
            id: "hetzner",
            label: "Hetzner Object Storage",
            endpointTemplate: "https://<location>.your-objectstorage.com",
            region: "",
            regionHint: "The location code of your bucket, e.g. \"fsn1\" (Falkenstein), \"nbg1\" (Nuremberg) or \"hel1\" (Helsinki). Same code as in the endpoint URL.",
            pathStyleAccess: true,
            keysHint: "Cloud Console → your project → Object Storage → Credentials → Generate credentials.",
            note: nil,
        ),
        StorageProvider(
            id: "wasabi",
            label: "Wasabi",
            endpointTemplate: "https://s3.<region>.wasabisys.com",
            region: "",
            regionHint: "The bucket's region, e.g. \"eu-central-1\" or \"us-east-1\".",
            pathStyleAccess: true,
            keysHint: "Wasabi console → Access Keys → Create New Access Key.",
            note: nil,
        ),
        StorageProvider(
            id: "digitalocean",
            label: "DigitalOcean Spaces",
            endpointTemplate: "https://<region>.digitaloceanspaces.com",
            region: "",
            regionHint: "The datacentre of your Space, e.g. \"fra1\", \"ams3\" or \"nyc3\".",
            pathStyleAccess: true,
            keysHint: "API → Spaces Keys → Generate New Key.",
            note: nil,
        ),
        StorageProvider(
            id: "scaleway",
            label: "Scaleway",
            endpointTemplate: "https://s3.<region>.scw.cloud",
            region: "",
            regionHint: "The region of your bucket, e.g. \"fr-par\", \"nl-ams\" or \"pl-waw\".",
            pathStyleAccess: true,
            keysHint: "Console → Identity and Access Management → API keys → Generate API key.",
            note: nil,
        ),
        StorageProvider(
            id: "ovh",
            label: "OVHcloud Object Storage",
            endpointTemplate: "https://s3.<region>.io.cloud.ovh.net",
            region: "",
            regionHint: "The lowercase region code of your bucket, e.g. \"gra\" (Gravelines), \"rbx\" (Roubaix), \"sbg\" (Strasbourg), \"eu-west-par\" (Paris) or \"eu-south-mil\" (Milan). It must match the region in the endpoint URL — read it off the bucket in the OVH control panel.",
            pathStyleAccess: false,
            keysHint: "Public Cloud → Object Storage → S3 users → create a user, then generate S3 credentials. Grant it a role or a bucket policy on this bucket as well: a user with no policy gets 403 on everything. The secret is shown once.",
            note: "Use the io.cloud.ovh.net endpoint, not the older perf.cloud.ovh.net one. OVH answers 501 to conditional writes (If-None-Match), but this app does not use them.",
        ),
        StorageProvider(
            id: "minio",
            label: "MinIO / self-hosted",
            endpointTemplate: "https://minio.example.com",
            region: "us-east-1",
            regionHint: "Self-hosted servers usually ignore this, but the S3 protocol still requires a value. Leave \"us-east-1\" unless yours says otherwise.",
            pathStyleAccess: true,
            keysHint: "MinIO Console → Access Keys → Create access key. Garage and Ceph have an equivalent page.",
            note: "The endpoint must be reachable from the photo server, not just from your phone.",
        ),
        StorageProvider(
            id: "other",
            label: "Something else",
            endpointTemplate: "https://",
            region: "us-east-1",
            regionHint: "Whatever your provider calls the region. If they do not mention one, \"us-east-1\" is the usual placeholder.",
            pathStyleAccess: true,
            keysHint: "Look for “S3 credentials”, “access key” or “API key” in your provider's console.",
            note: nil,
        ),
    ]

    static func named(_ id: String) -> StorageProvider {
        all.first { $0.id == id } ?? all[0]
    }

    /// Which preset an existing endpoint looks like, so an edit form shows hints about the
    /// provider it actually points at.
    ///
    /// Matched on the domain *suffix*, never the prefix: "https://s3." starts both the Amazon and
    /// the Backblaze template, so a prefix match would file every B2 bucket under AWS — whichever
    /// happened to be listed first. The tail after the last placeholder is unique per provider.
    static func guess(fromEndpoint endpoint: String) -> StorageProvider {
        var host = endpoint.lowercased()
        while host.hasSuffix("/") {
            host.removeLast()
        }
        let match = all.first { provider in
            guard provider.id != "other",
                  let suffix = provider.endpointTemplate.lowercased().components(separatedBy: ">").last,
                  provider.endpointTemplate.contains(">"),
                  suffix.count > 4
            else { return false }
            return host.hasSuffix(suffix)
        }
        return match ?? named("other")
    }
}
