# Photo Upload

Personal photo / video gallery with iOS background sync, TUS resumable uploads, and S3-backed storage —
either the instance's own MinIO, under a per-user quota, or a bucket the user brings themselves
(AWS, Cloudflare R2, Backblaze B2, Hetzner, Wasabi, DigitalOcean, Scaleway, OVHcloud, MinIO), chosen per album.
Deployed as a Helm chart to a single-node K3s cluster.

## Components

| Path        | Stack                              | Role                                                                  |
| ----------- | ---------------------------------- | --------------------------------------------------------------------- |
| `server/`   | Spring Boot 4 / Java 25            | Backend JAR — runs as both `api` and `worker` pods (different `SPRING_PROFILES_ACTIVE`). |
| `frontend/` | Vue 3 + Vite + TypeScript + Nginx  | SPA (`picz2.oglimmer.com`).                                           |
| `ios/`      | Swift (Xcode project)              | iOS app `Zyncloud` — the primary client.                        |
| `helm/`     | Helm chart                         | K8s deploy — five workloads (api, worker, frontend, tusd, retention CronJob). |

## Local development

```bash
# Full stack on Docker (browse via http://localhost)
docker compose up

# Minimal stack — just MariaDB + Traefik, for running the server in your IDE
docker compose -f compose.local.yml up
```

Ports: api `:8080`, frontend `:5173`, MariaDB `:3306`, MinIO `:9000` / console `:9001`.

### Server

```bash
cd server
./mvnw -q -DskipTests compile
./mvnw test                                          # most tests
./mvnw test -Dtest='RetentionServiceOrphanCleanupTest'  # single class
./mvnw test -Drun.testcontainers=true                # IT classes (need real Docker daemon, not Docker Desktop)
```

### Frontend

```bash
cd frontend
npm install
npm run dev          # Vite dev server with HMR
npm run build        # vue-tsc + vite build
npm run type-check
npm run lint
```

### iOS

Open `ios/Zyncloud/Zyncloud.xcodeproj` in Xcode. Requires a paid Apple Developer account (uses background URLSessions + APNS).

## CI

GitHub Actions, one workflow per component under [`.github/workflows/`](.github/workflows/), each path-filtered to its own directory:

| Workflow | Runner | What it runs |
|---|---|---|
| `server.yml` | `ubuntu-latest`, Temurin 17 | `./mvnw test -Drun.testcontainers=true` (Docker-gated tests included) |
| `web.yml` | `ubuntu-latest`, Node 24 | `npm ci`, `lint`, `type-check`, `type-check:test`, `test`, `build` |
| `ios.yml` | `macos-26`, Xcode 26.6 | `Scripts/check-*.sh`, then `xcodebuild test` on iPhone 17 + iPad Pro 11-inch (M5) |

All three also run on `renovate/**` branch pushes — Renovate's branch automerge waits for these checks.

## Deploying to the cluster

```bash
./oglimmer.sh build -s -v          # server image — rolls api + worker
./oglimmer.sh build -f -v          # frontend image
./oglimmer.sh build -a -v          # both
./oglimmer.sh release              # bump VERSION, tag, build a release
./oglimmer.sh --help               # full options
```

The script reads `VERSION`, builds `registry.oglimmer.com/picz2-{be,fe}:<version>` plus `:latest`, pushes both, and runs `kubectl rollout restart` on the relevant Deployments. With `imagePullPolicy: Always`, the next CronJob firing also picks up the new digest.

For helm-side configuration (values, upgrade pattern, ops cookbook), see [`helm/photo-upload/README.md`](helm/photo-upload/README.md).

## Architecture & decisions

The single source of truth for *why* the codebase looks the way it does — phase history, gap inventory, decision log (D1–D60) — is **[`upload-concept-plan.md`](upload-concept-plan.md)**.

In one paragraph: backend runs as `api` and `worker` pods sharing the same JAR; api handles HTTP and serves bytes from MinIO, worker drains a `processing_jobs` table via `SELECT … FOR UPDATE SKIP LOCKED` (MariaDB ≥ 10.6 required). Every job (PROCESS / ROTATE_LEFT / REGEN_THUMBNAILS) downloads its source from S3 to an `emptyDir` workdir, runs vips/HEIC/ffmpeg locally, and PUTs derivatives back to deterministic `derivatives/{assetId}/...` keys. TUS resumable uploads land in `tus-uploads/{uuid}` via a separate tusd Deployment; a hook callback at `/api/tus/hooks/{secret}` finalises by S3-COPYing to `originals/`, inserting the row, and enqueuing a job — all in one TX. A nightly retention CronJob (also the same JAR, `retention` profile) runs three passes: aged-original purge, abandoned-TUS-upload cleanup, and orphan-key detection.

Storage is per album (D59). `storage_backends` holds one credential-free system-default row — it resolves `storage.s3.*` at runtime, so the cluster secret is never copied into a table — plus any S3-compatible endpoint a user registers for themselves; secret keys are AES-GCM encrypted with `storage.backend-secret-key`, and without that setting the feature stays off instead of failing at upload time. An album's backend is fixed at creation. tusd always writes to the system default; the finish hook server-side COPYs when the album lives there too and streams through the api pod when it does not. Retention and the orphan sweep run one bucket at a time. What a user keeps on the *system* backend is capped by `users.storage_quota_bytes` (D60, 100 MiB by default, raised with an `UPDATE`); their own buckets are neither metered nor capped, and refusals are `507`.

## Migrating from picz v1

The previous generation (`picz-api` / `picz-web`, repo `../picz`) still runs in the same
cluster. **[`bin/migrate-v1.md`](bin/migrate-v1.md)** is the runbook for moving one account's
albums and photos across; it has not been run yet beyond a 5-photo smoke test. See **D66**.

## License

MIT.
