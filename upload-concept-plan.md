# Implementation Plan: Closing Architectural Gaps

Companion to `upload-concept.txt`. Tracks the work needed to bring the
status quo in line with the concept document.

Status legend (update as work lands):
- [ ] not started
- [~] in progress
- [x] done

Last reviewed: 2026-04-27 (Gap 1 implementation landed)

---

## Gap inventory (priority order, agreed with user)

1. Persistent jobs table with leases (replace in-memory `ThreadPoolTaskExecutor` queue).
2. Split worker into its own Deployment (currently co-located with upload pod).
3. TUS resumable uploads (currently single multipart POST).
4. Retention CronJob + storage alert (originals kept indefinitely).
5. libvips for image thumbnails (currently ImageMagick).
6. Explicit processing status field on `FileMetadata` (PENDING/PROCESSING/DONE/FAILED).
7. Prometheus queue-depth gauge.

---

## Critical path & sequencing

```
Phase 0  ─ Gap 6 (status field, additive migration, no contract change)
            Gap 5 (libvips swap, internal only)
            Gap 4-prep (PVC alert + retention CronJob skeleton)
                                │
                                ▼
Phase 1  ─ Gap 1 (jobs table + lease-based dispatcher, still in same JVM)
                                │
                                ▼
Phase 2  ─ Gap 7 (Prometheus gauges over the new jobs table)
                                │
                                ▼
Phase 3  ─ Gap 2a (introduce MinIO; both reads + writes from upload pod)
                                │
                                ▼
Phase 4  ─ Gap 2b (split worker into separate Deployment, sharing only DB + MinIO)
                                │
                                ▼
Phase 5  ─ Gap 3 (TUS resumable uploads via tusd Deployment with S3 backend)
                                │
                                ▼
Phase 6  ─ Gap 4-finish (retention CronJob now sweeps MinIO + DB consistently)
```

### Parallelisable
- Gap 6 and Gap 5 are independent; ship in any order in Phase 0.
- Gap 7 metric scaffolding can be drafted alongside Gap 1.
- Gap 4's PVC alert is independent of everything; ship anytime.

### Why this order
1. Status field (6) is additive and removes ambiguity for every downstream phase.
2. libvips (5) reduces memory pressure *before* we add load with the new dispatcher.
3. Jobs table (1) replaces the in-memory queue but stays in the same process — isolates "introduce a queue" risk from "split deployments" risk.
4. Object storage (2a) before splitting (2b): both pods must agree on the storage boundary first.
5. TUS (3) last because it requires the upload pod to be cheap (only stream → MinIO → write job row); that is only true after the worker split.

---

## Decision points (need sign-off before coding)

| #   | Decision                                       | Recommended                                                                                                          | Status |
| --- | ---------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ------ |
| D1  | Status enum values                             | `INGESTED / QUEUED / PROCESSING / DONE / FAILED / DEAD_LETTER` — richer set keeps reprocessing diagnosable.          | accepted |
| D2  | Backfill strategy for existing rows            | V30: rows with any derivative → `DONE`; else `FAILED`. V31: re-enqueue every FAILED row as QUEUED.                   | accepted |
| D3  | Jobs table key relationship                    | FK `asset_id → file_metadata.id`. Single-purpose queue, not infra.                                                   | accepted |
| D4  | Job granularity                                | One row per asset, fixed pipeline. No sub-step rows until reprocessing demands them.                                 | accepted |
| D5  | Lease duration                                 | 15 min default, configurable via `jobs.lease.seconds`.                                                               | accepted |
| D6  | Poll interval                                  | 2 s, configurable via `jobs.poll.interval-ms`.                                                                       | accepted |
| D7  | TUS implementation                             | **tusd Deployment** with S3 backend writing directly to MinIO. Avoids JVM heap; tusd's state machine is mature.      | open   |
| D8  | Object storage                                 | **MinIO**, single replica on Longhorn PVC.                                                                           | open   |
| D9  | MinIO deploy shape                             | Hand-rolled Deployment (single Pod, single PVC). Official chart is over-engineered for one node.                     | open   |
| D10 | Existing-data migration to MinIO               | Lazy + one-shot CommandLineRunner (idempotent: skip if HEAD succeeds). No maintenance window.                        | open   |
| D11 | iOS handling of HTTP 202                       | Treat 202 like 200 for "don't re-upload" bookkeeping; surface "Processing…" status in gallery UI optionally.         | open   |
| D12 | TUS rollout to iOS                             | Coexistence: `/api/upload` stays for old clients; new clients prefer TUS based on `GET /api/capabilities`.           | open   |
| D13 | Worker concurrency                             | `Semaphore(1)` per worker pod. Add replicas if needed; do not oversubscribe ImageMagick/ffmpeg threads.              | accepted |
| D14 | libvips refactor shape                         | Split into `VipsThumbnailService` (images), `HeicConversionService` (HEIC only), `FfmpegService` (video).            | open   |
| D15 | Dead-letter behaviour                          | Move to `DEAD_LETTER` after `max_attempts=3`, keep original blob. `GET /api/admin/dead-letter` exposes them; UI deferred. | accepted |

