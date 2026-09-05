# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Read first

- **`upload-concept-plan.md`** — architectural source of truth (phase history, decision log D1–D60, what's done / open). Update the `Last reviewed` line at the top after non-trivial changes.
- **`README.md`** — project overview, local dev, deploy.
- **`helm/photo-upload/README.md`** — full Helm + ops reference.

## Architecture in one sentence

Backend runs as `api` and `worker` pods sharing the same JAR (different `SPRING_PROFILES_ACTIVE`); they share state via MariaDB + MinIO only; the worker drains a `processing_jobs` table via `SELECT … FOR UPDATE SKIP LOCKED`; TUS uploads go through a separate `tusd` Deployment that hooks back into the api on finish; a nightly retention CronJob (same JAR, `retention` profile) sweeps aged originals + TUS leftovers + orphan keys.

## Things to know before changing code

- **Profile gating is load-bearing.** Both pods boot the same JAR; misclassifying a `@Profile`-gated bean leads to one pod crashing on startup. Check both `Profiles.API` and `Profiles.WORKER` when adding services.
- **Storage keys are deterministic** (derived from asset id in `StoragePaths`). No path-drift recovery code is needed because paths can't drift.
- **Adding a new background operation** = add to `JobType` enum → worker method on `FileProcessingService` → switch case in `JobDispatcher` → api enqueue method on `FileStorageService` → controller endpoint returning 202. Mirror `REGEN_THUMBNAILS` or `ROTATE_LEFT`.
- **Retention is irreversible** (`RetentionService` deletes S3 originals + nulls `file_path`). If you change retention logic, set `retention.dryRun: true` for one nightly cycle and read the log first.
- **All backwards-compatibility shims have been removed** (Phase 4e R3, 2026-04-30; the local-disk storage mode followed on 2026-09-05, D77). Object storage is the only storage: `ObjectStorageService` is a required bean, `file.upload.upload-dir` is scratch space only. Don't reintroduce a disk path for hypothetical future flexibility.
- **`hidden` is a privacy boundary, not a filter.** New uploads get the tag named by `users.new_asset_tag` (D70), which defaults to `hidden`. Anything carrying `hidden` must stay out of every public path: the share-token listing, the public single-image page and subscription mails all drop it. `/api/i/{token}` is deliberately NOT gated — the owner's own clients fetch pixels through it — so never hand a hidden asset's `publicToken` to an unauthenticated caller.
- **`/api/admin/**` needs `ROLE_ADMIN`** (D74), granted from `users.is_admin` in `CustomUserDetailsService`. Everyone else is `ROLE_USER`. Grant admin with SQL, never through an endpoint. `PUT /api/settings/languages/*` is admin-only too (D75): the two language names are one instance-wide pair.
- **`JobStatus` has no `FAILED`** (D76, V51). A failed attempt goes back to `QUEUED`; out of attempts means `DEAD_LETTER`. Don't reintroduce it.
- **Migrations** (Flyway, MariaDB) live in `server/src/main/resources/db/migration/`. Every entity field must match a migrated column or the app fails to start (`ddl-auto: validate`).

## Test caveats

- The **server** suite is green (277 tests, 0 failures, 11 Docker-gated skips, as of 2026-09-05). There is no baseline failure to ignore any more — the six stale tests that used to fail were fixed, so any red test is yours.
- The **iOS** suite is separate and also green (536 tests, 0 failures, as of 2026-09-02). It is `xcodebuild test`, not Maven — see `ios/Zyncloud/README.md` for the invocation and its two traps (`CODE_SIGNING_ALLOWED=NO` breaks the keychain tests; the `StubServer` suites are process-wide).
- Some IT classes (`ProcessingJobLeaseTest`, `*ProfileContextTest`) are gated by `-Drun.testcontainers=true` because Docker Desktop returns stub responses to docker-java. They run cleanly on a non-Desktop daemon.

## Single-test syntax

```bash
# Server (Maven Surefire)
./mvnw test -Dtest='ClassName'                  # whole class
./mvnw test -Dtest='ClassName#methodName'       # single method
./mvnw test -Dtest='Pattern*Test'               # glob
```

All other commands (build, dev server, deploy, kubectl) are in `README.md` and `helm/photo-upload/README.md`.
