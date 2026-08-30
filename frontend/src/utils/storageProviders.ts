/**
 * Ready-made settings for the S3-compatible services people actually use.
 *
 * Every provider spells the same four things differently — what the endpoint URL looks like, what
 * they call a region, whether path-style addressing is required, and where in their console the
 * keys live. Getting any one of them wrong produces an SDK error that names none of the others, so
 * the picker fills in what it can and the hints say where to find the rest.
 *
 * `endpointTemplate` deliberately keeps its ANGLE-BRACKET placeholders: they land in the field for
 * the user to replace, which is clearer than an empty box and impossible to submit by accident —
 * the server rejects a host that still contains one.
 */
export interface StorageProviderPreset {
  id: string;
  label: string;
  /** Goes straight into the endpoint field; `<…>` parts are for the user to replace. */
  endpointTemplate: string;
  /** Pre-filled region, or "" when the provider needs the user to pick one. */
  region: string;
  /** What this provider calls a region, and an example, shown under the field. */
  regionHint: string;
  pathStyleAccess: boolean;
  /** Where to create the access key and secret key in this provider's console. */
  keysHint: string;
  /** Anything else that trips people up on this provider. */
  note?: string;
}

export const STORAGE_PROVIDERS: StorageProviderPreset[] = [
  {
    id: "aws",
    label: "Amazon S3",
    endpointTemplate: "https://s3.<region>.amazonaws.com",
    region: "",
    regionHint:
      'The bucket\'s region code, e.g. "eu-central-1" (Frankfurt) or "us-east-1" (Virginia). It must match the region in the endpoint URL.',
    pathStyleAccess: false,
    keysHint:
      "IAM → Users → your user → Security credentials → Create access key. Choose “Application running outside AWS”.",
    note: "Give the key s3:PutObject, s3:GetObject, s3:DeleteObject and s3:ListBucket on this bucket. Keep the bucket private — this app signs its own URLs.",
  },
  {
    id: "r2",
    label: "Cloudflare R2",
    endpointTemplate: "https://<account-id>.r2.cloudflarestorage.com",
    region: "auto",
    regionHint: 'R2 has one region. Leave it as "auto".',
    pathStyleAccess: true,
    keysHint:
      "R2 → Manage API tokens → Create API token, with Object Read & Write. Your account ID is in the same panel and goes in the endpoint URL.",
  },
  {
    id: "backblaze",
    label: "Backblaze B2",
    endpointTemplate: "https://s3.<region>.backblazeb2.com",
    region: "",
    regionHint:
      'B2 shows this as the "Endpoint" on the bucket page, e.g. "eu-central-003". The same code goes in the endpoint URL and here.',
    pathStyleAccess: true,
    keysHint:
      "Account → Application Keys → Add a New Application Key, restricted to this bucket. The keyID is the access key, the applicationKey is the secret.",
    note: "The secret is shown once, when you create the key. Copy it then.",
  },
  {
    id: "hetzner",
    label: "Hetzner Object Storage",
    endpointTemplate: "https://<location>.your-objectstorage.com",
    region: "",
    regionHint:
      'The location code of your bucket, e.g. "fsn1" (Falkenstein), "nbg1" (Nuremberg) or "hel1" (Helsinki). Same code as in the endpoint URL.',
    pathStyleAccess: true,
    keysHint:
      "Cloud Console → your project → Object Storage → Credentials → Generate credentials.",
  },
  {
    id: "wasabi",
    label: "Wasabi",
    endpointTemplate: "https://s3.<region>.wasabisys.com",
    region: "",
    regionHint: 'The bucket\'s region, e.g. "eu-central-1" or "us-east-1".',
    pathStyleAccess: true,
    keysHint: "Wasabi console → Access Keys → Create New Access Key.",
  },
  {
    id: "digitalocean",
    label: "DigitalOcean Spaces",
    endpointTemplate: "https://<region>.digitaloceanspaces.com",
    region: "",
    regionHint: 'The datacentre of your Space, e.g. "fra1", "ams3" or "nyc3".',
    pathStyleAccess: true,
    keysHint: "API → Spaces Keys → Generate New Key.",
  },
  {
    id: "scaleway",
    label: "Scaleway",
    endpointTemplate: "https://s3.<region>.scw.cloud",
    region: "",
    regionHint: 'The region of your bucket, e.g. "fr-par", "nl-ams" or "pl-waw".',
    pathStyleAccess: true,
    keysHint: "Console → Identity and Access Management → API keys → Generate API key.",
  },
  {
    id: "minio",
    label: "MinIO / self-hosted",
    endpointTemplate: "https://minio.example.com",
    region: "us-east-1",
    regionHint:
      'Self-hosted servers usually ignore this, but the S3 protocol still requires a value. Leave "us-east-1" unless yours says otherwise.',
    pathStyleAccess: true,
    keysHint:
      "MinIO Console → Access Keys → Create access key. Garage and Ceph have an equivalent page.",
    note: "The endpoint must be reachable from this server, not just from your browser.",
  },
  {
    id: "other",
    label: "Something else",
    endpointTemplate: "https://",
    region: "us-east-1",
    regionHint:
      'Whatever your provider calls the region. If they do not mention one, "us-east-1" is the usual placeholder.',
    pathStyleAccess: true,
    keysHint: "Look for “S3 credentials”, “access key” or “API key” in your provider's console.",
  },
];

export function findProvider(id: string): StorageProviderPreset | undefined {
  return STORAGE_PROVIDERS.find((p) => p.id === id);
}