---

## Gap 6 — Explicit processing status field (Phase 0)

- [ ] Migration `V30__add_processing_status_to_file_metadata.sql`: adds `processing_status`, `processing_attempts`, `processing_error`, `processing_completed_at`. Backfill `DONE` where any derivative exists, else `FAILED`. Index on status.
- [ ] Entity: `FileMetadata` gains a `ProcessingStatus` enum (`@Enumerated(STRING)`).
- [ ] `FileStorageService.storeFile`: set `INGESTED` before save (becomes `QUEUED` once Gap 1 lands).
- [ ] `FileProcessingService.processFile`: transition `PROCESSING → DONE/FAILED`; increment attempts on error.
- [ ] `UploadController.uploadFile`: return `202 Accepted` with `processingStatus` in body.
- [ ] New `GET /api/assets/{id}/status` for clients that want to poll.
- [ ] iOS: optional follow-up to render the status in the gallery (no compatibility break — `Uploader.urlSession` already accepts the full `2xx` range).

### Testing
- [ ] Migration smoke test against a prod-snapshot DB.
- [ ] Status-transition unit tests.
- [ ] Integration test: upload a file and assert `INGESTED → DONE`.

### Risk / rollback
200 → 202 is a contract change. Web frontend must be checked. Rollback by reverting the controller alone (DB columns stay).

---

## Gap 5 — libvips for image thumbnails (Phase 0)

- [ ] Refactor `ThumbnailService` into `VipsThumbnailService` + `HeicConversionService` + `FfmpegService` (D14).
  - `VipsThumbnailService`: `vipsthumbnail src --size NxN -o thumb_%s.jpg[Q=Q]`, three calls (one per size). Shrink-on-load → memory bounded by output, not input.
  - `HeicConversionService`: keeps existing `convert` (libheif inside ImageMagick is the most reliable HEIC decoder).
  - `FfmpegService`: wraps `transcodeVideo`, `generateVideoThumbnail`, `extractVideoCreationDate`. Adds explicit `process.waitFor(15, MINUTES)` + `destroyForcibly()` on timeout — current code has no timeout.
- [ ] `Dockerfile`: install `libvips-tools`.
- [ ] Feature flag: `file.upload.thumbnailer=vips|magick` for the first release so we can flip back.

### Testing
- [ ] Golden-file thumbnails for JPEG / 50MP JPEG / PNG / animated GIF / EXIF-rotated input.
- [ ] RSS comparison via `jcmd VM.native_memory summary` before/after.

### Risk / rollback
vips handles unusual color profiles slightly differently. Flag-gated rollback.

---

## Gap 4-prep — PVC + MinIO alert (Phase 0, independent)

- [ ] `prometheusrule-storage.yaml`: alert when any photo-upload PVC is `> 80%` for 10 min. Routed via existing email/Alertmanager.

---

## Gap 1 — Persistent jobs table with leases (Phase 1)

