# Implementation Plan: Closing Architectural Gaps

Companion to `upload-concept.txt`. Tracks the work needed to bring the
status quo in line with the concept document.

Status legend (update as work lands):
- [ ] not started
- [~] in progress
- [x] done

Last reviewed: 2026-05-03 (iOS `ShareExtension` and standalone macOS `UploadExtension/` both migrated to TUS — their `Shared/UploadService.swift` files now do `POST /files/` + `PATCH {Location}` with `Upload-Metadata` carrying `filename`/`filetype`/`albumId`/`auth`; legacy multipart code paths removed (also dropped `AppConfiguration.uploadEndpoint` on iOS). `contentId` is intentionally omitted on both so re-shares create new assets, matching previous `/api/upload` behaviour. Two of four blockers for retiring `/api/upload` now closed; remaining: web multipart fallback in `useUpload.ts`, and the main iOS app's `Settings.useTus` toggle (legacy `Uploader.swift` still chosen when `useTus=false`). Earlier: Backend PVC + underlying Longhorn PV retired — `backend.persistence.enabled=false`, helm upgrade dropped the PVC, explicit `kubectl delete pv` + `delete volume` chained the cleanup through Longhorn since reclaimPolicy was Retain. 30 GiB freed; closes Gap 8 follow-ups. Earlier: Phase 4.5 closed — `JobType.REGEN_THUMBNAILS` + `FileProcessingService.regenerateThumbnails` + `POST /api/admin/regen-missing-thumbnails` shipped, mirroring the ROTATE_LEFT pattern; the two video-path admin methods are deliberately not rebuilt because deterministic S3 keys make path-drift impossible in the new architecture. Earlier today: retention is now live-deleting: 2026-05-02 nightly dry-run logged eligible=2408 / TUS=0 / 0 failures cleanly, so `retention.dryRun` flipped to `false` in `values.yaml`. Same commit added a third pass — `RetentionService.runOriginalsOrphanCleanup` — that set-diffs `originals/` listing against `FileMetadataRepository.findAllOriginalsKeys` and deletes keys older than `retention.orphan-grace-hours` (default 24) with no live row. Wired into `RetentionRunner`; `RETENTION_ORPHAN_GRACE_HOURS` env added to `cronjob-retention.yaml`. Closes the deferred TUS post-finish-crash recovery follow-up. Also reverted the rotate-after-purge prohibition: `FileProcessingService.rotateAndReprocess` now falls back to the largest available derivative (output is LARGE=2400px-bounded regardless of source resolution — pixel-equivalent to post-purge browsing), so `rotateImageLeft` no longer 410s on null `filePath` and `GalleryItem.vue` no longer hides the button. Purged assets stay purged: rotation skips the writeback to `originals/` when the original is gone. Earlier 2026-05-01: Phase 6 / Gap 4-finish landed in code: V33 makes `file_path` nullable, `RetentionService` + `RetentionRunner` (one-shot CommandLineRunner under the new `Profiles.RETENTION` profile) sweep DONE rows older than `retention.original-days` and DELETE the S3 original. Helm `cronjob-retention.yaml` runs nightly at 03:17 with `concurrencyPolicy: Forbid`. File-serve falls back to the largest derivative when the original is purged; explicit `?size=original` returns 410 via the new `ResourceGoneException`. Rotate is blocked at the API (also 410) and the rotate button is hidden in `GalleryItem.vue` via the new `originalAvailable` flag on `FileInfo`. Earlier 2026-04-30: Phase 4e R3 cleanup landed; legacy `@Async`/`INGESTED`/`jobs.dispatcher.enabled` and the deferred admin methods were removed.)

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
| D7  | TUS implementation                             | **tusd Deployment** with S3 backend writing directly to MinIO. Avoids JVM heap; tusd's state machine is mature.      | accepted |
| D8  | Object storage                                 | **MinIO**, single replica on Longhorn PVC.                                                                           | open   |
| D9  | MinIO deploy shape                             | Hand-rolled Deployment (single Pod, single PVC). Official chart is over-engineered for one node.                     | open   |
| D10 | Existing-data migration to MinIO               | Lazy + one-shot CommandLineRunner (idempotent: skip if HEAD succeeds). No maintenance window.                        | open   |
| D11 | iOS handling of HTTP 202                       | Treat 202 like 200 for "don't re-upload" bookkeeping; surface "Processing…" status in gallery UI optionally.         | accepted |
| D12 | TUS rollout to iOS                             | Coexistence: `/api/upload` stays for old clients; new clients prefer TUS based on `GET /api/capabilities`.           | accepted |
| D13 | Worker concurrency                             | `Semaphore(1)` per worker pod. Add replicas if needed; do not oversubscribe ImageMagick/ffmpeg threads.              | accepted |
| D14 | libvips refactor shape                         | Split into `VipsThumbnailService` (images), `HeicConversionService` (HEIC only), `FfmpegService` (video).            | open   |
| D15 | Dead-letter behaviour                          | Move to `DEAD_LETTER` after `max_attempts=3`, keep original blob. `GET /api/admin/dead-letter` exposes them; UI deferred. | accepted |
| D16 | Circuit-breaker library (Phase 4)              | Resilience4j with `resilience4j-spring-boot3`. Hand-rolled volatile-flag reinvents half of it; we already have actuator + Micrometer.  | accepted |
| D17 | Rotate / admin-thumbs fate after split         | Leave non-functional for one release; admin endpoints throw 503 on api profile until a Phase 4.5 worker-job rewrite. Rare ops cost.   | accepted |
| D18 | Audio reencode locality                        | Stays on api pod (`AudioReencodingService` not `@Profile`-gated). Audio is short and infrequent; no `processing_jobs` row exists.     | accepted |
| D19 | Worker HTTP listener                           | `server.port=-1` in `application-worker.yml`; only management:8081 active. Keep main port off entirely.                              | accepted |
| D20 | Controller profile-gating shape                | Class-level `@Profile("api")` on each controller; grep-able. Avoid `@ComponentScan` excludes.                                          | accepted |
| D21 | Legacy `@Async` cleanup release                | Bundle the removal in R3 (post-soak), not R2. Keeps R2 diff focused on deploy-shape change.                                            | accepted |
| D22 | Worker default replicas                        | 1. Each pod has `Semaphore(1)`, so scale-out gives parallelism but isn't required day-1 on the single-node Pi cluster.                | accepted |
| D23 | Per-job-type discriminator                     | Add `processing_jobs.job_type` (V32) with `JobType.{PROCESS,ROTATE_LEFT}` so admin operations reuse the lease/retry/dead-letter machinery instead of building a parallel queue. Revisits **D4** intentionally — the "single-purpose queue" stance held while there was only one job type. | accepted |
| D24 | tusd S3 key namespace                          | tusd writes to `tus-uploads/{uuid}`; `post-finish` hook S3-COPYs to `originals/{stored_filename}` then DELETEs the tusd object. COPY is server-side in MinIO; bytes never leave MinIO. | accepted |
| D25 | Why COPY rather than heterogeneous keys        | Keeps the `originals/%` invariant that retention (Phase 6), `derivatives/{assetId}/...` paths, and the legacy multipart path all already depend on. One scheme, one sweep rule. | accepted |
| D26 | Auth on TUS endpoint                           | Bearer token in `Upload-Metadata` (key `auth`), validated in `pre-create`. iOS background URLSession can't carry cookies reliably, so the token is the only sane channel. | accepted |
| D27 | Hook-channel authenticity                      | **Amended from the original HMAC sketch** — stock tusd cannot sign hook bodies, only forward client headers, so HMAC was infeasible without a custom shim. Substitute: shared secret embedded in the tusd→api hooks URL path: `http://photo-upload-backend:8080/api/tus/hooks/$(TUS_HOOK_SECRET)`. Controller validates the path-secret with constant-time compare. Cluster-internal only; not exposed via Ingress. Functionally equivalent defence-in-depth against accidental cross-namespace calls. | accepted |
| D28 | Backpressure on TUS                            | Reject in `pre-create` when `JobQueueDepthService.depth > jobs.backpressure.queue-depth-threshold`. Returns 503 → tusd surfaces 5xx → client backs off. tusd never starts buffering bytes for a doomed upload. | accepted |
| D29 | tusd replicas                                  | 1 (single-node Pi). tusd is stateless once `info.json` is in S3.                                                                                                                                                                                                                            | accepted |
| D30 | Duplicate detection in pre-create              | `Upload-Metadata.contentId` (sha256 from client) checked against `file_metadata` exactly like the multipart path. 200 if novel, 409 if dupe. Avoids spending S3 storage on dupe uploads.                                                                                                    | accepted |
| D31 | Existing `UploadBackpressureFilter` fate       | Stays in place for `/api/upload` legacy. TUS gets its own `pre-create` check (D28). Two paths, two filters, same source of truth (`JobQueueDepthService`).                                                                                                                                  | accepted |

---

## Gap 6 — Explicit processing status field (Phase 0)

- [x] Migration `V30__add_processing_status_to_file_metadata.sql`: adds `processing_status`, `processing_attempts`, `processing_error`, `processing_completed_at`. Backfill `DONE` where any derivative exists, else `FAILED`. Index on status.
- [x] Entity: `FileMetadata` gains a `ProcessingStatus` enum (`@Enumerated(STRING)`).
- [x] `FileStorageService.storeFile`: sets `QUEUED` (dispatcher enabled) / `INGESTED` (legacy) before save.
- [x] `FileProcessingService.processFile`: transitions `PROCESSING → DONE/FAILED`; increments attempts on error.
- [x] `UploadController.uploadFile`: returns `202 Accepted` with `processingStatus` in body.
- [x] `AssetStatusController` exposes `GET /api/assets/{id}/status`.
- [ ] iOS: optional follow-up to render the status in the gallery (no compatibility break — `Uploader.urlSession` already accepts the full `2xx` range).

### Testing
- [ ] Migration smoke test against a prod-snapshot DB.
- [ ] Status-transition unit tests.
- [ ] Integration test: upload a file and assert `INGESTED → DONE`.

### Risk / rollback
200 → 202 is a contract change. Web frontend must be checked. Rollback by reverting the controller alone (DB columns stay).

---

## Gap 5 — libvips for image thumbnails (Phase 0)

- [x] Refactor `ThumbnailService` into `VipsThumbnailService` + `HeicConversionService` + `FfmpegService` (D14). All three classes shipped; `ThumbnailService.generateAllThumbnails` dispatches to vips by default.
- [x] `Dockerfile`: installs `libvips-tools` (and a hand-built libheif/ImageMagick chain for the HEIC fallback).
- [x] Feature flag: `file.upload.thumbnailer=vips|magick`. Default `VIPS` (set in `FileStorageProperties.Thumbnailer`).

### Testing
- [ ] Golden-file thumbnails for JPEG / 50MP JPEG / PNG / animated GIF / EXIF-rotated input.
- [ ] RSS comparison via `jcmd VM.native_memory summary` before/after.

### Risk / rollback
vips handles unusual color profiles slightly differently. Flag-gated rollback.

---

## Gap 4-prep — PVC + MinIO alert (Phase 0, independent)

- [x] Alert rule body authored. **Substitution**: the cluster runs the standalone `prometheus` chart, *not* `prometheus-operator`, so the original `prometheusrule-storage.yaml` template was removed. The rule YAML now lives in `NOTES.txt` for one-time paste into the prometheus chart's `serverFiles.alerting_rules.yml`. Functionally equivalent; ownership boundary is the prometheus release rather than the photo-upload release.

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
- [x] Helm: scrape discovery via annotation-based mechanism (cluster has standalone `prometheus`, no operator). A headless `*-metrics` Service with `prometheus.io/scrape="true"`, `prometheus.io/port="8081"`, `prometheus.io/path="/actuator/prometheus"` is picked up by the existing `kubernetes-service-endpoints` SD job. (Replaces the original `PodMonitor` template, which the operator-less cluster could not reconcile.)
- [x] Helm: alert-rule YAML for jobs (`PhotoUploadJobsBacklog`, `PhotoUploadJobsDeadLetter`) emitted via `NOTES.txt` for paste into the prometheus chart's `serverFiles.alerting_rules.yml`. (Replaces the original `prometheusrule-jobs.yaml` template, same reason.)

### Risk
Management port (8081) is already internal-only; no exposure concern.

---

## Gap 2a — Introduce MinIO (Phase 3)

MinIO already exists in-cluster at `minio.minio.svc.cluster.local:9000`, so the Helm work for MinIO itself (Deployment / Service / PVC) is owned by the platform side. The plan below tracks only the application changes.

### Phase 3a — Foundation (landed)

- [x] Skip `deployment-minio.yaml` / `service-minio.yaml` / `persistentvolumeclaim-minio.yaml` — MinIO is platform-managed.
- [x] `software.amazon.awssdk:s3` + `apache-client` via the AWS SDK BOM.
- [x] `ObjectStorageProperties`, `ObjectStorageConfig` (S3Client + S3Presigner beans, both `@ConditionalOnProperty(storage.s3.enabled)` so local dev without MinIO still boots).
- [x] `ObjectStorageService`: `putFile(key, Path, mime)` via `RequestBody.fromFile` (never reads into heap), `getToFile`, `openStream`, `exists`, `delete`, `presignGet`.
- [x] `BucketBootstrapper` `@PostConstruct` — creates the bucket if missing (idempotent), fails startup loudly if creds are wrong.
- [x] Helm: secret entries for access/secret keys, configmap entries for endpoint/bucket/region, env wiring on the backend Deployment. Gated by `objectStorage.enabled` so the section is no-op when MinIO isn't desired.

### Phase 3b — Switch the data plane (all three pieces landed)

- [x] `FileStorageService.storeFile`: **direct-to-S3**, no durable disk write under app control. Reads `MultipartFile.getInputStream()` once for SHA-256 (Spring stages it transiently in `.multipart-tmp`), runs duplicate detection, then a second `getInputStream()` is piped to `objectStorage.putStream("originals/{stored_filename}", in, contentLength, contentType)`. Row saved with `filePath = "originals/{stored_filename}"`. Falls back to the legacy disk pattern when `ObjectStorageService` isn't injected (tests / non-S3 deploys).
- [x] `FileProcessingService.processFile`: per-job temp workdir under `{uploadDir}/.processing-tmp/{id}/`. Original downloaded from S3 (when `filePath` is an S3 key), HEIC→JPEG converts locally and uploads the new key (and deletes the legacy HEIC key from S3), thumb/medium/large/transcoded run on local temps and each is `putFile`'d to its `derivatives/{assetId}/...` key. Workdir is wiped via `deleteRecursive` in `finally`. `file_size` updated to the post-HEIC JPEG size (closes the stale-column source for new uploads).
- [x] **Serve layer** (read side) routed through `StoragePaths.isS3Key`. `ImageServeController` streams from `ObjectStorageService.openStream` when `FileServeInfo.storageKey` is set, otherwise serves the legacy disk Path. Both shapes coexist transparently — no flag day. (`FileController.downloadFile` legacy by-filename endpoint deferred — niche, not used by gallery.)
- [x] **End-to-end smoke**: id=4989 / id=4990 uploads both landed `originals/...` + three derivatives; zero durable bytes on disk; serve via API → MinIO returns byte-identical bytes (sha256 match local-disk-as-known-source).

### Phase 3c — Admin-driven migration (landed)

- [x] `MigrationService` (admin-triggered, not a CommandLineRunner — operator-paced is safer for an oversubscribed Pi). Single-thread executor, `AtomicReference<MigrationRun>` for run state, cancel checked at row boundary.
- [x] **Failure-safety properties**:
  - Idempotent per file: `objectStorage.exists(key)` HEAD-check before every PUT, so a re-run after a crash never re-uploads bytes already in S3.
  - Atomic per row: all five paths flip in a single TX. A row is never half-migrated.
  - Resumable via DB state: rows whose `filePath` already starts with `originals/` are filtered out by the repository query; re-runs converge naturally.
  - Skips `processing_status != DONE` rows so the migrator never races the dispatcher.
  - Local files are *kept* (not moved) — reclaiming disk is a follow-up operator decision.
- [x] **Endpoints** (gated by `storage.s3.enabled`):
  - `POST /api/admin/migrate-to-s3` → 202 + run snapshot. 409 if a run is already in progress.
  - `GET  /api/admin/migrate-to-s3/status` → current/last run snapshot.
  - `POST /api/admin/migrate-to-s3/cancel` → graceful stop at next row boundary.
- [x] Idempotency tests (`MigrationServiceTest`): re-upload skipped when key already in S3, no-op for already-migrated rows, throws on missing local file, concurrent start respects the singleton.

### Testing
- [ ] `FileStorageServiceIT` against a MinIO Testcontainer.
- [ ] e2e gallery + slideshow + public-token flows.
- [ ] Backwards-compat: rows with absolute paths still serve correctly during the migration window.

### Risk
MinIO single-replica is an SPOF for new writes. Acceptable for single-node K3s; underlying Longhorn PVC is durable.

---

## Gap 2b — Worker Deployment split (Phase 4)

Splits the single backend Deployment into two: an **api** pod that handles HTTP + serves bytes, and a **worker** pod that drains `processing_jobs`. Same JAR, same image, different `SPRING_PROFILES_ACTIVE`. Sharing surface is **DB + MinIO only** — no shared filesystem, no in-process handoff. Phase 3 (object storage) is the prerequisite that makes this physically separable.

### Phase 4-prep — decouple `FileStorageService` from `ThumbnailService`

The api pod must boot without pulling Vips/Heic/Ffmpeg beans. Today `FileStorageService` injects `ThumbnailService` purely to call predicates (`isImageFile`/`isVideoFile`/`isHeicFile`) and pure file-deletion helpers (`deleteThumbnails`/`deleteTranscodedVideo`). The remaining heavy uses are in admin endpoints (rotate, `generateMissingThumbnails`, `updateTranscodedVideoPaths`, `updateVideoThumbnailPaths`) which per **D17** stay non-functional for one release post-split.

- [x] New `MimeTypePredicates` static utility — `isImageFile`, `isHeicFile`, `isVideoFile`. No DI.
- [x] New `LocalFileCleanupService` `@Component` — `deleteThumbnails`, `deleteTranscodedVideo`. No Vips/Heic/Ffmpeg deps.
- [x] `FileStorageService.deleteFile` calls `LocalFileCleanupService` instead of `ThumbnailService`.
- [x] `ThumbnailService` predicate methods become thin forwarders to `MimeTypePredicates`; cleanup methods delegate to `LocalFileCleanupService`. Both kept for backwards compat during the transition; remove in R3.
- [x] All other callers (`FileProcessingService`, `SlideshowRecordingService`, etc.) keep using `thumbnailService.is*` until R3 cleanup; no churn now.

### Phase 4a — Profile-gate beans (mergeable, no behaviour change)

Both profiles still co-located in one Deployment. `SPRING_PROFILES_ACTIVE` defaults to `api,worker` so existing deploys keep working. New `Profiles` constants class for grep-ability.

- [x] **Worker-only** (`@Profile(Profiles.WORKER)`): `JobDispatcher`, `FileProcessingService`, `ThumbnailService`, `VipsThumbnailService`, `HeicConversionService`, `FfmpegService`, `JobLeaseService`.
- [x] **API-only** (`@Profile(Profiles.API)`, class-level per **D20**): all 18 controllers, `FileStorageService`, `SlideshowRecordingService`, `UploadBackpressureFilter`, `AsyncConfig`, `SecurityConfig`, `WebConfig`, `OpenApiConfig`, `MigrationService` / `RecordingMigrationService`, `VerificationService` / `RecordingVerificationService`, `EmailService`, `ApnsService`, `DeviceTokenService` (cron), `AlbumSubscriptionNotificationService` (cron), **`AlbumService` / `UserService` / `AlbumSubscriptionService`** (added during R2 pre-flight — each transitively depends on `FileStorageService` or `EmailService`). Last two crons **must** be api-gated or both pods double-fire.
- [x] **Both profiles** (no `@Profile`): all repositories, `ObjectStorageService` + `ObjectStorageConfig`, `BucketBootstrapper`, `JobEnqueueService`, `JobQueueDepthService`, `JobMetricsConfig`, `JobsProperties`, `AudioReencodingService` (per **D18**), shared "utility" services (`TagService`, `GallerySettingService`, etc.). Original plan listed `AlbumService` / `UserService` / `AlbumSubscriptionService` here; R2 pre-flight boot smoke caught that each injects an api-only bean (`FileStorageService` for `AlbumService`, `EmailService` for the other two) — they were promoted to API-only above.
- [x] `FileStorageService` switches `ThumbnailService` injection to `Optional<ThumbnailService>`; admin/rotate methods throw `IllegalStateException` when empty via a `requireThumbnailer()` helper (api pod, post-split). Per **D17** those endpoints are documented broken until Phase 4.5. **Also discovered**: `FileProcessingService` injection had the same shape (legacy `@Async` fallback path), so it's likewise wrapped in `Optional<>` with an `IllegalStateException` if `jobs.dispatcher.enabled=false` on api-only deploys. `AlbumService` gets `Optional<ThumbnailService>` for the same reason (video-date backfill skipped when absent).
- [x] `application.yml` defaults `spring.profiles.active=${SPRING_PROFILES_ACTIVE:api,worker}` so existing deploys, dev runs, and the unit-test suite keep loading both profiles. Per-pod env (`api` / `worker`) overrides at R2.
- [x] New `config/Profiles.java` constants class — `Profiles.API` / `Profiles.WORKER`, used in every `@Profile` annotation.
- [x] Bean-context tests: `WorkerProfileContextTest` + `ApiProfileContextTest` (under `test/.../profile/`) assert presence/absence of the gated beans. Gated by `-Drun.testcontainers=true` like `ProcessingJobLeaseTest` because they need a real MariaDB to satisfy `ddl-auto: validate` + Flyway.

### Phase 4b — Worker pod posture

- [x] Disable the main HTTP listener on the worker pod via `SERVER_PORT=-1` env var on `deployment-worker.yaml` (per **D19**). **Initially shipped as `application-worker.yml`, which broke the api pod** — Spring loads profile-specific YAMLs whenever the profile is *active*, not "active alone", so on the default `api,worker` deploy the override killed Tomcat 8080 there too (502 on `/api/auth/check`). Env var on the worker Deployment scopes the override correctly.
- [x] Confirmed `@EnableScheduling` is safe. The four `@Scheduled` beans split as: `JobDispatcher` (worker), `JobQueueDepthService` (both — refreshes a per-pod local cache, no side-effects), `DeviceTokenService` (api, cron), `AlbumSubscriptionNotificationService` (api, cron). No double-firing in any mode (api+worker, api-only, worker-only).
- [x] `FileStorageService.init()` `@PostConstruct` (creates `.multipart-tmp`) is api-only after gating — fine, worker doesn't need it. `FileProcessingService` continues to create `.processing-tmp/{id}` lazily.

### Phase 4c — Helm

- [x] `values.yaml`: new `worker.*` section parallel to `backend.*` (replicas: 0 default for R1; `worker.image.tag` falls through to `backend.image.tag` so a single release ships both pods at the same version). Backend gets two new keys: `backend.sprintProfilesActive` (empty default → `application.yml`'s `${SPRING_PROFILES_ACTIVE:api,worker}` applies, no behaviour change) and `backend.jobsDispatcherEnabled` (defaults `true`). **Slim `backend.*`** (`limits.memory: 1Gi`, JVM `-Xmx512m`) is deferred to the R2 release commit so R1 truly stays no-op.
- [x] `deployment-backend.yaml`: env `SPRING_PROFILES_ACTIVE` rendered only when non-empty; env `JOBS_DISPATCHER_ENABLED` always rendered (default `"true"`).
- [x] New `deployment-worker.yaml` (`{{ if .Values.worker.enabled }}`): same image/env block as backend, `SPRING_PROFILES_ACTIVE=worker`, **no Service / no Ingress**, ports 8081 only, `emptyDir` mount at `/app/uploads`, resources `limits: { cpu: 4000m, memory: 2Gi }` / `requests: { cpu: 500m, memory: 1Gi }`, JVM `-Xmx512m -XX:MaxRAMPercentage=35.0`, `replicas: {{ .Values.worker.replicas }}` (default 0 in R1 per **D22**).
- [x] New `service-worker-metrics.yaml`: clone of `service-backend-metrics.yaml` with worker selector + matching `prometheus.io/scrape` annotations.
- [x] `_helpers.tpl`: `photo-upload.worker.{fullname,labels,selectorLabels}` helpers (mirror backend).
- [x] `NOTES.txt`: added `PhotoUploadWorkerDown` rule (uses `kube_deployment_status_replicas_available == 0` so a 0-replica R1 manifest doesn't false-alert). `PhotoUploadJobsBacklog` description rewritten to cover both pre-split (in-pod dispatcher) and post-split (worker pod) semantics.
- [x] `helm template` + `helm lint` clean (pre-existing warnings about missing object-storage creds in defaults are unrelated).

### Phase 4d — Circuit breaker for "MinIO unreachable"

Fail-fast contract: 503 within ~50 ms, never hang Tomcat threads. Resilience4j (per **D16**).

- [x] Added `resilience4j-circuitbreaker` + `resilience4j-micrometer` (core libs, not the `-spring-boot3` starter — keeps us Spring Boot version-agnostic and skips AOP we don't need; the breaker is invoked explicitly from the service layer).
- [x] `ObjectStorageService` runs each SDK call through `breaker.executeSupplier(...)` / `executeRunnable(...)`. `CallNotPermittedException` (breaker OPEN) is translated to `MinioUnavailableException` → `GlobalExceptionHandler` 503 with `Retry-After: 30`. Wrapping at the service layer means **all callers** (api `FileStorageService.storeFile`, `ImageServeController` / `SlideshowRecordingController` reads, worker `FileProcessingService` download/put) get the breaker for free, without per-controller annotations.
- [x] SDK timeouts on the `S3Client`: `apiCallAttemptTimeout=2s`, `apiCallTimeout=5s` (defaults were unbounded → 90 s SDK retries pinned Tomcat threads on outage). Retry count not adjusted explicitly — `apiCallTimeout=5s` upper-bounds retries inside the budget; the breaker handles repeated-failure fast-fail.
- [x] `UploadBackpressureFilter` injects `Optional<CircuitBreaker> minioCircuitBreaker`; when state is `OPEN` it returns 503 + `Retry-After: 30` **before** parsing the multipart body — saves the staging cost during a MinIO outage.
- [x] Serve paths automatically covered by the service-layer wrap (`ImageServeController` and `SlideshowRecordingController` both call `ObjectStorageService.openStream(...)` which is breakered). No per-controller annotations needed.
- [x] `health/MinioHealthIndicator` flips readiness DOWN when the breaker is OPEN; HALF_OPEN reports UNKNOWN to avoid flapping during recovery; CLOSED is UP. K8s removes the api pod from the Service for the duration of an outage.
- [x] Worker-side automatically covered (same service-layer wrap). When the worker can't reach MinIO mid-job, the SDK timeout raises through the breaker → `FileProcessingService` catches → `markFailedOrDeadLetter` runs the existing failure path.
- [x] Resilience4j defaults configured programmatically in `ResilienceConfig` (not `application.yml` — since we skipped the Spring Boot starter, the YAML auto-config keys aren't wired). Values match the plan: `failureRateThreshold=50`, `slowCallRateThreshold=100`, `slowCallDurationThreshold=3s`, `slidingWindowSize=20`, `minimumNumberOfCalls=5`, `waitDurationInOpenState=10s`, `permittedNumberOfCallsInHalfOpenState=2`, `automaticTransitionFromOpenToHalfOpenEnabled=true`.
- [x] `TaggedCircuitBreakerMetrics` bound to Micrometer so `resilience4j_circuitbreaker_state{name="minio",...}` etc. surface on `/actuator/prometheus` for both api and worker pods.

### Phase 4e — Roll-out

**R1 — manifests only.** [x] **Landed 2026-04-29 ~18:00 (Helm rev 19).** `worker.enabled: true`, `worker.replicas: 0`, `backend.sprintProfilesActive: ""` (falls through to `application.yml` default `api,worker`). Manifest validation only; behaviour identical to pre-split.

**R2 — worker takes processing.** [x] **Landed 2026-04-29 ~20:43 (Helm rev 20, image `picz2-be:1.0.33`); rev 21 corrected `jobsDispatcherEnabled` after first upload failed.** `worker.replicas: 1`, `backend.sprintProfilesActive: "api"` (drops `worker`), **`backend.jobsDispatcherEnabled: true`** (see correction below). `worker.sprintProfilesActive: "worker"`, `worker.jobsDispatcherEnabled: true`. Backend slimmed: `limits.memory 3Gi → 1Gi`, `requests.memory 1536Mi → 768Mi`, `-Xmx1024m → 512m`, `-Xms512m → 256m`. `SELECT … FOR UPDATE SKIP LOCKED` makes any rolling-update overlap safe. Soak 24 h before R3.

  **Earlier-plan correction.** This document originally said R2 sets `backend.jobsDispatcherEnabled: false` "→ api pod enqueues but never drains" with a "subtle invariant" that the property only controls the enqueue contract. **That was wrong.** The actual code in `FileStorageService.storeFile` reads:
  - `dispatcherEnabled=true` → row inserted as `QUEUED` + `processing_jobs` row written via `JobEnqueueService`. No legacy call.
  - `dispatcherEnabled=false` → row inserted as `INGESTED` + **no `processing_jobs` row** + falls through to `legacy.processFileAsync(...)`. Requires `FileProcessingService` (worker-only). On the api pod that bean is absent → `IllegalStateException`. The first upload after R2 hit exactly this and stranded asset id 4992 as `INGESTED` with no job. R2 was corrected by setting the api pod's flag to `true`; drain remains worker-only because `JobDispatcher` is `@Profile(WORKER)` regardless of the property. Asset 4992 was manually re-enqueued (job 7) and processed cleanly.

  **R2 pre-flight findings** (caught by local boot smoke when Testcontainers couldn't run on Docker Desktop):
  - `AlbumService`, `UserService`, `AlbumSubscriptionService` were listed as "shared" in Phase 4a but each transitively depended on an api-only bean (`FileStorageService` / `EmailService`). Worker boot crashed `UnsatisfiedDependencyException`. Fixed by adding `@Profile(API)` (committed 24d5e43). Phase 4a list updated above.
  - Helm template bug: `value: {{ .Values.backend.jobsDispatcherEnabled | default true | quote }}` rendered `false` as `"true"` because Go-template `default` treats boolean `false` as falsy. Same bug in worker template. Patched both — `default` removed; `values.yaml` is the source of truth. (Fixing this template bug is what unmasked the dispatcher-flag bug above — pre-fix, the api pod was always reading `true` regardless of values.)

**R3 — cleanup.** [x] **Landed 2026-04-30** after a clean R2 soak (DB read: 2446/2446 file_metadata DONE, 38/38 processing_jobs DONE, 0 DEAD_LETTER). Removed: `FileProcessingService.processFileAsync` + the `@Async` annotation, `AsyncConfig` (whole file deleted; no remaining `@Async` users), `INGESTED` from `ProcessingStatus` (DB column + V30 default kept — every insert sets the value explicitly), `Optional<ThumbnailService>` and `Optional<FileProcessingService>` shims on `FileStorageService` plus the legacy fallback branch in `storeFile`, `requireThumbnailer()`, the three deferred admin methods (`generateMissingThumbnails` / `updateTranscodedVideoPaths` / `updateVideoThumbnailPaths`) and their `AdminController` endpoints, the `is*`/`deleteThumbnails`/`deleteTranscodedVideo` forwarders on `ThumbnailService` (callers updated to use `MimeTypePredicates` / `LocalFileCleanupService` directly), the `Optional<ThumbnailService>` shim + video-date backfill loop on `AlbumService`, and the `UploadBackpressureFilter` executor-fallback branch (and its `ThreadPoolTaskExecutor` injection). Also removed the now-vestigial `jobs.dispatcher.enabled` flag end-to-end (`JobsProperties.Dispatcher`, `application.yml`, `values.yaml`, `deployment-backend.yaml`, `deployment-worker.yaml`, the early-returns in `JobDispatcher` / `JobQueueDepthService` / `UploadBackpressureFilter`) — there's no fallback to gate. iOS `AssetProcessingStatus` and frontend `ProcessingStatus` types likewise dropped `INGESTED`. Test suite parity: 6 failures on the changed branch, identical to master HEAD (verified via stash + retry) — R3 introduces zero regressions.

### Testing

- [x] `WorkerProfileContextTest` / `ApiProfileContextTest` assert bean presence per profile (gated by `-Drun.testcontainers=true`, same as `ProcessingJobLeaseTest`).
- [ ] Cross-profile JVM Testcontainers: spin two `SpringApplicationBuilder().profiles(...).run()` contexts against one MariaDB. Api context inserts `FileMetadata` + `ProcessingJob`; worker context picks it up; both rows reach `DONE`.
- [ ] Chaos: `kubectl scale deploy/worker --replicas=0` mid-job → lease expires → resume on restart. `--replicas=2` → no asset has `processing_attempts > 1`.
- [ ] CB chaos: `kubectl scale deploy/minio -n minio --replicas=0` → upload returns 503 within ~50 ms once breaker is OPEN; restore → recovery within ~20 s.

### Risk / rollback

R2 rollback: `backend.sprintProfilesActive=""` (empty → application.yml default `api,worker`), `backend.jobsDispatcherEnabled=true` (was already true post-fix), `worker.replicas=0`. Coexistence is safe at every step because of `SKIP LOCKED`. Per-pod `emptyDir` for processing scratch is the same restart-loses-in-flight property the PVC had post-Gap 8 — no new exposure.

### Follow-ups (not blocking the split)

- [x] **Phase 4.5**: rewrite admin / rotate endpoints as worker-side jobs (per **D17**). Closed 2026-05-03 — REGEN_THUMBNAILS landed; the two video-path admin methods are deliberately not rebuilt (PVC unmounted, no use case, see notes below).
  - [x] **Rotate-left**: `processing_jobs.job_type` column added (V32, **D23**); `JobType.{PROCESS,ROTATE_LEFT}` discriminates dispatch; `FileProcessingService.rotateAndReprocess` runs on worker; `FileStorageService.rotateImageLeft` (api) flips `processing_status=QUEUED` + enqueues `ROTATE_LEFT` in same TX; `FileController` returns 202; `GalleryView.vue` polls `/api/assets/{id}/status` (1 s, 60 s cap) before reloading. Note: `IllegalStateException` was never mapped to 503 in `GlobalExceptionHandler` so the broken pre-fix endpoint actually returned 500 — moot now that the path works.
    - **Post-deploy follow-ups landed 2026-04-29:**
      - `oglimmer.sh` only restarted `photo-upload-backend` on `-s`, not `photo-upload-worker`. With `:latest` + `imagePullPolicy=Always`, this leaves the worker on its previously-cached image and silently runs old `JobDispatcher` code against the new schema — ROTATE_LEFT jobs get dispatched as PROCESS, no rotation, no error. Patched: script now restarts both whenever `BUILD_BACKEND=true`, and gained a `--worker-deploy` flag + `WORKER_DEPLOYMENT` env override mirroring the backend pattern.
      - Gallery `<img>` kept showing the pre-rotate bytes until a full page refresh. Root cause: `:key="file.id"` made Vue reuse the same `GalleryItem` instance across `loadAlbumFiles`, and the browser stubbornly served the previously-loaded image despite the new `publicToken` URL. Fix: `:key="\`${file.id}:${file.publicToken}\`"` forces a remount with a fresh `<img>` element when the token changes (which only happens on rotate — uploads/reorder/status polls keep the key stable).
      - The "Processing…" spinner placeholder was missing during rotate because the rotate handler polled a local variable instead of mutating the file's `processingStatus`. Fix: in `handleRotateImage`, set `target.processingStatus = 'QUEUED'` immediately after the 202, and update it from each poll tick. `GalleryItem.thumbnailReady` flips false → spinner shows for the duration of the worker job, identical UX to a fresh upload.
  - [x] **`generateMissingThumbnails`** rewritten as a worker job (2026-05-03). New `JobType.REGEN_THUMBNAILS`; `FileProcessingService.regenerateThumbnails` reuses the rotate-side `pickRotationSource` fallback chain (original → large → medium → thumb), so it works on retention-purged assets too. Identical lease/retry/dead-letter machinery as ROTATE_LEFT. New `FileMetadataRepository.findMissingThumbnailIds(maxRows)` filters image-typed DONE rows missing one of the three derivative paths AND with no active job (idempotent re-runs). New `FileStorageService.enqueueRegenForMissingThumbnails(maxRows)` walks the IDs in one TX, flipping each row to QUEUED + enqueueing the job. `POST /api/admin/regen-missing-thumbnails?maxRows=500` (capped at 5000) returns `{success, message, stats:{enqueued, maxRows}}`. Caller pages by re-invoking until `enqueued == 0`.
  - **`updateTranscodedVideoPaths`, `updateVideoThumbnailPaths`** — won't-build (decision 2026-05-03). Both originally scanned the local PVC to repair drifted DB paths. The PVC is unmounted post-Gap 8 and all paths are deterministic S3 keys derived from `assetId`, so they cannot drift in the new architecture. Failures during PROCESS surface via DEAD_LETTER + the new REGEN_THUMBNAILS sweep above. If a future use case re-emerges (e.g. bulk re-transcode after an ffmpeg upgrade), add a `REGEN_VIDEO` JobType using the same pattern as REGEN_THUMBNAILS.
  - [x] `AlbumService` video-date backfill — removed in R3 (the loop was an api-side ffprobe call, impossible after the worker split). If we want creation-time backfill again, enqueue a `BACKFILL_VIDEO_DATE` worker job per row; for now ordering by upload date when EXIF is absent is the documented behaviour.
- [ ] **`/actuator/prometheus` returns 401** (pre-existing, surfaced during R2 verification). API pod's `SecurityConfig` only permits `/actuator/health/**` and `/actuator/info`; worker has no `SecurityConfig` so falls to Spring Security secure-by-default. Means the `PhotoUploadJobsBacklog` / `PhotoUploadJobsDeadLetter` alerts in `NOTES.txt` would never fire because the scrape itself fails. Permit `/actuator/prometheus` (cluster-network only) on both pods, or add a worker-side `WorkerSecurityConfig` (`@Profile(WORKER)`) that allows the actuator namespace.

---

## Gap 3 — TUS resumable uploads (Phase 5)

### Architecture (D7, accepted)

`tusd` Deployment writing **directly to MinIO** via the S3 backend. tusd never hits the JVM for chunk PATCHes — only thin hook callbacks on `pre-create` and `post-finish` reach the api pod. Worker pod is unchanged: it drains `processing_jobs` whether the row arrived via multipart or TUS.

```
[client] -- POST /files/ ------> [tusd] -- pre-create  hook --> [api]
[client] -- PATCH /files/{id} -> [tusd] -- S3 multipart -----> [MinIO]
                                 [tusd] -- post-finish hook --> [api] -> insert file_metadata + processing_jobs
[worker] <-- SKIP LOCKED lease ---------------------------- [processing_jobs]
```

Phase 6 (retention) landed before Phase 5, breaking the original sequence diagram. That is fine: retention's eligibility query (`file_path LIKE 'originals/%'`) does not match the `tus-uploads/` prefix, so the new namespace is out of scope. Stale TUS uploads are swept by tusd's own `-expire-after=168h` plus a MinIO bucket-lifecycle abort-rule.

### Phase 5a — tusd in cluster (manifests only, no client traffic)

- [x] Helm: `deployment-tusd.yaml` (image `tusproject/tusd:v2`, single replica per **D29**). Args:
  ```
  -s3-bucket=$(STORAGE_S3_BUCKET)
  -s3-endpoint=$(STORAGE_S3_ENDPOINT)
  -s3-object-prefix=tus-uploads/
  -s3-disable-content-hashes
  -hooks-http=http://photo-upload-backend:8080/api/tus/hooks/$(TUS_HOOK_SECRET)
  -hooks-http-forward-headers=Authorization
  -hooks-enabled-events=pre-create,post-finish,post-terminate
  -behind-proxy
  -base-path=/files/
  ```
- [x] `service-tusd.yaml` ClusterIP:1080.
- [x] `_helpers.tpl`: `photo-upload.tusd.{fullname,labels,selectorLabels}` mirroring backend / worker.
- [x] `secret.yaml`: new `tus.hookSecret` entry; required when `tus.enabled` (operator generates with `openssl rand -hex 32`); injected as env to both tusd and api Deployments.
- [x] Ingress: route `/files/*` to tusd Service. `/api/*` continues to api Deployment. `/api/tus/hooks/{secret}` is **not** exposed externally. Conditional skip in `ingress.yaml` ensures `tus.enabled=false` doesn't render a /files entry pointing at a missing Service.
- [x] MinIO bucket lifecycle: `mc ilm rule add --prefix tus-uploads/ --expiry-days 7` documented in `NOTES.txt` — operator applies once per environment, like the existing prometheus alert rules. This is platform-side because the bucket lives in the platform-managed `minio` release. **Required, not optional**: tusd 2.x dropped its in-process `-expire-after` flag (originally in the plan but discovered missing during R1 deploy — the pod CrashLoopBackOff'd until we removed the flag), so the bucket lifecycle is the only GC mechanism for stale `tus-uploads/{uuid}` objects.
- [x] `helm template` + `helm lint` clean. Verified both `tus.enabled=true` (renders Deployment + Service + Ingress route + secret + backend env vars) and `tus.enabled=false` (omits all of the above) paths.

  **Implementation note** — the original recommendation in D27 was HMAC-signed hook bodies. tusd 2.x cannot sign hook bodies, only forward client request headers, so HMAC was infeasible without a custom shim. Substituted with a path-secret in the hook URL (`/api/tus/hooks/$(TUS_HOOK_SECRET)`) validated with constant-time compare. Functionally equivalent defence-in-depth.

  **Integer rendering bug caught during validation** — `maxSize: 524288000` rendered as `5.24288e+08` (Helm/Go template treats YAML numeric as float64). Fixed in both `deployment-tusd.yaml` arg (`-max-size={{ .Values.tus.maxSize | int64 }}`) and the backend `TUS_MAX_SIZE` env (`int64 | quote`). Same bug class as the earlier R2-pre-flight `default true | quote` rendering issue.

### Phase 5b — backend hooks (still no client traffic)

- [x] Added `ObjectStorageService.copy(srcKey, dstKey, contentType)` (server-side `CopyObjectRequest` with `MetadataDirective.REPLACE` for content-type override; no JVM bytes; breaker-wrapped).
- [x] `TusProperties` (`@ConfigurationProperties("tus")`): `enabled` (default false), `advertised` (default false), `endpoint` (default `/files/`), `maxSize`, `hookSecret`, `version`.
- [x] `TusHookController.POST /api/tus/hooks/{secret}` (`@Profile(API)` + `@ConditionalOnProperty(tus.enabled)`):
  - Path-secret validated with `MessageDigest.isEqual` (constant-time) before any further work; mismatch → 404 (matches Spring's "unmapped URL" response shape so a probe can't tell whether the endpoint exists).
  - `pre-create` handler: parse `Upload-Metadata.auth` as `email:password`, validate via the existing `AuthenticationManager` (HTTP Basic, same path the multipart endpoint uses); reject 409 if `contentId` already in `file_metadata` (per **D30**); reject 503 with `Retry-After: 30` if `JobQueueDepthService.depth > threshold` (per **D28**); 200 otherwise.
  - `post-finish` handler: re-validates auth (Authorization header + `auth` metadata both flow on every PATCH); short-circuits 200 when a row already exists for the contentId (idempotent retry); otherwise calls `FileStorageService.registerTusUpload(...)` which COPIES, inserts the row + enqueues a PROCESS job in one TX, and deletes the tus-uploads/{uuid}+`.info` objects best-effort.
  - `post-terminate` handler: logs and 200s. tusd already cleaned up the S3 object.
  - Crucially: post-finish never returns 5xx, even on internal failure. Returning 5xx would loop tusd retries against an already-finalised upload that can't be undone; orphan-detection (follow-up) mops up any stranded `originals/...` objects.
- [x] `CapabilitiesController.GET /api/capabilities` (`@Profile(API)`) returns `{ tus: { enabled, endpoint, version, maxSize }, multipart: { enabled, endpoint } }`. `tus.enabled` here is *advertised* (the user-facing flag); pin to `false` in R1, flip to `true` in R2.
- [x] `SecurityConfig`: permit `/api/tus/hooks/**` (path-secret is the auth) and `GET /api/capabilities`.
- [x] `application.yml`: `tus.enabled`, `tus.advertised`, `tus.endpoint`, `tus.max-size`, `tus.hook-secret`, `tus.version`. Helm wires the secret-backed `TUS_HOOK_SECRET` from the `Secret`.
- [x] Added `FileStorageService.registerTusUpload(...)` — TUS-side parallel to `storeFile`. Same TX boundary (row + enqueue), same `originals/{stored_filename}` invariant, but skips checksum-based dedupe (would require downloading from S3, defeats the point of TUS); contentId dedupe in pre-create is the only de-dupe path on the TUS side. Documented as a known limitation in V1.
- [x] Unit tests: `TusHookServiceTest` — 10 tests covering pre-create missing-auth / bad-credentials / backpressure / duplicate-contentId / happy-path; post-finish register / idempotent-retry / swallowed-auth-failure / swallowed-register-failure; post-terminate ack. `TusHookControllerTest` — 8 tests covering path-secret guard + dispatch + 200-with-JSON envelope. All pass. Full server suite shows 6 pre-existing failures (`TagServiceTest`, `JobLeaseServiceTest`×4, `FileProcessingServiceStatusTest`) — same count as documented in the R3 cleanup section, no Phase 5 regressions.

  **Post-R1-deploy bug fix #2 (2026-05-01)** — first real upload via `tus-js-client` from the web frontend hit `HTTP/2 500: ERR_INTERNAL_SERVER_ERROR: failed to parse hook response: unexpected end of JSON input`. Root cause: tusd 2.x **requires** the hook response body to be a JSON-shaped {@code HookResponse} envelope (`{"HTTPResponse":{...},"RejectUpload":bool}`), and uses the inner `HTTPResponse.StatusCode` to decide what to surface to the actual client. The original implementation returned `ResponseEntity.ok().build()` (HTTP 200 with empty body) and used 4xx/5xx HTTP statuses for rejections — both wrong. Fixed by introducing a new `TusHookResponse` DTO (records mapping to PascalCase via `@JsonProperty`), refactoring `TusHookService` methods to return `TusHookResponse` instead of `ResponseEntity<Object>`, and having `TusHookController` always wrap in `ResponseEntity.ok(...)`. Path-secret-mismatch is the one exception that still returns bare HTTP 404 — tusd never calls with a wrong secret in normal operation, and 404 keeps the path's existence unobservable to probes.

  **Post-R1-deploy bug fix #3 (2026-05-01)** — second upload attempt got past the hook-envelope fix and reached `post-finish`, then the `objectStorage.copy(tusKey, ...)` raised `NoSuchKeyException`. Root cause: tusd's S3 store synthesises {@code Upload.ID} as `<objectName>+<base64-multipartUploadId>`, where only the part before the `+` is the actual S3 object key. Our code reconstructed the key naively as `tus-uploads/{Upload.ID}` — pointing at a path that never exists. Fixed by adding a `Storage` field (`Map<String,String>`) to `TusHookRequest.TusUpload` and reading the authoritative `Storage.Key` set by tusd. Falls back to splitting `Upload.ID` on `+` if a future tusd version drops `Storage`. Applies to both `post-finish` (COPY+DELETE source) and `post-terminate` (logging).

  **Post-R1-deploy bug fix #4 (2026-05-01) — TUS post-finish-vs-PATCH-204 race.** With all the server-side fixes in, uploads landed cleanly but the new image didn't show in the gallery without a hard refresh. tusd's logs revealed the cause: contrary to its docs claim that "the client will not get a response until after the hook has been completed", tusd 2.4.0 sends the PATCH 204 *before* invoking `post-finish`:

  ```
  21:38:43.652206 - ResponseOutgoing PATCH status=204    ← client gets 204 here
  21:38:43.654200 - HookInvocationStart type=post-finish ← THEN post-finish starts
  21:38:43.869412 - HookInvocationFinish type=post-finish ← row finally committed (217ms later)
  ```

  So `tus-js-client.onSuccess` fires, `await loadAlbumFiles` runs, and `/api/files` is queried ~200ms before the `file_metadata` row exists. Result: the response correctly returns the *old* file list; the gallery doesn't re-render because the new file isn't there. After ~3 minutes, a hard refresh sees the row and renders it.

  Fixed in `GalleryView.vue#handleFileUpload`: snapshot the file-list length before the upload loop, then poll `loadAlbumFiles` until `files.value.length >= initialCount + successCount` or a 3 s deadline, with 300 ms gaps between polls. First load happens immediately; the loop only iterates if the row hasn't shown up yet. Multipart is harmless to this change since its row commits before the response.

  Three layers of timing-related lessons here, all because the docs disagreed with the actual behaviour:
  1. tusd's `Upload.ID` is `<objectName>+<multipartUploadId>` — not a key (#3).
  2. tusd's hook response *body* must be a JSON envelope, not a plain HTTP status (#2).
  3. tusd's `post-finish` is **not** synchronous despite docs — the PATCH 204 fires before the hook starts.

### Phase 5c — iOS client (gated, default off)

**Status: shipped end-to-end and verified on device (2026-05-02).** TUS uploads from iOS land cleanly when `Settings.useTus=true`; multipart path is unaffected when off. Two pre-existing iOS issues surfaced and were fixed during the first Xcode build:

1. `ProcessingStatusPoller` line 78 still referenced `AssetProcessingStatus.ingested` — the enum case had been removed during Phase 4 R3 cleanup but the iOS target hadn't been built since, so the dangling reference went unnoticed. Removed.
2. `SyncCoordinator.syncTargetAlbumFromServer` async-clear race (when server returns null target album): completion fired before the `DispatchQueue.main.async` clear, so the caller's `guard settings.selectedAlbumName != nil` saw the stale non-nil value and proceeded with a doomed scan. Moved `completion(true)` inside the async block so the caller observes the post-clear state. Pre-existing, only fires on the rare server-clears-target-album path; no data loss in either case.

Also surfaced (not fixed in this commit): the user's `User.defaultAlbumId` was null, so iOS multipart uploads were 400ing because they don't include `albumId` in the form body and the server falls back to `currentUser.getDefaultAlbumId()`. Resolved out-of-band by `PUT /api/settings/target-album`. Operational, not a code bug.

- [x] `Settings.useTus: Bool` — toggle in `SyncOptionsView` under an "Advanced" section, default `false`, persisted via `UserDefaults`. Cleared by `Settings.clear()`. Footer text explains what TUS does in plain English. The toggle is a no-op when server-side `tus.advertised=false` (`shouldUseTus()` requires both flags), so it can ship without coordinating with R2/R3 capability flips.
- [x] `Models/Capabilities.swift` — Decodable matching the api response shape.
- [x] `APIClient.fetchCapabilities(completion:)` — unauthenticated GET, returns the same Decodable. Caller responsible for caching.
- [x] `TusUploader.swift` — singleton with its own background URLSession (identifier `com.oglimmer.photosync.tus`), drop-in shape match to `Uploader` (`configureSession`, `queueUpload`, `onTaskFinished`, `getActiveUploadAssetIds`). V1 sends a single PATCH per upload (the entire file from offset 0); the URLSession's built-in retry handles network blips. Cross-launch resume via `HEAD /files/{id}` is documented as deferred V2 work — needs Xcode + device verification.
- [x] `APIClient.tusEndpointURL()` and `APIClient.tusUploadMetadata(...)` extension helpers — TUS spec-compliant `Upload-Metadata` (comma-separated key + base64 value pairs); auth piggy-backs on the existing HTTP Basic credentials.
- [x] `SyncCoordinator` integration (2026-05-02) — picks `TusUploader.shared` vs `Uploader.shared` based on cached `/api/capabilities` × `Settings.useTus`, decided once per drainQueue batch (not per asset, to avoid a half-multipart-half-TUS batch if a capability flip races with the loop). Adapts `TusUploader.UploadOutcome` to `Uploader.UploadOutcome` in `init()` so `handleUploadFinished` stays path-agnostic. `start()` now configureSessions both uploaders, merges their `getActiveUploadAssetIds()` for stale-cleanup, and kicks off a non-blocking capabilities fetch (1 h TTL). Capabilities-fetch failure or pending state silently falls back to multipart. `Settings.useTus` defaults `false` so the user must opt in even after R2 capabilities flip.
- [x] **Status polling for TUS uploads** (2026-05-02) — fixed via a new `GET /api/assets/by-content?albumId=X&contentId=Y` endpoint that returns the same `AssetProcessingStatusResponse` shape as `/api/assets/{id}/status`. iOS `APIClient.lookupAssetByContentId` is called from `SyncCoordinator`'s TUS adapter when the upload completes with `serverAssetId=nil`; retries up to 4× with exponential backoff (200/400/800/1600ms) to ride out the post-finish hook race window (~200ms typical, 1s worst case observed in production). On success, normal `ProcessingStatusPoller` polling kicks in; on persistent failure (row never appears, hook crashed), nil is forwarded — upload is still recorded as success, only the FAILED/DEAD_LETTER notifications are unavailable for that asset.

### Phase 5d — Roll-out

- [x] **R1 — manifests only** (2026-05-01). tusd Deployment, hook secret, Ingress route. Four post-deploy tusd-protocol bugs found and fixed (see fix #1–#4 in Phase 5b notes). Verified `OPTIONS /files/` and hook round-trips end-to-end.
- [x] **R2 — flip capabilities** (2026-05-01). `tus.advertised=true`, web frontend uses TUS automatically; multipart kept as fallback. Verified with real photo upload through `tus-js-client`.
- [x] **R3 — all clients TUS by default** (2026-05-02). iOS `Settings.useTus` default flipped from `false` to `true` (init + `clear()`). Web has been on TUS since R2 (capability-driven, no per-user flag). Existing iOS users who explicitly toggled the switch off keep their preference (`UserDefaults.object` returns nil iff never written, so the `?? true` default only applies to never-touched values). 2-week soak before considering R4.
- [ ] **R4 — deprecate multipart.** Earliest 3 months after R3 (2026-08-02). `/api/upload` returns 410 Gone pointing at `/api/capabilities`. iOS minimum supported version forced upward.

### Testing

- [ ] **Unit**: hook-path-secret verification, pre-create dedupe, pre-create backpressure, post-finish row insert.
- [ ] **Integration** (Testcontainers MariaDB + MinIO + tusd): full round-trip — `POST /files/` → PATCH chunks → assert `file_metadata` + `processing_jobs` rows match the multipart path.
- [ ] **Resume**: PATCH 1 chunk, kill the connection, `HEAD /files/{id}` reports correct offset, resume completes, post-finish fires exactly once.
- [ ] **Pod restart**: `kubectl delete pod -l app=tusd` mid-upload. tusd persists state in S3, client resume succeeds after restart.
- [ ] **Backpressure**: pin queue depth above threshold via SQL → `POST /files/` returns 503 + `Retry-After`.
- [ ] **Duplicate**: same `contentId` twice → second `POST /files/` returns 409.
- [ ] **iOS chaos**: airplane-mode toggle mid-PATCH, force-quit + relaunch mid-PATCH, OS reboot mid-PATCH.
- [ ] **End-to-end gallery**: TUS-uploaded asset appears in gallery, derivatives render, public token works, rotate works.

### Risk / rollback

- **Stale TUS uploads**: client uploads but never completes → `tus-uploads/{uuid}` lingers. The MinIO bucket-lifecycle abort-rule is the **only** GC mechanism — tusd 2.x removed its in-process `-expire-after` flag (we discovered this during R1 deploy when the tusd pod CrashLoopBackOff'd on startup). Without the lifecycle rule applied, abandoned uploads accumulate indefinitely. Phase 6 retention sweep is unaffected — its WHERE clause matches `originals/%` only, so the `tus-uploads/` prefix is out of scope.
- **post-finish hook fails after S3 COPY succeeds**: row never written, but the `originals/{stored_filename}` object exists in MinIO. Recovery: orphan-detection job (compare `originals/*` listing against `file_metadata.file_path`) — deferred to follow-up; manual cleanup acceptable in early rollout.
- **Hook secret leak**: rotate via Helm secret + tusd Deployment restart + api pod restart. No long-lived state.
- **R2 rollback**: `tus.enabled=false` in api config. Existing in-flight TUS uploads on iOS will fail; the next `/api/capabilities` poll switches them back to multipart for the next attempt.
- **R4 rollback**: revert the `/api/upload` 410 commit. The multipart code path stayed in place; re-enabling is a config change.

### Follow-ups (not blocking ship)

- [x] **Orphan-detection job for `originals/` keys without `file_metadata` rows** (post-finish hook crash recovery, also covers multipart-PUT-then-TX-fail). Landed 2026-05-03 as a third pass in `RetentionService.runOriginalsOrphanCleanup`. Set-diffs `objectStorage.listKeysOlderThan("originals/", now − retention.orphan-grace-hours)` against `FileMetadataRepository.findAllOriginalsKeys()` (projection-only, no entity hydration). Default grace `24h` — wide enough that no in-flight upload can be misclassified (post-finish hook race is sub-second, ~1s observed worst-case), narrow enough that real orphans don't sit around for a week. Same `dryRun` / `maxRowsPerRun` knobs as the originals + TUS sweeps; `RetentionRunner` sums all three failure counts into the exit code. 7 unit tests in `RetentionServiceOrphanCleanupTest`; zero regressions in the existing TUS test suite.
- [ ] tusd Prometheus metrics scrape (`/metrics` endpoint native to tusd; add `prometheus.io/scrape` annotations to the tusd Service).
- [ ] Web frontend TUS support (`tus-js-client`). Currently web uses the multipart path; lower priority because web uploads are smaller.
- [ ] NetworkPolicy restricting `/api/tus/hooks/**` ingress to the tusd Pod's identity (defence-in-depth on top of D27 path-secret).
- [x] **Stale TUS upload GC** — discovered during R1 deploy: tusd 2.x removed `-expire-after`, and the platform-side MinIO is single-drive (no lifecycle API). Solved by extending `RetentionService` with a `runTusCleanup()` second pass that lists `tus-uploads/` and deletes objects older than `retention.tus-upload-days` (default 7). Same nightly CronJob, same dry-run/max-rows safety properties. New `ObjectStorageService.listKeysOlderThan(prefix, cutoff)` helper. `RetentionRunner` calls both passes and sums failure counts into the exit code. 6 unit tests added (`RetentionServiceTusCleanupTest`); zero regressions.

---

## Gap 4-finish — Retention CronJob (Phase 6)

- [x] `cronjob-retention.yaml`: nightly at `03:17`, `concurrencyPolicy: Forbid`, `restartPolicy: Never`, `backoffLimit: 0`. Runs the same backend image with `SPRING_PROFILES_ACTIVE=retention`. `application-retention.yml` strips Tomcat (`spring.main.web-application-type=none`) and the management port; `RetentionRunner.run()` calls `SpringApplication.exit(...)` so K8s reports Job/Completed.
- [x] V33 migration drops the `NOT NULL` on `file_metadata.file_path`; `FileMetadata.filePath` entity field updated to match.
- [x] `RetentionService` (under `@Profile(Profiles.RETENTION)`) finds rows where `processing_status='DONE'` AND `uploaded_at < NOW() - retention.original-days` AND `file_path LIKE 'originals/%'` AND `thumbnail_path IS NOT NULL` (defensive sanity check that *some* derivative exists) → S3 DELETE original → null `file_path` in its own per-row TX. `RetentionProperties` exposes `retention.original-days` (default 7), `retention.max-rows-per-run` (default 5000, prevents runaway sweep on misconfig), `retention.dry-run` (was `true` in chart values for first-run safety; **flipped to `false` on 2026-05-03** after the 2026-05-02 nightly logged eligible=2408 / 0 failures cleanly).
- [x] `RetentionRunner` (one-shot `CommandLineRunner`) wraps `RetentionService.run()` + `runTusCleanup()` + `runOriginalsOrphanCleanup()` and exits with `min(originals.failed + tus.failed + orphans.failed, 125)` so a partial-failure run shows on the CronJob's last-failed status without masking it as success.
- [x] **Orphan-detection third pass** (added 2026-05-03 — see Gap 3 Follow-ups). `RetentionService.runOriginalsOrphanCleanup` set-diffs S3 `originals/` listing (older than `retention.orphan-grace-hours`, default 24h) against `FileMetadataRepository.findAllOriginalsKeys()` to delete keys with no live row. Same `dryRun` / `maxRowsPerRun` knobs. `RETENTION_ORPHAN_GRACE_HOURS` env added to `cronjob-retention.yaml`.
- [x] File-serve adjustment: `FileStorageService.getFileServeInfoByPublicToken` falls back to the largest available derivative (`transcoded` for video > `large` > `medium` > `thumbnail`) when `filePath` is NULL and no specific size was asked for. Explicit `?size=original` on a purged asset throws the new `ResourceGoneException`, mapped to 410 by `GlobalExceptionHandler`.
- [x] **Rotation works after purge** (revised 2026-05-03). Originally `FileStorageService.rotateImageLeft` threw 410 when `filePath` was NULL and `GalleryItem.vue` hid the rotate button via `originalAvailable: boolean`. Walked back: rotate output is bounded by LARGE=2400px regardless of source resolution, so the worker can fall back to the largest available derivative (`large` → `medium` → `thumb`) and produce pixel-equivalent output to what the user already gets post-purge. `FileProcessingService.rotateAndReprocess` now picks the best S3-backed source via the new `pickRotationSource()` helper and only writes back to `originals/` when the original is still present (purged assets stay purged — we don't resurrect bytes retention deliberately dropped). `FileStorageService.rotateImageLeft` keeps a defensive 410 only when no S3-backed source exists at all (unreachable for any DONE asset). `GalleryItem.vue#canRotate` now always true; `originalAvailable` flag retained on `FileInfo` for any future "download original" UI.

### Testing
- [ ] Shorten retention to 0 in staging, run the CronJob manually (`kubectl create job --from=cronjob/...`), verify originals are gone but gallery still serves derivatives.
- [ ] Idempotency: re-run the runner immediately after a successful sweep — eligibility query returns 0 rows because every purged row now has `file_path IS NULL`.
- [ ] Crash recovery: kill the runner between the S3 DELETE and the DB UPDATE for a row → next run sees the row again, S3 DELETE is a no-op, DB null-out completes.

### Risk
Irreversible deletion. Hence the conservative 7-day default, `dryRun: true` in chart values for first-run validation, the `originals/` prefix filter (legacy local-disk paths are deliberately out of scope), and the per-row TX that limits blast radius if the eligibility query ever returns something it shouldn't.

---

## Gap 8 — Slideshow audio to S3 + backend PVC unmount (Phase 3 follow-up, landed 2026-04-29)

Not in the original plan; surfaced when verifying the photo migration was complete and discovering `SlideshowRecordingService` still wrote durably to `${uploadDir}/recordings/`. That blocked the goal of detaching the backend pod from the durable PVC, so audio was migrated under the same direct-to-S3 model as photos.

### S3 key convention (D-new)

Distinct prefix `audio/{audioFilename}` for migrated/new recordings. Legacy paths `recordings/{audioFilename}` continue to mean local-disk relative path. The `audio_path` column is therefore self-describing — `StoragePaths.isAudioS3Key(path)` is the only routing predicate. Different prefix from photos (which already use `originals/`/`derivatives/`) so the audio migration cannot collide with the photo `recordings/` legacy convention.

### Code

- [x] `StoragePaths.AUDIO_PREFIX = "audio/"` plus `audioKey(filename)` and `isAudioS3Key(path)` helpers.
- [x] `SlideshowRecordingService.saveRecording`: stream → temp file in `{uploadDir}/.audio-tmp/` → `audioReencodingService.reencodeAudio` (ffmpeg needs a local file) → `objectStorage.putFile(audio/{filename}, …)` → delete temp → store `audio_path = "audio/{filename}"`. Legacy disk path retained for non-S3 deployments via `Optional<ObjectStorageService>` injection.
- [x] `SlideshowRecordingService.deleteRecording` is S3-aware: deletes the S3 object when the key is `audio/...`, falls through to the legacy file delete otherwise.
- [x] `SlideshowRecordingController.getRecordingAudio` and `getRecordingAudioByPublicToken`: when `RecordingAudioInfo.storageKey` is set, in-band stream from MinIO with HTTP `Range` forwarded via `objectStorage.openStream(key, rangeHeader)`. Returns 200 / 206 + `Content-Range` as appropriate. (We deliberately did **not** 302 to a presigned URL because MinIO has no public ingress; the API pod must mediate.)
- [x] `RecordingAudioInfo` carries `audioPath` (legacy local) **xor** `storageKey` (S3 backed), mirroring `FileServeInfo`.
- [x] `SlideshowRecordingRepository` gains `countRecordingsOnLocalDisk`, `findRecordingsOnLocalDisk`, `findRecordingsOnObjectStorage` (keyset-paginated).

### Migration & verification

- [x] `RecordingMigrationService` mirrors `MigrationService`: HEAD-before-PUT, atomic per-row flip, idempotent re-runs.
- [x] `RecordingVerificationService` mirrors the photo `VerificationService` hash mode. SHA-256 of `uploads/recordings/{filename}` vs SHA-256 of the MinIO object.
- [x] Endpoints (gated by `storage.s3.enabled`):
  - `POST /api/admin/migrate-recordings`, `GET .../status`, `POST .../cancel`
  - `POST /api/admin/migrate-recordings/verify`, `GET .../verify/status`, `POST .../verify/cancel`
- [x] **Outcome**: 41/41 recordings migrated, hash-verified 41/41 (0 missing, 0 hashMismatch, 0 errored).

### Helm — PVC unmount

- [x] `backend.persistence.mounted` (default `false` in chart values) toggles the deployment's `uploads` volume between `persistentVolumeClaim` and `emptyDir { sizeLimit: 5Gi }`. `enabled` still controls whether the PVC resource is rendered, so the PVC stays defined and Bound while detached from the running pod.
- [x] `backend.persistence.emptyDirSizeLimit` (default `5Gi`) sized comfortably above peak transient footprint (largest in-flight upload + per-job derivative workdir + audio reencode temp).
- [x] **Outcome**: live backend pod runs against `emptyDir` only. PVC remains Bound (30 GiB Longhorn) for byte-level recovery if ever needed; can be cleaned out / `--set persistence.enabled=false`'d later.

### Risk / rollback

`emptyDir` is per-pod ephemeral. A pod restart mid-upload kills any `.multipart-tmp` body Spring is currently staging — same property the PVC had, since per-request multipart was never durable. Rollback is `--set backend.persistence.mounted=true`.

### Follow-up

- [x] **PVC retired (2026-05-03).** `backend.persistence.enabled` flipped to `false` in `values.yaml`; helm upgrade dropped the PVC manifest. PV had `reclaimPolicy=Retain` (provisioned that way 201 days ago) so it went to `Released` rather than auto-freeing — explicit `kubectl delete pv pvc-bcfc2395-…` and `kubectl -n longhorn-system delete volume pvc-bcfc2395-…` chained the cleanup all the way down to Longhorn. 30 GiB freed. The historical-content wipe step from the original plan is implicit in this — no separate `rm -rf` Job needed because Longhorn reclaiming the volume drops the data.

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
