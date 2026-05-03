# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Read first

- **`upload-concept-plan.md`** — architectural source of truth (phase history, decision log D1–D31, what's done / open). Update the `Last reviewed` line at the top after non-trivial changes.
- **`README.md`** — project overview, local dev, deploy.
- **`helm/photo-upload/README.md`** — full Helm + ops reference.

## Architecture in one sentence

Backend runs as `api` and `worker` pods sharing the same JAR (different `SPRING_PROFILES_ACTIVE`); they share state via MariaDB + MinIO only; the worker drains a `processing_jobs` table via `SELECT … FOR UPDATE SKIP LOCKED`; TUS uploads go through a separate `tusd` Deployment that hooks back into the api on finish; a nightly retention CronJob (same JAR, `retention` profile) sweeps aged originals + TUS leftovers + orphan keys.

## Things to know before changing code

- **Profile gating is load-bearing.** Both pods boot the same JAR; misclassifying a `@Profile`-gated bean leads to one pod crashing on startup. Check both `Profiles.API` and `Profiles.WORKER` when adding services.
- **Storage keys are deterministic** (derived from asset id in `StoragePaths`). No path-drift recovery code is needed because paths can't drift.
- **Adding a new background operation** = add to `JobType` enum → worker method on `FileProcessingService` → switch case in `JobDispatcher` → api enqueue method on `FileStorageService` → controller endpoint returning 202. Mirror `REGEN_THUMBNAILS` or `ROTATE_LEFT`.
- **Retention is irreversible** (`RetentionService` deletes S3 originals + nulls `file_path`). If you change retention logic, set `retention.dryRun: true` for one nightly cycle and read the log first.
- **All backwards-compatibility shims have been removed** (Phase 4e R3, 2026-04-30). Don't reintroduce them for hypothetical future flexibility.
- **Migrations** (Flyway, MariaDB) live in `server/src/main/resources/db/migration/`. Every entity field must match a migrated column or the app fails to start (`ddl-auto: validate`).

## Test caveats

- Pre-existing baseline failure: `FileProcessingServiceStatusTest.successfulProcessingTransitionsToDoneAndIncrementsAttempts`. Documented in the plan; not yours to fix. Just don't add *new* failures.
- Some IT classes (`ProcessingJobLeaseTest`, `*ProfileContextTest`) are gated by `-Drun.testcontainers=true` because Docker Desktop returns stub responses to docker-java. They run cleanly on a non-Desktop daemon.

## Single-test syntax

```bash
# Server (Maven Surefire)
./mvnw test -Dtest='ClassName'                  # whole class
./mvnw test -Dtest='ClassName#methodName'       # single method
./mvnw test -Dtest='Pattern*Test'               # glob
```

All other commands (build, dev server, deploy, kubectl) are in `README.md` and `helm/photo-upload/README.md`.