- [x] Migration `V31__create_processing_jobs.sql`: `processing_jobs` table with `(id, asset_id, status, attempts, max_attempts, leased_until, leased_by, last_error, created_at, started_at, finished_at)`, FK to `file_metadata` with `ON DELETE CASCADE`, composite index `(status, leased_until)`. Backfill enqueues every row left FAILED by V30 and resets their `processing_status` to QUEUED.
- [x] `ProcessingJob` entity, `ProcessingJobRepository` with native `SELECT ... FOR UPDATE SKIP LOCKED` for atomic lease acquisition.
- [x] `JobDispatcher` with `@Scheduled(fixedDelay=2000)`: acquires `Semaphore(1)` permit, leases a row in one TX (`status='PROCESSING'`, `leased_until=NOW()+15min`), runs `FileProcessingService.processFile` synchronously, mirrors the asset's resulting `ProcessingStatus` onto the job row, marking `DONE` / `FAILED` (→ `DEAD_LETTER` after max attempts).
- [x] `JobEnqueueService.enqueue(assetId)` called by `FileStorageService.storeFile` *inside the same TX as the metadata insert* → atomic.
- [x] `FileProcessingService.processFile`: synchronous core; `processFileAsync` thin `@Async` wrapper kept only for the legacy flag-off path.
- [x] `UploadBackpressureFilter`: switched to a **cached gauge** (`JobQueueDepthService`) of `(QUEUED + PROCESSING)` jobs, refreshed every 1 s via `@Scheduled`. Threshold stays at 200. Falls back to executor-queue check when the dispatcher is disabled.
- [x] Config: `jobs.poll.interval-ms`, `jobs.lease.seconds`, `jobs.max-attempts`, `jobs.backpressure.queue-depth-threshold`, `jobs.backpressure.refresh-ms`.
- [x] Feature flag `jobs.dispatcher.enabled` so we can fall back to old `@Async` for one release.
- [x] D15 admin surface: `GET /api/admin/dead-letter` (re-enqueue UI deferred per the decision).
- [~] Pre-deploy: `ProcessingJobLeaseTest` (Testcontainers, MariaDB 11.8) covers SKIP LOCKED non-duplication, expired-lease recovery, active-lease respect, V31 backfill. Gated by `-Drun.testcontainers=true` because the local Docker Desktop install returns stub responses to docker-java; IT runs cleanly on a daemon without that filter (CI / fresh Docker).

### Testing
- [ ] Testcontainers-MariaDB integration: two competing threads acquire from the same row → exactly one wins.
- [ ] Crash-recovery: abort mid-job, advance clock past lease, assert re-acquisition.
- [ ] Load: 500 fake assets, no duplicate processing.

### Risk / rollback
`FOR UPDATE SKIP LOCKED` requires MariaDB ≥ 10.6. **Verify the live version before merging.** If older, fall back to advisory lock or `FOR UPDATE NOWAIT` with retry. Rollback by flipping the feature flag.

---

## Gap 7 — Prometheus queue-depth gauge (Phase 2)

- [x] `JobMetricsConfig` registers one Micrometer `Gauge` per `JobStatus` value, all sharing the metric name `photoupload.jobs.queued` with a `status` tag (renders as `photoupload_jobs_queued{status=...}` in Prometheus).
- [x] One scheduled `GROUP BY status` query refreshes a `volatile EnumMap` snapshot in `JobQueueDepthService`. Both the gauge suppliers and the backpressure filter read from that snapshot — no per-scrape DB cost, no Caffeine needed.
- [x] `prometheus` added to actuator exposure; `micrometer-registry-prometheus` on the classpath.
- [x] Helm: `PodMonitor` (`podmonitor-backend.yaml`) targeting the management port (8081) so prometheus-operator scrapes `/actuator/prometheus`. Gated by `monitoring.jobsMetrics.enabled`.
- [x] Helm: `prometheusrule-jobs.yaml` with two alerts, gated by `monitoring.jobsAlert.enabled`:
  - `photoupload_jobs_queued{status="QUEUED"} > 200 for 5m` → warning.
  - `photoupload_jobs_queued{status="DEAD_LETTER"} > 0 for 1m` → critical (potential data loss).

### Risk
Management port (8081) is already internal-only; no exposure concern.

---

