# Migrating picz (v1) into Picz (v2)

Runbook for `bin/migrate_v1.py` and its launcher `bin/migrate-v1-run.sh`.

**Status: run in full on 2026-09-07.** All 3459 photos of `oglimmer@gmail.com` are in v2, both
phases complete — see [Current state](#current-state). A re-run is a no-op: every element
already carries its `content_id` marker and is skipped.

---

## Scope

Decided 2026-09-01:

| Question | Decision |
| --- | --- |
| Which accounts | **`oglimmer@gmail.com` only.** v1 user ids 7 and 89 (the same address signed in through both Keycloak and Apple) → v2 user id 1. |
| How to write | **Directly into the v2 database and MinIO**, not through `POST /api/upload`. The API path would need each user's v2 password, and v2 has no OIDC to migrate the v1 Apple/Keycloak identities onto. |
| Non-photo elements | **Skipped.** |

The other 72 v1 accounts are deliberately out of scope. 34 of them have no photo at all, and
none can log in to v2 without a password reset — v1 authenticates against
`https://id.oglimmer.de/realms/oglimmer` and `https://appleid.apple.com`, v2 against
`users.password`. Migrating a second account is a matter of running the same script with a
different `--email`, provided a v2 account with that address exists first.

## What moves

- The v1 user's **19 non-empty albums** — `album.description` becomes `albums.name`.
- **3459 `IMAGE` elements.**
- **Capture date and GPS**, read out of the v1 database (not out of the bytes — see
  [Why two phases](#why-two-phases)).
- Photo order within an album: v1's `order_no` (an epoch-ms sort key) becomes v2's
  0-based `display_order`.

The object v1 keeps at `s3://picz-images-bucket/images/<filename>` (AWS, `eu-central-1`)
becomes the v2 *original* at `originals/<stored_filename>` in the cluster MinIO bucket
`photo-upload`. The v2 worker regenerates thumb/medium/large from it.

That object is **already a derivative**: v1 resized to `max_image_width` (1200 by default)
at `jpg_quality` 0.4 before storing it, and never kept the true original in S3 — only on the
`/opt/picz-data` hostPath, which is not what `ImageStorageS3` uploads. So the migration
cannot recover better pixels than v1 itself can serve. 3448 JPEG, 11 PNG.

## What does not move

| Dropped | Count | Why |
| --- | --- | --- |
| `SECTION` elements | 182 | v2's nearest equivalent is `presentation_groups`, which is anchored to a *tag* and to a starting image. There is no faithful mapping. |
| `MAP` elements | 68 | v2 has no per-image map element. It has a per-*album* saved map view (`albums.map_center_lat` …) driven by real GPS. |
| Per-photo captions | 268 | `album_element.description` has no counterpart — `file_metadata` carries no caption column. |
| v1 `small/` renditions | — | The worker rebuilds thumb/medium/large; copying v1's would waste the space twice. |
| The album `New Album` (v1 id 259) | 1 | Empty. Pass `--include-empty-albums` to carry it anyway. |
| Share links | — | Each migrated album gets a fresh 64-hex `share_token`. Old `secret_id` links die with v1. |

## Why two phases

`ImageResizeService.removeExif` strips EXIF before v1 stores anything, so the bytes in
`picz-images-bucket` carry **no capture date and no GPS**. That matters twice:

1. The date and the coordinates have to come from the v1 `album_element` row instead.
2. `FileProcessingService` writes `gps_latitude`/`gps_longitude` **unconditionally** from
   what it extracts — including `NULL`. A PROCESS job running after the backfill would wipe
   it out.

Hence the order: upload → let the worker finish → backfill.

```
phase upload     create albums, PUT objects, insert QUEUED rows + no_tag + PROCESS jobs
   ↓  (v2 worker builds thumb/medium/large)
phase finalize   write exif_date_time_original / capture_utc_offset_seconds / gps_* from v1
```

**Timezones need no correction.** The v1 api pod runs in UTC, so
`ExifSubIFDDirectory.getDateOriginal()` — which has no zone and parses in the JVM default —
stored the camera's own wall clock as a naive UTC datetime. It is written straight through
with `capture_utc_offset_seconds = 0` and `exif_date_source = 'EXIF_FALLBACK_ZONE'`, which
keeps v2's "group by day" showing the day the shutter fired. MariaDB is on `SYSTEM` = UTC and
both script connections pin `SET time_zone = '+00:00'`, so nothing converts on the way.

## Idempotency

Every migrated row carries `content_id = 'piczv1:<v1 album_element.id>'`. The upload phase
skips any element that already has a row, and albums are matched by `(user_id, name)` —
which is v2's own unique key — so a re-run continues rather than duplicates. The script
commits once per photo, so an interruption loses at most the one in flight.

This marker is also how `--phase status` and `--phase finalize` find their rows, and how you
would undo the migration.

## Running it

The launcher deletes any previous `picz-migrate` Job, re-uploads the script as a ConfigMap,
starts a fresh Job and follows its logs. It runs **in-cluster** on purpose: the job needs
cluster DNS for `mariadb` and `minio.minio.svc.cluster.local`, and it pulls ~6 GB out of AWS
S3 — doing that through a laptop port-forward is slow and fragile.

Credentials are read from what is already deployed; nothing is passed on the command line:

| | Source |
| --- | --- |
| v1 database | `picz_prod` on `mariadb` as `picz-app`, password from secret `picz-api-env` |
| v1 AWS S3 | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` from secret `picz-api-env` |
| v2 database | configmap `photo-upload-config` + secret `photo-upload-secret` |
| v2 MinIO | same configmap and secret |

### 0. Dry run — reads only, writes nothing

```bash
bash bin/migrate-v1-run.sh --email oglimmer@gmail.com --phase upload --dry-run
```

Expect `albums touched 19, uploaded 3459, already there 0, missing in v1 S3 0` — or, after
the smoke test, `already there 5`. A non-zero **missing in v1 S3** means a v1 row points at
an object that is gone; those are reported and skipped, never fatal.

### 1. Upload — roughly 30 minutes

```bash
bash bin/migrate-v1-run.sh --email oglimmer@gmail.com --phase upload
```

Add `--no-publish` to leave the albums unpublished. The default is **published**, matching
v1, where any album was reachable by its `secret_id` link.

#### Running it in chunks

`--limit N` stops after N uploads, and the `content_id` marker makes a re-run continue rather
than duplicate, so chunking needs nothing beyond repeating the same command. This keeps the
worker queue and the MinIO PVC under control instead of dropping 3454 jobs at once:

```bash
bash bin/migrate-v1-run.sh --email oglimmer@gmail.com --phase upload --limit 500
# wait for the worker to drain, then check space and load
bash bin/migrate-v1-run.sh --email oglimmer@gmail.com --phase status
bash bin/migrate-v1-watch.sh
# repeat until 'uploaded 0'
```

**The launcher deletes the existing `picz-migrate` Job before starting a new one.** So
`--phase status` run while a chunk is still uploading kills that chunk. It is safe — the chunk
is idempotent and the next run continues — but it is not what you meant. While a chunk is in
flight, watch with `bin/migrate-v1-watch.sh` (read-only, never touches the Job) or
`kubectl -n default logs -f job/picz-migrate`.

`bin/migrate-v1-watch.sh` prints the MinIO volume, node CPU/memory, the picz2 pods and the Job
state. Pass a number of seconds to loop: `bash bin/migrate-v1-watch.sh 30`.

### 2. Wait for the worker — roughly 1–2 hours

```bash
bash bin/migrate-v1-run.sh --email oglimmer@gmail.com --phase status
```

Repeat until nothing is `QUEUED` or `PROCESSING`. Two worker pods run one job each
(`FILE_UPLOAD_MAX_CONCURRENT_PROCESSING=1`).

**Ignore the `un-finalized` line.** It counts rows where `gps_source` *and*
`exif_date_source` are both NULL, and the PROCESS job fills both in itself — so it reads 0 as
soon as the worker is done, whether or not phase `finalize` has ever run. Only the
`processing_status` counts above it mean anything here.

### 3. Finalize

```bash
bash bin/migrate-v1-run.sh --email oglimmer@gmail.com --phase finalize
```

It refuses to run while rows are still processing. `--force` does the finished ones anyway,
which is safe — the remaining ones are picked up by a later re-run.

## Verifying

```sql
-- v2: what landed, and where it got stuck
SELECT processing_status, COUNT(*)
FROM file_metadata WHERE content_id LIKE 'piczv1:%' GROUP BY processing_status;

-- v2 vs v1: spot-check date, GPS and order against the source
SELECT f.content_id, f.exif_date_time_original, f.gps_latitude, f.display_order
FROM file_metadata f WHERE f.content_id LIKE 'piczv1:%' ORDER BY f.id LIMIT 20;
```

## Rolling back

Everything the migration writes is reachable through the marker. Delete the rows and the
`image_tags` / `processing_jobs` children follow by `ON DELETE CASCADE`; the MinIO objects
are then orphans, which `POST /api/admin/purge-orphaned-s3` collects.

```sql
DELETE FROM file_metadata WHERE content_id LIKE 'piczv1:%';
-- then the albums, which are only safe to drop once they hold nothing else
DELETE FROM albums WHERE user_id = 1 AND id NOT IN (SELECT DISTINCT album_id FROM file_metadata);
```

The second statement is blunt — it would also take any *other* empty album the user owns.
Name the ids explicitly instead if that matters.

**v1 is never written to.** The script only reads `picz_prod` and `picz-images-bucket`, so a
failed migration costs nothing on the v1 side and the old deployment keeps serving.

## Capacity

~5.5 GB in MinIO: ~0.4 GB of originals plus ~5 GB of derivatives (measured at ~1.5 MB of
thumb+medium+large per photo in the smoke test, against ~100 KB originals — v1's images are
small and heavily compressed, v2's derivatives are not). The account's `storage_quota_bytes`
is 1 PiB, so the quota is not in the way — and the script writes rows directly anyway, so
`StorageQuotaService` never sees them.

**The limit is the MinIO PVC, not the node disk.** The "679 GB free" noted on 2026-09-01 was
`k8s-node19`'s root filesystem. MinIO writes into a 30 GiB Longhorn PVC (`minio/minio`), which
held 11.0 GiB used / 18.2 GiB free on 2026-09-06. The migration therefore consumes about a
third of what is left and lands near 12.7 GiB free. That fits, but it is not roomy — watch the
volume during the run, and remember that volume has no Longhorn backup.

Read it without exec'ing into anything:

```bash
kubectl get --raw "/api/v1/nodes/k8s-node19/proxy/stats/summary" \
  | jq -r '.pods[] | select(.podRef.namespace=="minio") | .volume[]? | select(.name=="export")'
```

## Current state

**Migration complete, 2026-09-07.** Run in seven chunks of 500 (`--limit 500`), each followed by a
worker drain and a `--phase status` check.

| | |
| --- | --- |
| Migrated rows | 3459, all `processing_status = DONE`, 0 queued, 0 dead-lettered |
| Albums | 19 (v2 ids 47, 50–67), published |
| Capture date | 3459 / 3459, `exif_date_source = 'EXIF_FALLBACK_ZONE'` |
| GPS | 3119 / 3459 — the other 340 carry no coordinates in v1 either |
| Missing in v1 S3 | 0 |
| MinIO volume after | 6.7 GiB free of 29.3 GiB |

The 5-photo smoke test of 2026-09-01 (album 47, files 6905–6909) was carried straight into
this run and needed no cleanup, exactly as planned.

Measured cost, against the ~5.5 GB estimate: about **8.2 GiB** of MinIO for the whole set.
The first two chunks cost ~0.6 GiB each and the rest ~1.9–2.1 GiB each — the later albums hold
bigger pictures, so do not size a future run from the first chunk alone.

`width` and `height` stay `NULL` on the migrated rows — they are `NULL` on all 3155
pre-existing v2 rows too. Nothing in v2 populates those columns.

### Still open

- **The 268 per-photo captions were dropped.** They were an accepted loss because
  `file_metadata` had no caption column. **D69** added one. `album_element.description` could
  now be backfilled onto the migrated rows through the same `content_id` marker — the data is
  still in `picz_prod`, and v1 is never written to, so nothing was lost by migrating first.
- Verify a few albums in the web client and on iOS before retiring the v1 deployment.
