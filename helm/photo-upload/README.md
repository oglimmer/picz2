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
| `objectStorage.enabled`      | When true, uploads / derivatives / serves go through S3                    | `true`                                   |
| `objectStorage.endpoint`     | S3 endpoint URL                                                            | `http://minio.minio.svc.cluster.local:9000` |
| `objectStorage.bucket`       | Bucket name (auto-created on startup if missing)                           | `photo-upload`                           |
| `objectStorage.region`       | S3 region (MinIO ignores this but the SDK requires it)                     | `us-east-1`                              |
| `objectStorage.accessKey`    | Access key — **must** be overridden                                        | `""`                                     |
| `objectStorage.secretKey`    | Secret key — **must** be overridden                                        | `""`                                     |

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

All bytes live in MinIO under one bucket, partitioned by prefix:

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