## Gap 2a — Introduce MinIO (Phase 3)

- [ ] Helm: hand-rolled `deployment-minio.yaml` (single replica, 512 Mi limit), `service-minio.yaml` (ports 9000/9001), `persistentvolumeclaim-minio.yaml` (30 Gi Longhorn), `secret-minio.yaml` for credentials.
- [ ] Add `software.amazon.awssdk:s3` (more portable than `io.minio`).
- [ ] New `ObjectStorageService` over `S3Client`: `putObject(key, file, mime)` via `RequestBody.fromFile` (never reads into heap), `getObject`, `deleteObject`, `presignGet`.
- [ ] `FileStorageService.storeFile`: stream to local temp → checksum → `putObject("originals/{uuid}", tempFile)` → delete temp → save row with `filePath = "originals/{uuid}"`.
- [ ] `FileProcessingService.processFile`: download original to local temp dir → vips/ffmpeg/magick (unchanged) → upload derivatives to `derivatives/{assetId}/{thumb,medium,large}.jpg` and `derivatives/{assetId}/transcoded.mp4` → `finally { deleteTempDir }`.
- [ ] File-serve controllers: prefer presigned URLs; fall back to streamed `getObject` when auth requires it.
- [ ] `FilesystemToS3Migrator` `CommandLineRunner` gated by `migration.fs-to-s3.enabled` (D10). Idempotent: HEAD-check before upload. Run as a one-off Job over a low-traffic window.

### Testing
- [ ] `FileStorageServiceIT` against a MinIO Testcontainer.
- [ ] e2e gallery + slideshow + public-token flows.
- [ ] Backwards-compat: rows with absolute paths still serve correctly during the migration window.

### Risk
MinIO single-replica is an SPOF for new writes. Acceptable for single-node K3s; underlying Longhorn PVC is durable.

---

## Gap 2b — Worker Deployment split (Phase 4)

- [ ] Spring profiles: `api` and `worker`. Same JAR, different `SPRING_PROFILES_ACTIVE`. `JobDispatcher`, `FileProcessingService`, `ThumbnailService` only loaded under `worker`. `UploadController` only under `api`.
- [ ] New Helm `deployment-worker.yaml` — same image, `SPRING_PROFILES_ACTIVE=worker`, no Service/Ingress. Resources `limits: { cpu: 4000m, memory: 2Gi }`, `requests: { memory: 1Gi }`. JVM `-Xmx512m -XX:MaxRAMPercentage=35.0`. `emptyDir` `/tmp/worker` for the encode area.
- [ ] API pod slimmed: `limits.memory: 1Gi`, JVM `-Xmx512m`. No more ImageMagick budget needed.
- [ ] Roll-out: deploy worker at `replicas: 0` first (validate manifests). Then `replicas: 1` + `jobs.dispatcher.enabled=false` on API. Watch metrics for 24 h. Then ship the cleanup release that removes the dispatcher code path from the `api` profile.
- [ ] Add a circuit breaker on the upload pod that returns 503 when MinIO is unreachable; iOS already handles 503 gracefully.

### Testing
- [ ] Chaos: `kubectl scale deployment worker --replicas=0` mid-processing → lease expires → resumes when worker comes back.
- [ ] `--replicas=2` → `SKIP LOCKED` ensures no duplicate processing.

---

## Gap 3 — TUS resumable uploads (Phase 5)

### Architecture (D7)
tusd as a separate Deployment writing **directly to MinIO** via the S3 backend. On upload completion, tusd POSTs to a hook URL on the API → API creates the `file_metadata` row + `processing_jobs` row.

### Server
- [ ] Helm: `deployment-tusd.yaml` (image `tusproject/tusd:v2`, args `-s3-bucket -s3-endpoint -hooks-http=http://photo-upload-api:8080/api/tus/hooks -behind-proxy`).
- [ ] `service-tusd.yaml` ClusterIP:1080.
- [ ] Ingress: route `/files/` to tusd; keep `/api/upload` for legacy.
- [ ] `TusHookController.POST /api/tus/hooks`:
  - `pre-create`: validate Authorization, check `Upload-Metadata` for `contentId` → reject duplicates.
  - `post-finish`: file already in MinIO → insert `file_metadata` row at the existing object key, insert `processing_jobs` row.
  - HMAC-verify hook authenticity using a shared secret.
