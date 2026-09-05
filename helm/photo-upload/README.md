# Photo Upload Helm Chart

Deploys the Photo Upload application — a personal photo / video gallery with iOS sync, TUS resumable uploads, and S3-backed storage. Five workloads in one chart:

| Component   | Type        | Purpose                                                                  |
| ----------- | ----------- | ------------------------------------------------------------------------ |
| `backend`   | Deployment  | API pod (Spring Boot 4 / Java 25). Handles HTTP, serves bytes from S3.   |
| `worker`    | Deployment  | Drains `processing_jobs` (vips / HEIC / ffmpeg). Same JAR, worker profile. |
| `frontend`  | Deployment  | Vue 3 SPA served by Nginx.                                               |
| `tusd`      | Deployment  | TUS resumable uploads (v2.4.0). Writes directly to MinIO; thin hook callbacks to backend. |
| `retention` | CronJob     | Nightly sweep — purges aged originals, mops up abandoned TUS uploads, cleans orphan S3 keys. |

Architecture, decision log, and phase history live in [`upload-concept-plan.md`](../../upload-concept-plan.md). This README is a deploy-and-operate reference; for *why* something is shaped the way it is, read the plan.

## Prerequisites

- Kubernetes 1.25+ (uses `batch/v1` CronJob, `Always`-pull policy semantics)
- Helm 3.0+
- An external **MariaDB 10.6+** (uses `SELECT … FOR UPDATE SKIP LOCKED` for the job dispatcher's leases)
- An external **S3-compatible object store** (MinIO is what's tested). Single-bucket; the chart does not provision it.
- An ingress controller (Traefik in the reference deploy, but anything serving plain HTTP works)
- Optional: standalone **Prometheus** chart for scrape + alerts (no `prometheus-operator` CRDs required)

## Quick start

Reference deploy with secrets passed inline (suitable for laptops, **not** production — see [Secrets](#secrets-management) below):

```bash
helm install photo-upload ./helm/photo-upload \
  --set objectStorage.accessKey=YOUR_MINIO_ACCESS_KEY \
  --set objectStorage.secretKey=YOUR_MINIO_SECRET_KEY \
  --set database.external.password=YOUR_DB_PASSWORD \
  --set tus.hookSecret=$(openssl rand -hex 32)
```

Upgrade pattern (preserves existing `--set` values, additive overrides):

```bash
helm upgrade photo-upload ./helm/photo-upload \
  --reset-then-reuse-values \
  --set objectStorage.accessKey=… \
  --set objectStorage.secretKey=… \
  --set database.external.password=… \
  --set tus.hookSecret=…
```

## Architecture at a glance

```
                    ┌──────────┐  /api/i/{token}  ┌───────────┐
   browser ────────▶│ frontend │◀─────────────────│  backend  │──┐
                    │ (Nginx)  │                  │  (api)    │  │
                    └──────────┘                  └─────┬─────┘  │
                                                       SQL       │  S3 GET
                                                        │        │  (serve bytes)
                                                        ▼        │
                                                   ┌────────┐    │
                                                   │MariaDB │    │
                                                   └────────┘    │
                                                        ▲        │
                                                       SQL       │
                                                  enqueue/lease  │
                                                        │        │
   iOS / web ──────▶ ┌──────┐  POST/PATCH    ┌────────┴────┐    │
   (TUS upload)      │ tusd │ ─── S3 PUT ──▶│   MinIO     │◀──┘
                     └──┬───┘                │  (S3)        │
                        │ post-finish hook   └─────▲────────┘
                        ▼                          │
                  ┌───────────┐                    │  S3 GET (download original)
                  │  backend  │                    │  S3 PUT (write derivatives)
                  │ (api hook)│                    │
                  └───────────┘            ┌───────┴────┐
                                           │   worker   │
                                           │ (vips/heic │
                                           │  ffmpeg)   │
                                           └────────────┘

   Nightly:        ┌───────────┐  S3 LIST + DELETE
                   │ retention │ ────────────────────▶ MinIO
                   │  CronJob  │  (originals, TUS, orphans)
                   └───────────┘
```

The api and worker pods run **the same image** with different `SPRING_PROFILES_ACTIVE`. They share state via MariaDB + MinIO only — no shared filesystem.

## Configuration

### Global

| Parameter      | Description                              | Default |
| -------------- | ---------------------------------------- | ------- |
| `replicaCount` | Replicas for backend (api). Worker has its own knob. | `1`     |

### Backend (api pod)

| Parameter                          | Description                                                                   | Default                                                                  |
| ---------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `backend.image.repository`         | Image repo                                                                    | `registry.oglimmer.com/picz2-be`                                         |
| `backend.image.tag`                | Image tag                                                                     | `latest`                                                                 |
| `backend.image.pullPolicy`         | Image pull policy                                                             | `Always`                                                                 |
| `backend.baseUrl`                  | Public origin used in Open Graph meta tags                                    | `https://picz2.oglimmer.com`                                             |
| `backend.service.port`             | Cluster service port                                                          | `8080`                                                                   |
| `backend.resources`                | CPU/memory limits + requests                                                  | `1Gi` limit / `768Mi` request — slim, no derivative work in this pod    |
| `backend.javaOpts`                 | JVM flags                                                                     | `-Xmx512m -Xms256m -XX:+ExitOnOutOfMemoryError …`                        |
| `backend.sprintProfilesActive`     | Spring profiles active on the api pod                                         | `api`                                                                    |
| `backend.maxConcurrentProcessing`  | Legacy in-pod concurrency cap (used only when no worker is running)           | `1`                                                                      |
| `backend.processingQueueCapacity`  | Backpressure threshold for `UploadBackpressureFilter` (queue depth → 503)     | `50`                                                                     |
| `backend.persistence.enabled`      | Render a PVC for the backend (legacy — uploads go to S3 now)                  | `false`                                                                  |
| `backend.persistence.mounted`      | Mount the PVC into the pod (false → emptyDir for transient `.multipart-tmp`) | `false`                                                                  |
| `backend.persistence.size`         | PVC size if `enabled=true`                                                    | `30Gi`                                                                   |
| `backend.persistence.storageClass` | Storage class name                                                            | `""`                                                                     |
| `backend.persistence.emptyDirSizeLimit` | Cap on the in-pod scratch volume when `mounted=false`                    | `5Gi`                                                                    |

### Worker (processing pod)

| Parameter                       | Description                                                       | Default                          |
| ------------------------------- | ----------------------------------------------------------------- | -------------------------------- |
| `worker.enabled`                | Render the worker Deployment                                      | `true`                           |
| `worker.replicas`               | Worker pods (each has `Semaphore(1)`, scale-out for parallelism)  | `1`                              |
| `worker.image.tag`              | Image tag (falls through to `backend.image.tag` if blank)         | `""`                             |
| `worker.resources`              | CPU/memory limits + requests                                      | `2Gi` limit / `1Gi` request      |
| `worker.javaOpts`               | JVM flags (heap is small — actual encode RAM lives in subprocesses) | `-Xmx512m -XX:MaxRAMPercentage=35.0 …` |
| `worker.sprintProfilesActive`   | Spring profiles active on the worker pod                          | `worker`                         |
| `worker.workdir.sizeLimit`      | emptyDir for per-job derivative scratch                           | `5Gi`                            |
| `worker.workdir.mountPath`      | Mount path for the workdir                                        | `/app/uploads`                   |

### Frontend

| Parameter                   | Description       | Default                          |
| --------------------------- | ----------------- | -------------------------------- |
| `frontend.image.repository` | Image repo        | `registry.oglimmer.com/picz2-fe` |
| `frontend.image.tag`        | Image tag         | `latest`                         |
| `frontend.image.pullPolicy` | Image pull policy | `Always`                         |
| `frontend.service.port`     | Service port      | `80`                             |
| `frontend.resources`        | CPU/memory        | `256Mi` limit / `128Mi` request  |

### Database (external)

| Parameter                    | Description                          | Default       |
| ---------------------------- | ------------------------------------ | ------------- |
| `database.external.enabled`  | Use external MariaDB (the only path) | `true`        |
| `database.external.host`     | Database host                        | `mariadb`     |
| `database.external.port`     | Database port                        | `3306`        |
| `database.external.name`     | Database name                        | `photoupload` |
| `database.external.user`     | Database user                        | `photoupload` |
| `database.external.password` | Database password                    | `photoupload` |

### Object storage (MinIO / S3)

| Parameter                    | Description                                                                | Default                                  |
| ---------------------------- | -------------------------------------------------------------------------- | ---------------------------------------- |
| `objectStorage.enabled`      | Renders the S3 env/secret wiring. Must stay `true`: since D77 the backend has no other storage mode and will not boot without an endpoint | `true`                                   |
| `objectStorage.endpoint`     | S3 endpoint URL                                                            | `http://minio.minio.svc.cluster.local:9000` |
| `objectStorage.bucket`       | Bucket name (auto-created on startup if missing)                           | `photo-upload`                           |
| `objectStorage.region`       | S3 region (MinIO ignores this but the SDK requires it)                     | `us-east-1`                              |
| `objectStorage.accessKey`    | Access key — **must** be overridden                                        | `""`                                     |
| `objectStorage.secretKey`    | Secret key — **must** be overridden                                        | `""`                                     |
| `objectStorage.backendSecretKey` | Base64 AES key encrypting user-registered storage credentials. Empty = "bring your own storage" is off | `""`                        |

### TUS resumable uploads

Two-flag rollout: `enabled` controls whether tusd + the api hook are *deployed*; `advertised` controls whether `/api/capabilities` tells clients to use TUS. R1 ships `enabled=true / advertised=false`; R2 flips advertised. iOS picks the path based on a cached `/api/capabilities` × user setting.

| Parameter            | Description                                                                              | Default                |
| -------------------- | ---------------------------------------------------------------------------------------- | ---------------------- |
| `tus.enabled`        | Render tusd Deployment + Service + Ingress route + api-side hook controller              | `true`                 |
| `tus.advertised`     | Tell clients (via `/api/capabilities`) to use TUS                                        | `false`                |
| `tus.image.tag`      | tusd image tag                                                                           | `v2.4.0`               |
| `tus.endpoint`       | Public path prefix (also tusd's `-base-path`)                                            | `/files/`              |
| `tus.maxSize`        | Per-upload size cap, bytes (matches Spring's multipart cap)                              | `524288000` (500 MB)   |
| `tus.hookSecret`     | Path-secret embedded in the tusd → api hook URL — **must** be overridden                 | `""`                   |
| `tus.replicas`       | tusd replicas (stateless once `info.json` is in S3)                                      | `1`                    |

### Apple Maps (map filter)

The gallery's "🗺️ Map" filter draws pins from each asset's capture location using Apple MapKit JS. MapKit refuses to initialise without a short-lived ES256 JWT, which the api pod mints from an Apple Developer key — so the feature is **off** until you supply one. With `appleMaps.enabled=false`, `/api/capabilities` reports `maps.enabled=false` and the frontend hides the filter entirely; nothing else changes.

Getting the credentials (Apple Developer account required):

1. developer.apple.com → Certificates, Identifiers & Profiles → **Identifiers** → register a **Maps ID**.
2. **Keys** → create a key with **MapKit JS** enabled, tick the Maps ID → download `AuthKey_XXXXXXXXXX.p8` (**one download only**).
3. Team ID is top-right in the portal; Key ID is on the key's detail page.

Install with the key read straight off disk, so it never lands in a values file:

```bash
helm upgrade --install photo-upload ./helm/photo-upload \
  --set appleMaps.enabled=true \
  --set appleMaps.teamId=ABCDE12345 \
  --set appleMaps.keyId=FGHIJ67890 \
  --set appleMaps.origin=https://picz2.oglimmer.com \
  --set-file appleMaps.privateKey=AuthKey_FGHIJ67890.p8
```

| Parameter                | Description                                                                                  | Default                          |
| ------------------------ | -------------------------------------------------------------------------------------------- | -------------------------------- |
| `appleMaps.enabled`      | Mint MapKit tokens and advertise the map filter                                              | `false`                          |
| `appleMaps.teamId`       | Apple Developer Team ID — the token's `iss`                                                  | `""`                             |
| `appleMaps.keyId`        | MapKit JS Key ID — the token header's `kid`                                                  | `""`                             |
| `appleMaps.privateKey`   | Body of the `.p8` file — **must** be overridden, ideally with `--set-file`                   | `""`                             |
| `appleMaps.origin`       | Origin the token is pinned to; blank omits the claim (a leaked token then works anywhere)    | `https://picz2.oglimmer.com`     |
| `appleMaps.ttlSeconds`   | Token lifetime; MapKit re-fetches on its own as expiry nears                                 | `1800`                           |

Verify after deploy:

```bash
curl -s https://picz2.oglimmer.com/api/capabilities | jq .maps      # {"enabled": true, "geocoding": true}
curl -s https://picz2.oglimmer.com/api/maps/token | cut -c1-40      # a JWT, not an error string
```

### Push notifications (APNs)

The iOS app is told about new photos and newly published albums over Apple Push. The api pod signs
each push with an Apple Developer key, so the feature is **off** until you supply one: with
`apns.enabled=false` the api logs one line at boot and drops every push. E-mail notifications are
unaffected either way.

The key used to be committed to the repo at `server/src/main/resources/AuthKey_XXXX.p8` and read
off the classpath, which baked it into every image and made rotation a rebuild. It is now supplied
exactly like the MapKit key — as the `.p8` body, from the chart's secret.

Getting the credentials (Apple Developer account required):

1. developer.apple.com → Certificates, Identifiers & Profiles → **Keys** → create a key with
   **Apple Push Notifications service (APNs)** enabled → download `AuthKey_XXXXXXXXXX.p8`
   (**one download only**).
2. Key ID is on the key's detail page; Team ID is top-right in the portal.
3. The topic is the app's bundle id, `com.oglimmer.photosync`.

Install with the key read straight off disk, so it never lands in a values file:

```bash
helm upgrade --install photo-upload ./helm/photo-upload \
  --reuse-values \
  --set apns.enabled=true \
  --set apns.keyId=289ZRKLFNQ \
  --set apns.teamId=SBFZ9G94BG \
  --set apns.topic=com.oglimmer.photosync \
  --set apns.production=true \
  --set-file apns.privateKey=AuthKey_289ZRKLFNQ.p8
```

**Set every field, including the ones with defaults.** `--reuse-values` bases the upgrade on the
*previous release's* values and does not pick up new defaults from the chart, so the first upgrade
that turns `apns` on gets `topic: ""` however good the default in `values.yaml` is. APNs rejects
every push without a topic, while the api still logs a cheerful "client initialized" — so the
template makes `apns.topic` `required` rather than letting that ship. If a later upgrade fails with
`apns.topic is required`, that is this same trap; pass the value again.

| Parameter          | Description                                                                    | Default                  |
| ------------------ | ------------------------------------------------------------------------------ | ------------------------ |
| `apns.enabled`     | Send pushes at all                                                             | `false`                  |
| `apns.privateKey`  | Body of the `.p8` file — **must** be overridden, ideally with `--set-file`      | `""`                     |
| `apns.keyId`       | APNs Key ID — the token header's `kid`                                         | `""`                     |
| `apns.teamId`      | Apple Developer Team ID — the token's `iss`                                    | `""`                     |
| `apns.topic`       | The app's bundle id                                                            | `com.oglimmer.photosync` |
| `apns.production`  | Must match the build on the phone: `false` is Apple's sandbox, which a **debug** build (`Zyncloud.entitlements`, `aps-environment: development`) registers against; `true` is what a TestFlight or App Store build needs (`Zyncloud.Release.entitlements`, `aps-environment: production`). One server can only talk to one of the two — with the wrong one Apple answers `BadDeviceToken` and drops the push | `false` |

Verify after deploy — one line, and which environment it picked:

```bash
kubectl logs deploy/photo-upload-backend | grep APNs
# APNs client initialized for PRODUCTION environment (keyId=289ZRKLFNQ)
```

That line only proves the key parsed. It says nothing about the topic, so check that too:

```bash
kubectl exec deploy/photo-upload-backend -- printenv | grep APNS_TOPIC
# APNS_TOPIC=com.oglimmer.photosync     <- empty here means every push is rejected
```

**Rotating the key** is now a secret edit plus a restart, with no image rebuild:

```bash
helm upgrade photo-upload ./helm/photo-upload --reuse-values \
  --set apns.keyId=NEWKEYID12 \
  --set-file apns.privateKey=AuthKey_NEWKEYID12.p8
kubectl rollout restart deploy/photo-upload-backend
```

For local development, point at the file instead of pasting a PEM into your shell. Both Apple
keys live gitignored at the repo root:

```bash
APNS_KEY_PATH=$PWD/AuthKey_289ZRKLFNQ.p8 ./mvnw spring-boot:run
```

### Reverse geocoding (place names on "by day & region")

The gallery's "📅 By day & region" grouping labels each region with a place name. The api pod
resolves those through the **Apple Maps Server API**, behind its own cache, at
`GET /api/geocode/reverse?loc=50.047,8.574&loc=…&lang=de`. It rides on `appleMaps.*` — same key,
same Team ID — and does nothing at all when `appleMaps.enabled=false`; the headings then show
coordinates.

A lookup stops at the first of four layers that answers: an in-memory map, the exact
`geocode_cache` row (V38, shared by every pod and surviving restarts), the nearest cached point
within `reuseRadiusMeters`, and finally Apple. Only the last one costs quota, and it is
single-flighted, so twenty visitors opening the same album at once produce one call.

| Parameter                                        | Description                                                                        | Default |
| ------------------------------------------------ | ---------------------------------------------------------------------------------- | ------- |
| `appleMaps.geocode.enabled`                      | Resolve place names at all; false ⇒ `maps.geocoding=false` and coordinates are shown | `true`  |
| `appleMaps.geocode.reuseRadiusMeters`            | A cached name this close is reused rather than asking Apple again                    | `300`   |
| `appleMaps.geocode.maxLookupsPerMinute`          | Pod-wide ceiling on calls that actually reach Apple — the quota guard                | `120`   |
| `appleMaps.geocode.maxRequestsPerMinutePerClient`| Per-IP ceiling on the endpoint itself (it is unauthenticated, like the map token)    | `60`    |
| `appleMaps.geocode.defaultLanguage`              | Language used when the caller asks for one we do not cache (en, de, fr, es, it)      | `en`    |

Every limit degrades to "no place name", never to an error, so a throttled or misconfigured
install shows coordinates instead of breaking the gallery.

```bash
# Should answer with a name; run it twice — the second is a cache hit and returns instantly.
curl -s 'https://picz2.oglimmer.com/api/geocode/reverse?loc=50.047,8.574&lang=de' | jq .

# How well the cache is doing, and how much quota is actually being spent:
curl -s https://picz2.oglimmer.com/actuator/prometheus | grep geocode_
```

Names are labelled town-first ("Banff"), falling back to a named area ("Banff National Park"), a
district, then `"State, Country"`. When the rule changes, `ReverseGeocodeService.LABEL_VERSION` is
bumped and every row below it re-resolves as people browse — no cleanup script, no cache flush.

`geocode_cache_total{layer="memory|database|nearby"}` counts the questions answered without Apple;
`geocode_lookup_total{result="resolved|empty|throttled"}` counts the ones that were not. In steady
state the lookup counter should be nearly flat.

A bad `.p8` does **not** fail the boot: the api pod logs `Apple Maps private key could not be parsed` and reports `maps.enabled=false`, because the rest of the gallery has no reason to go down over a map.

**Backfill.** Only assets processed after this feature shipped carry coordinates. Existing rows need a one-off sweep, which reads metadata only — no transcodes, no thumbnail regeneration:

```bash
# Repeat until "enqueued": 0
curl -X POST -H "Authorization: Bearer $TOKEN" \
  'https://picz2.oglimmer.com/api/admin/extract-gps?maxRows=500'
```

Assets whose original was already deleted by the retention sweep are skipped and can never be backfilled — the coordinates live only in the original, and no derivative carries them.

### Capture-offset backfill (required once, for "by day & region")

The gallery cuts day sections on the wall clock the camera saw, not the viewer's timezone —
otherwise an album shot in Toronto breaks its days six hours early for anyone browsing from Europe.
That needs `capture_utc_offset_seconds` (V40), which only assets processed after this feature
shipped carry. The existing capture-date sweep backfills it, metadata only:

```bash
# Repeat until "enqueued": 0
curl -X POST -H "Authorization: Bearer $TOKEN" \
  'https://picz2.oglimmer.com/api/admin/reextract-capture-dates?maxRows=500'
```

Two kinds of asset never get an offset and do not need one: videos whose only timestamp is the
zone-less mvhd atom, and assets whose original retention already purged. Both fall back to the
album's dominant offset, so a trip album still breaks its days in the right place. Until the sweep
has run, every album falls back that way — day sections are not *wrong*, they are just cut in the
viewer's timezone as before.

### Retention CronJob

Nightly sweep at the configured `schedule`. Three independent passes: aged-original purge, abandoned-TUS-upload cleanup, originals/ orphan detection. Each obeys the same `dryRun` and `maxRowsPerRun` knobs.

| Parameter                          | Description                                                                                       | Default       |
| ---------------------------------- | ------------------------------------------------------------------------------------------------- | ------------- |
| `retention.enabled`                | Render the CronJob                                                                                | `true`        |
| `retention.schedule`               | Cron expression                                                                                   | `17 3 * * *`  |
| `retention.originalDays`           | Originals older than this (days) are eligible for purge once `processing_status='DONE'`           | `7`           |
| `retention.tusUploadDays`          | Abandoned `tus-uploads/` objects older than this are deleted                                      | `7`           |
| `retention.orphanGraceHours`       | `originals/` keys with no DB row + older than this (hours) are deleted (post-finish-crash recovery) | `24`          |
| `retention.maxRowsPerRun`          | Per-pass cap (safety against misconfigured cutoff)                                                | `5000`        |
| `retention.dryRun`                 | Log eligible rows but skip the actual delete + DB update                                          | `false`       |
| `retention.successfulJobsHistoryLimit` | K8s Job retention                                                                              | `3`           |
| `retention.failedJobsHistoryLimit` | K8s Job retention                                                                                 | `3`           |
| `retention.startingDeadlineSeconds`| Skip catch-up firings beyond this gap                                                             | `600`         |
| `retention.ttlSecondsAfterFinished`| Pod artefacts vanish this long after the Job finishes                                             | `86400`       |

### Ingress

| Parameter             | Description                            | Default         |
| --------------------- | -------------------------------------- | --------------- |
| `ingress.enabled`     | Render the Ingress                     | `true`          |
| `ingress.annotations` | Annotations (cert-manager etc.)        | `cert-manager.io/cluster-issuer: oglimmer-com-dns` |
| `ingress.hosts`       | Host + path → backend mapping          | See `values.yaml` |
| `ingress.tls`         | TLS secret references                  | See `values.yaml` |

The default routing splits paths between three backends:
- `/files/*` → tusd (only when `tus.enabled=true`)
- `/api/*`, `/swagger-ui*`, `/v3/api-docs`, `/public/album` → backend
- `/` → frontend (catch-all, must be last)

### Monitoring

The standalone `prometheus` chart picks up Services annotated with `prometheus.io/scrape="true"` via its `kubernetes-service-endpoints` SD job. No `prometheus-operator` CRDs.

| Parameter                  | Description                                                | Default                  |
| -------------------------- | ---------------------------------------------------------- | ------------------------ |
| `monitoring.scrape.enabled`| Render the `*-metrics` Services with scrape annotations    | `true`                   |
| `monitoring.scrape.port`   | Backend management port                                    | `8081`                   |
| `monitoring.scrape.path`   | Metrics path                                               | `/actuator/prometheus`   |

Alert rules don't ship in this chart — see `templates/NOTES.txt` for the rule YAML to paste into the prometheus chart's `serverFiles.alerting_rules.yml`.

> **Known gap:** `/actuator/prometheus` currently returns 401 because `SecurityConfig` doesn't permit it. Alerts that depend on Spring metrics won't fire until that's fixed. Tracked in `upload-concept-plan.md` line 321.

### Security & pod-level

| Parameter                     | Description                              | Default                    |
| ----------------------------- | ---------------------------------------- | -------------------------- |
| `serviceAccount.create`       | Create a ServiceAccount                  | `true`                     |
| `podSecurityContext.fsGroup`  | Pod-level FSGroup                        | `10001`                    |
| `securityContext.runAsUser`   | Container UID (non-root enforced)        | `10001`                    |
| `securityContext.capabilities.drop` | Capabilities dropped               | `[ALL]`                    |
| `imagePullSecrets`            | Registry pull secrets                    | `[{ name: oglimmerregistrykey }]` |

### Resources controlled outside this chart

- **MinIO** itself — provisioned per-environment by the platform side. Chart only consumes it.
- **MariaDB** — same. Chart points at it via `database.external.*`.
- **Prometheus alert rules** — pasted into the prometheus chart's `serverFiles.alerting_rules.yml` (see `NOTES.txt`).
- **MinIO bucket lifecycle** — *not* used; the retention CronJob's TUS sweep is the GC mechanism.

## Secrets management

Inline `--set` is fine for dev, but it puts credentials in your shell history *and* helm release annotations. For anything beyond a laptop:

- **Sealed Secrets**: pre-encrypt the `Secret` and let the controller decrypt at apply time.
- **External Secrets Operator**: store in Vault / AWS SM / etc., reference in the cluster.
- **`--set-file`**: read from a gitignored file rather than the shell.

The chart's templates already use `secretKeyRef` for every credential — you just need to populate the source.

The four secrets that **must** be overridden:

| Path                          | What                                          |
| ----------------------------- | --------------------------------------------- |
| `objectStorage.accessKey`     | MinIO access key                              |
| `objectStorage.secretKey`     | MinIO secret key                              |
| `objectStorage.backendSecretKey` | AES key for user storage credentials (optional) |
| `database.external.password`  | MariaDB password                              |
| `tus.hookSecret`              | tusd → api hook URL path-secret (`openssl rand -hex 32`) |

## Operations

### Deploying a new backend image

```bash
# Build + push backend, restart api + worker (rolling update)
./oglimmer.sh build -s -v
```

`imagePullPolicy: Always` + restart picks up the new `:latest` digest. Same image runs in api / worker / retention; the next CronJob firing pulls automatically too.

### Scaling the worker

```bash
helm upgrade photo-upload ./helm/photo-upload --reuse-values --set worker.replicas=3
```

Each worker pod has `Semaphore(1)` — replica count is the parallelism knob. `SELECT … FOR UPDATE SKIP LOCKED` makes overlap safe.

### Manually firing a CronJob

```bash
kubectl create job --from=cronjob/photo-upload-retention photo-upload-retention-manual
```

Useful for retention dry-run validation or exercising the orphan / TUS sweeps before the next scheduled firing.

### Tuning retention

```bash
# Switch back to dry-run for a one-off audit
helm upgrade photo-upload ./helm/photo-upload --reuse-values --set retention.dryRun=true

# Bump the original-keep window from 7d to 30d
helm upgrade photo-upload ./helm/photo-upload --reuse-values --set retention.originalDays=30
```

### Health checks

| Pod         | Liveness                       | Readiness                                                                    |
| ----------- | ------------------------------ | ---------------------------------------------------------------------------- |
| `backend`   | `GET /actuator/health/liveness`| `GET /actuator/health/readiness` — flips DOWN when MinIO breaker is OPEN     |
| `worker`    | `GET /actuator/health/liveness`| `GET /actuator/health/readiness`                                             |
| `frontend`  | TCP                            | HTTP 200 on `/`                                                              |
| `tusd`      | TCP                            | HTTP 200 on `/files/`                                                        |

The MinIO circuit breaker is wired into `MinioHealthIndicator`: when it OPENs, K8s removes the api pod from the Service for the duration of the outage.

## Storage model

Every album names the storage its bytes live in (`albums.storage_backend_id`). By default that is
the MinIO configured above — the row `storage_backends` seeds with `system_default = TRUE`, which
deliberately holds no endpoint and no credentials and resolves `storage.s3.*` at runtime, so the
cluster secret is never copied into the database.

A user can register their own S3-compatible endpoint ("bring your own storage") and point new
albums at it. That needs `objectStorage.backendSecretKey` — a base64 AES key encrypting their
secret access keys. Leave it empty and the feature is simply off: every album uses the MinIO
above, and the API says so instead of failing at upload time. **Do not rotate the key in place**;
a new one makes every stored user credential unreadable and each user has to re-enter theirs.

### Per-user quota

What a user keeps on the MinIO above is capped — 100 MiB by default, from the
`users.storage_quota_bytes` column. There is no UI and no API for it; raise a specific account's
allowance with SQL:

```sql
UPDATE users SET storage_quota_bytes = 5368709120 WHERE email = 'someone@example.com';  -- 5 GiB
```

`0` refuses every further upload, which is a usable way to freeze an abusive account. An album on
a user's own storage is neither counted nor capped.

Every `/api/admin/*` route needs `ROLE_ADMIN` (D74). That role comes from the `users.is_admin`
column, which — like the quota — has no UI and no API. A fresh deploy has no admin until you name
one:

```sql
UPDATE users SET is_admin = TRUE WHERE email = 'you@example.com';
```

Any other account gets 403 on those routes, even with a valid login.
The same flag gates renaming the two gallery language names (`PUT /api/settings/languages/*`);
reading them stays public because the share page needs them.

Counted: originals, derivatives (thumb/medium/large/transcoded) and narration audio. **Not**
counted: anything under `tus-uploads/`, which is in flight and swept by retention either way — an
album on a user's own storage passes its bytes through that prefix, and charging for it would bill
transport as storage.

**Run once after upgrading to the chart version that ships V45:**

```bash
kubectl exec deploy/photo-upload-backend -- \
  curl -sS -u 'admin@example.com:PASSWORD' -X POST localhost:8080/api/admin/recalculate-derivative-bytes
```

Rows written before V45 have no recorded derivative size, so they meter as free until this reads
the real sizes out of the bucket. It is idempotent — only rows with an unknown size are touched.

Two consequences worth knowing before operating this:

- An album's storage is fixed at creation. There is no move; the API refuses the change.
- tusd always stages into the MinIO above, whatever the album's backend. Finishing an upload for
  an album on a user's own storage streams the bytes through the api pod once, so watch api
  egress rather than tusd's if that traffic ever matters.

The prefix layout below is the same in every backend:

| Prefix              | Contents                                              | Owner / writer                                |
| ------------------- | ----------------------------------------------------- | --------------------------------------------- |
| `originals/`        | Full-resolution upload (or post-HEIC-conversion JPEG) | api `storeFile` + `registerTusUpload`         |
| `derivatives/{id}/` | `thumb.jpg`, `medium.jpg`, `large.jpg`, `transcoded.mp4`, `video_thumb.jpg` | worker `processFile` / `regenerateThumbnails` / `rotateAndReprocess` |
| `audio/`            | Slideshow soundtracks (re-encoded)                    | api `SlideshowRecordingService`               |
| `tus-uploads/`      | tusd's per-upload staging objects                     | tusd; cleaned by post-finish hook + retention sweep |

The retention CronJob's three passes match `originals/%`, `tus-uploads/%`, and `originals/` orphan detection respectively. `derivatives/` is never swept (deterministic per-asset keys, deleted with the row).

## Troubleshooting

### Pods

```bash
kubectl get pods -l app.kubernetes.io/instance=photo-upload
kubectl describe pod <pod-name>
```

### Logs

```bash
# Backend (api)
kubectl logs -l app.kubernetes.io/component=backend --tail=200

# Worker (processing pipeline)
kubectl logs -l app.kubernetes.io/component=worker --tail=200

# tusd
kubectl logs -l app.kubernetes.io/component=tusd --tail=200

# Latest retention CronJob run
kubectl logs -l app.kubernetes.io/component=retention --tail=500
```

### Job queue inspection

```sql
-- Queue depth by status
SELECT status, COUNT(*) FROM processing_jobs GROUP BY status;

-- DEAD_LETTER inspection
SELECT id, asset_id, attempts, last_error, created_at
FROM processing_jobs
WHERE status='DEAD_LETTER'
ORDER BY created_at DESC LIMIT 20;
```

Or via the API: `GET /api/admin/dead-letter` (auth required).

### Image not updating after build

The retention CronJob's pod inherits the `:latest` tag at firing time. If you rebuilt mid-day, the *running* api / worker pods don't auto-restart — you need `kubectl rollout restart deployment/<name>` (which `oglimmer.sh build -s` does for you). The retention pod from the *previous* night will still show the *previous* digest until the next firing.

### MinIO unreachable

The api pod's `MinioHealthIndicator` flips readiness DOWN when the circuit breaker is OPEN; K8s removes it from the Service. New uploads return 503 with `Retry-After: 30` (`UploadBackpressureFilter` short-circuits before parsing the multipart body).

### TUS uploads landing as orphans

Symptoms: `originals/{stored_filename}` exists in MinIO but no `file_metadata` row. Cause: post-finish hook crashed between the S3 COPY and the row insert. The retention CronJob's third pass mops these up after `retention.orphanGraceHours` (default 24h). Manual cleanup before then: `mc rm minio/photo-upload/originals/{stored_filename}`.

## Upgrading the chart

```bash
helm upgrade photo-upload ./helm/photo-upload --reset-then-reuse-values \
  --set objectStorage.accessKey=… \
  --set objectStorage.secretKey=… \
  --set database.external.password=… \
  --set tus.hookSecret=…
```

`--reset-then-reuse-values` reads the new chart's defaults but lets the explicit `--set` flags override — safer than plain `--reuse-values` when chart values have been added or renamed between versions.

## Uninstall

```bash
helm uninstall photo-upload
```

The chart no longer manages a PVC (default `backend.persistence.enabled=false`), so uninstall is clean. If you previously enabled persistence and the PV has `reclaimPolicy=Retain`, you'll also need:

```bash
kubectl delete pv <pv-name>                           # frees Longhorn binding
kubectl -n longhorn-system delete volume <pv-name>    # actually frees the disk
```
