# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal photo / video gallery with iOS sync, TUS resumable uploads, and S3-backed storage. Deployed as a Helm chart to a single-node K3s cluster on a Raspberry Pi 5. Stack:

- **Backend**: Spring Boot 4 (Java) — single JAR deployed as **two pods** (api + worker) sharing state via MariaDB and MinIO only.
- **Frontend**: Vue 3 + Vite + TypeScript, served by Nginx.
- **iOS**: native Swift app (`ios/PhotoCloudSync`) — primary client.
- **tusd**: third-party TUS server, writes directly to MinIO via S3 backend.
- **Retention CronJob**: nightly sweep — same backend JAR, `retention` profile.

> ⚠️ The top-level `README.md` describes a completely different (long-superseded) macOS Share Extension + Node.js project. **Ignore it.** The current architecture lives in `upload-concept-plan.md` (decision log, phase history) and `helm/photo-upload/README.md` (deploy + ops reference).

## Source-of-truth documents

- **`upload-concept-plan.md`** (~75 KB) — the architectural source of truth. Phase history, decisions (D1–D31), gap inventory, what's done / open. Update the `Last reviewed` line at the top whenever you change architecture.
- **`helm/photo-upload/README.md`** — deploy + operate reference. Configuration tables, ops cookbook, troubleshooting.
- **`upload-concept.txt`** — original architectural intent (frozen reference, doesn't get updated).

When you make non-trivial code changes, update the plan doc to keep it in sync.

## Architecture in one paragraph

The backend runs as **api** (`SPRING_PROFILES_ACTIVE=api`) and **worker** (`SPRING_PROFILES_ACTIVE=worker`) — same image, different `@Profile`-gated beans. The api pod handles HTTP and serves bytes from MinIO; the worker pod drains a `processing_jobs` table via `SELECT … FOR UPDATE SKIP LOCKED` (MariaDB ≥ 10.6 required). Every job (PROCESS / ROTATE_LEFT / REGEN_THUMBNAILS) downloads its source from S3 to an emptyDir workdir, runs vips/HEIC/ffmpeg locally, and PUTs derivatives back to deterministic `derivatives/{assetId}/...` keys. TUS uploads land in `tus-uploads/{uuid}` via tusd; a hook callback at `/api/tus/hooks/{secret}` finalises by S3-COPYing to `originals/`, inserting the row, and enqueuing a job — all in one TX. A nightly retention CronJob (also the same JAR, `retention` profile) sweeps aged originals + abandoned TUS uploads + orphan keys.

## Common commands

### Server (Spring Boot)

```bash
cd server

# Compile only
./mvnw -q -DskipTests compile

# Test-compile only
./mvnw -q test-compile

# Run all tests (some IT classes are gated — see below)
./mvnw test

# Run a single test class
./mvnw test -Dtest='RetentionServiceOrphanCleanupTest'

# Run a single test method
./mvnw test -Dtest='RetentionServiceOrphanCleanupTest#deletesOnlyKeysWithNoLiveRow'

# Run multiple classes by pattern
./mvnw test -Dtest='RetentionService*Test,FileStorageService*Test'

# Run integration tests that need a real Docker daemon
./mvnw test -Drun.testcontainers=true
```

**Pre-existing failure to ignore**: `FileProcessingServiceStatusTest.successfulProcessingTransitionsToDoneAndIncrementsAttempts` (1 test) is a documented baseline failure on master — captured in the plan's R3 cleanup notes. Don't try to fix it as part of unrelated work; just don't *introduce additional* failures.

**Testcontainers gate**: `ProcessingJobLeaseTest`, `WorkerProfileContextTest`, `ApiProfileContextTest` are gated by `-Drun.testcontainers=true` because Docker Desktop returns stub responses to docker-java. They run cleanly on a fresh Docker daemon (CI).

### Frontend (Vue 3)

```bash
cd frontend

npm install
npm run dev            # Vite dev server with HMR
npm run build          # vue-tsc + vite build
npm run type-check     # vue-tsc --noEmit
npm run lint           # eslint
npm run lint:fix       # eslint --fix
```

### iOS

Open `ios/PhotoCloudSync/PhotoCloudSync.xcodeproj` in Xcode. Build target requires a paid Apple Developer account (capabilities use background URLSessions, push notifications). The TUS toggle is in `Settings.useTus` (default `true`); set to `false` to fall back to multipart.

### Local development stack

```bash
# Full stack: backend + frontend + MariaDB + MinIO + Traefik (browse via http://localhost)
docker compose up

# Minimal: just MariaDB + Traefik (for running server in IDE while DB lives in Docker)
docker compose -f compose.local.yml up
```

### Deploying to the cluster

```bash
# From repo root. The script builds, pushes, and rolls deployments.
./oglimmer.sh build -s -v        # server only (rolls api + worker; CronJob picks up next firing)
./oglimmer.sh build -f -v        # frontend only
./oglimmer.sh build -a -v        # both
./oglimmer.sh build -s --no-push # build + restart only, no registry push
./oglimmer.sh release            # bump VERSION, tag, build a release
./oglimmer.sh show               # show current VERSION
```

The script reads `VERSION`, builds `registry.oglimmer.com/picz2-{be,fe}:<version>` plus `:latest`, pushes both, and runs `kubectl rollout restart` on the relevant Deployments. With `imagePullPolicy: Always`, the next CronJob firing also pulls the new digest automatically.

### Helm

```bash
# Validate locally (must pass dummy secrets — defaults are empty)
helm template helm/photo-upload \
  --set objectStorage.accessKey=x \
  --set objectStorage.secretKey=y \
  --set tus.hookSecret=z

helm lint helm/photo-upload \
  --set objectStorage.accessKey=x --set objectStorage.secretKey=y --set tus.hookSecret=z

# Upgrade live release (preserves existing values, additive overrides)
helm upgrade photo-upload ./helm/photo-upload --reset-then-reuse-values \
  --set objectStorage.accessKey=… \
  --set objectStorage.secretKey=… \
  --set database.external.password=… \
  --set tus.hookSecret=…
```

### Cluster inspection

```bash
kubectl -n default get pods -l app.kubernetes.io/instance=photo-upload
kubectl -n default logs -l app.kubernetes.io/component=worker --tail=200
kubectl -n default logs -l app.kubernetes.io/component=retention --tail=500
kubectl -n default get cronjob photo-upload-retention -o yaml
```

## Key things to know before changing code

### Profile gating is load-bearing

Bean injection mistakes don't show up at compile time. Both pods boot the same JAR; misclassifying a bean leads to one pod crashing on `UnsatisfiedDependencyException` at startup. Check both `@Profile(API)` (controllers, FileStorageService, etc.) and `@Profile(WORKER)` (FileProcessingService, ThumbnailService, JobDispatcher, etc.) when adding services. The `Profiles` constants class in `config/` is the canonical reference.

### Storage keys are deterministic

`StoragePaths` derives every S3 key from the asset id (`originals/{stored_filename}`, `derivatives/{id}/{thumb,medium,large,transcoded,video_thumb}.{jpg,mp4}`, `audio/{filename}`, `tus-uploads/{uuid}`). No path-drift recovery code is needed because paths can't drift. If a regen path is needed, model it as a new `JobType` (see `REGEN_THUMBNAILS` for the pattern).

### Job pattern

Adding a new background operation:
1. Add a constant to `JobType` enum.
2. Add a worker-side method on `FileProcessingService` (mirror `regenerateThumbnails` — same lease/retry/dead-letter machinery comes for free).
3. Add a `case` to the switch in `JobDispatcher.pollOnce`.
4. Add an api-side enqueue method on `FileStorageService` (mirror `rotateImageLeft` or `enqueueRegenForMissingThumbnails`).
5. Expose via controller. Return 202 + status URL for clients to poll.

### Retention is irreversible

`RetentionService.run()` deletes S3 originals (sets `file_path` to NULL on the row, doesn't delete the row). The orphan and TUS sweeps delete S3 objects directly. Default `dryRun: false` in `values.yaml`. If you change retention logic, set `dryRun: true` for one nightly cycle and read the log before re-enabling deletes.

### Backwards-compatibility shims have all been removed

Phase 4e R3 (2026-04-30) removed every legacy code path: the `@Async` fallback, the `INGESTED` status, the `Optional<ThumbnailService>` injection shim, the `jobs.dispatcher.enabled` flag, the `UploadBackpressureFilter` executor branch, the `is*`/`delete*` forwarders on `ThumbnailService`. There is exactly one happy path now. Don't reintroduce shims for hypothetical future flexibility — write the change directly.

### Migrations live in `server/src/main/resources/db/migration/`

Flyway, MariaDB syntax. Current head is V33 (`V33__make_file_path_nullable_for_retention.sql`). Every entity field must match a migrated column or the app fails to start (`ddl-auto: validate`).

## Memory + automation context

The user's auto-memory (`~/.claude/projects/-Users-oli-dev-photo-upload/memory/MEMORY.md`) holds:
- The user prefers root-cause analysis over surface-level mitigations. Validate hypotheses against code/infra before proposing fixes.
- Cluster topology: Raspberry Pi 5 K3s node, Longhorn PVC, oversubscribed memory (pod OOMs are often node-level SystemOOM events).

Read both before making cluster-side recommendations.