- [ ] `GET /api/capabilities` returns `{"tus": true, "tusEndpoint": "/files/", "multipart": true}`.

### iOS
- [ ] New `TusUploader.swift`. Foreground `POST /files/` to get `Location: /files/{id}` → persist URL in `UploadStore` (new `tusUploadUrl` field). Background `URLSession.uploadTask(with:fromFile:)` against `Location` with `PATCH` + `Tus-Resumable: 1.0.0` + `Content-Type: application/offset+octet-stream`. PATCH is fully self-contained → background URLSession-safe. Creation POST is the only foreground step, and it is tiny.
- [ ] On launch with pending TUS uploads: `HEAD /files/{id}` to discover current `Upload-Offset`, then resume.
- [ ] `Uploader.swift` keeps multipart path. `SyncCoordinator` selects path based on cached `/api/capabilities` result.

### Roll-out
TestFlight build with `Settings.useTus` flag, default off in first release. After three months, deprecate `/api/upload` (return 410 Gone with redirect message).

### Testing
- [ ] Airplane-mode toggle mid-upload.
- [ ] Force-quit + relaunch mid-upload.
- [ ] `kubectl delete pod -l app=tusd` mid-upload (tusd persists state in S3 → resumes after restart).

### Risk
Stale TUS uploads leave dangling MinIO objects. Set `tusd -expire-after=168h`; retention CronJob (Gap 4) sweeps.

---

## Gap 4-finish — Retention CronJob (Phase 6)

- [ ] `cronjob-retention.yaml`: nightly at `03:17`, `concurrencyPolicy: Forbid`. Runs the same backend image with `SPRING_PROFILES_ACTIVE=retention`.
- [ ] New `RetentionRunner` `CommandLineRunner` finds rows where `status='DONE'` AND `uploaded_at < NOW() - 7d` AND all derivatives exist → deletes original from MinIO, sets `filePath = NULL`. Configurable `retention.original-days`.
- [ ] File-serve adjustment: serve the largest available derivative when `filePath` is NULL; return 410 Gone for explicit `?size=original` requests on purged assets.
- [ ] Block rotation in the UI for assets with `filePath=NULL` (rotation needs the original).

### Testing
- [ ] Shorten retention to 0 in staging, run the CronJob manually, verify originals are gone but gallery still serves derivatives.

### Risk
Irreversible deletion. Hence the conservative 7-day default and the alert-first phase.

---

## Cross-cutting risks

- **Pi memory pressure during transition**: doing Gap 5 (libvips → less RAM) *before* Gap 1 leaves headroom for running the old `@Async` queue + new dispatcher in parallel during cutover.
- **Migration window for existing data**: thousands of rows × 30 Gi PVC → MinIO takes tens of minutes on a Pi. Idempotent and resumable; run during low traffic.
- **Hibernate `ddl-auto: validate`**: every entity field must match a migrated column or app fails to start. Verify entity-vs-migration before each deploy.
- **Single-node K3s availability**: switch the upload pod's deploy strategy to `Recreate` during the multipart-tmp-dir transition window; back to `RollingUpdate` once writes go to MinIO only.

---

## Cross-cutting test plan

| Layer        | Tooling                                                                    |
| ------------ | -------------------------------------------------------------------------- |
| Unit         | JUnit 5 + Mockito for new services                                         |
| Integration  | Spring Boot Test + Testcontainers (MariaDB 11, MinIO, tusd)                |
| iOS unit     | XCTest with mocked URLSession                                              |
| iOS manual   | Airplane-mode toggle, force-quit, OS-reboot-during-upload                  |
| E2E          | Existing web flow extended with admin-status check (`GET /api/assets/{id}/status` reaches DONE) |
| Load         | K6 script: 200 concurrent uploads of 50 MB JPEGs against staging Pi        |
| Chaos        | `kubectl delete pod` mid-processing (Gap 1, Gap 2b) and mid-upload (Gap 3) |
