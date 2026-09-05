# Server code review — findings (Fable 5.1, 2026-09-05)

Scope: `server/` only. Engineering practice, dead code, bugs, patterns, architecture.
Method: read all 213 Java files, the migrations, `application.yml`, and the tests that touch the findings.
The test suite was not run as part of the review itself.

Paths are relative to `server/src/main/java/com/oglimmer/photoupload/`.

## Bugs — fix first

**Status 2026-09-05: all five fixed** (D74 for the admin role). Tests: 283 run, 0 failures. Details per item below.

1. ✅ FIXED — **Any user can delete any other user's photo.** `DELETE /api/files/{id}` loads the file by id only and never checks the owner. `service/FileStorageService.java:984` (`deleteFile` uses `findById`).
2. ✅ FIXED — **Any user can reorder another user's album.** `PUT /api/files/reorder` checks that the ids exist, not who owns them. `service/FileStorageService.java:1176` (`reorderFiles` → `findExistingIds`).
3. ✅ FIXED (D74, `V50` adds `users.is_admin`; grant with SQL) — **Admin routes have no admin check.** `/api/admin/**` only needs a login. Every user gets zero roles (`security/CustomUserDetailsService.java:29`), so any user can run the S3 purge with `dryRun=false`, trigger sweeps, or read the dead-letter list. `config/SecurityConfig.java:34`.
4. ✅ FIXED — **The subscription mail job runs every minute.** Cron is `0 * * * * *`; the comment says every 6 hours. It loads every file of every subscribed album each minute. Noted in the plan doc on 2026-09-01 and still present. `service/AlbumSubscriptionNotificationService.java:38`.
5. ✅ FIXED — **Image serve turns 410 and 503 into 500.** Both handlers catch `Exception` and wrap it in `RuntimeException`; only `ResourceNotFoundException` passes through. `ResourceGoneException` (purged original) and `MinioUnavailableException` (breaker open) therefore reach the client as 500. `controller/ImageServeController.java:101` and `:138`. Same shape in `controller/SlideshowRecordingController.java:160`.

### Smaller bugs

**Status 2026-09-05 (second pass): all fixed.**

- ✅ FIXED — **Upload writes bytes before it checks album ownership.** `storeFile` resolves the album's backend and PUTs, then the insert transaction 404s on ownership. A user can push bytes into another user's S3 bucket; the object is left as an orphan. `service/FileStorageService.java:277`; TUS path at `:490`.
- ✅ FIXED — **Album delete leaks audio objects.** `deleteAlbum` cleans photo keys, then the SQL cascade drops `slideshow_recordings` rows; their `audio/` keys stay. The nightly orphan sweep only covers `originals/`, so only the manual admin purge ever reaps them. `service/AlbumService.java:271`.
- ✅ FIXED — **Album delete order is backwards.** Storage is deleted first, rows second, inside one `@Transactional`. If the DB step fails the bytes are gone and the rows point at nothing. Delete rows first; the orphan sweep already covers the other direction.
- ✅ FIXED — **`purgeOrphanedS3Objects` holds a DB connection for the whole bucket scan.** It is `@Transactional` and does S3 network calls inside. `service/FileStorageService.java:768`.
- ✅ FIXED — **Two backpressure thresholds disagree.** `web/UploadBackpressureFilter.java:88` rejects at `>=`; `service/TusHookService.java:115` rejects at `>`.
- ✅ FIXED — **Temp file leak on the multipart path.** If `computeSha256` or the duplicate check throws, the staged `.multipart-tmp` file is not deleted. `service/FileStorageService.java:265-330`.

## Dead code

**Status 2026-09-05 (second pass): removed, except `JobStatus.FAILED` — old rows may still carry that value, so the enum constant has to stay readable.**

- `FileStorageService.listFiles()` (`:548`) — no caller; also has no user filter.
- `FileStorageService.convertToFileInfoWithId` (`:414`) — one-line wrapper around `convertToFileInfo`.
- `BackendStorage.presignGet` (both overloads), `getBucket()`, `isSystemDefault()` — no callers. Two controller comments (`SlideshowRecordingController:54`, `SlideshowRecordingService:401`) still describe presigned 302 redirects that no longer exist.
- `ObjectStorageService.transfer(InputStream, …)` — no caller in main code.
- Unused injected fields: `FileController.fileMetadataRepository`, `AlbumService.albumMapper`, `AlbumService.jdbcTemplate`, `SlideshowRecordingController.analyticsService`, `SlideshowRecordingController.slideshowRecordingRepository`.
- `JobStatus.FAILED` is never written (retry re-queues as `QUEUED`).
- `TusHookService.TUS_UPLOADS_PREFIX` duplicates `StoragePaths.TUS_UPLOADS_PREFIX`.
- `Optional<CircuitBreaker>` in `UploadBackpressureFilter` is always present; the `minioCircuitBreaker` bean is unconditional.
- Stale docs: `entity/JobType.java` says the recording id travels in `asset_id`; there is a `recording_id` column now (V42). `service/FileProcessingService.java:753-758` is a javadoc block attached to nothing.

## Duplication

**Status 2026-09-05 (second pass): all six done** — `leaseIntoProcessing`/`workdirFor` in `FileProcessingService`, `enqueueSweep`/`resetAndEnqueue`/`findDuplicateByChecksum` in `FileStorageService`, `util/RandomTokens`, `UserContext` in both controllers, `storage/S3Clients`. The duplicate `catch (IOException)` arms were left; they differ per method and cost nothing.

- **`FileProcessingService`** — five job methods repeat the same prologue (flip to PROCESSING, bump attempts), work-dir creation, and catch/finally cleanup. One `runJob(id, label, body)` template would remove roughly 150 lines.
- **`FileStorageService`** — the four `enqueue*` sweeps (`:1509-1678`) have identical bodies except the query and `JobType`; `rotateImageLeft` repeats the same reset block. `storeFile` and `registerTusUpload` share ~40 lines of insert-transaction code.
- **Random tokens** — `new SecureRandom()` + hex is written out 8 times (`AlbumService` ×2, `FileProcessingService` ×2, `FileMetadata`, …). One helper.
- **Basic-auth parsing** — `UserController.extractEmailFromAuthHeader` and `AuthController.checkAuth` decode the header by hand; `UserContext` already gives the principal.
- **S3 client construction** — `config/ObjectStorageConfig.java` and `storage/StorageClientFactory.build` build the same client chain twice.
- `processFile` has `catch (IOException)` and `catch (Exception)` doing the same thing.

## Patterns and architecture

**Status 2026-09-05 (second pass):** done — 404 consistency in `SlideshowRecordingService`, the `published` gate moved into `listFilesByAlbumByShareToken`, COUNT + first-image queries on `GET /api/albums`, `@Getter`/`@Setter` on the five entities with collections, the regex hoisted, the Jackson 2 bean replaced by Boot's Jackson 3 `JsonMapper`. **Still open (need a decision or a migration):** `User.createdAt` type, global gallery language names, the local-disk shim, controllers injecting repositories, the twin status enums.

- **Not-found is inconsistent.** `SlideshowRecordingService` throws `IllegalArgumentException` for missing rows (→ 400); everything else uses `ResourceNotFoundException` (→ 404).
- **The `published` gate lives in callers.** `AlbumController` calls `requirePublishedByShareToken` and then the service; the `hidden` gate is inside the service. Both belong in `listFilesByAlbumByShareToken`.
- **`GET /api/albums` is N+1 and heavy.** `AlbumService.convertToAlbumInfo` loads every file entity of every album to count them and pick a cover, and logs at INFO per album. Use a COUNT query and a "first image" query.
- **`@Data` on JPA entities with bidirectional collections** (`Album.files`, `User.albums`, `User.tags`, `FileMetadata.imageTags`) puts lazy collections into `equals`/`hashCode`/`toString`. Prefer `@Getter`/`@Setter`.
- **Two clocks.** `User.createdAt` is `LocalDateTime`; every other entity uses `Instant`.
- **Gallery language names are global** (`GallerySettingService`), so any user changes them for every user. Check whether that is still intended.
- **Jackson 2 bean under Boot 4.** `config/WebConfig.java` defines a `com.fasterxml` `ObjectMapper`; Boot 4 MVC uses Jackson 3. Its only use is parsing the `data` string part in `SlideshowRecordingController.uploadRecording`; `@RequestPart RecordingRequest` would remove it.
- **The local-disk mode is the last big shim.** Eight classes carry `Optional<ObjectStorageService>` plus a disk fallback that production never runs (the worker has no PVC, `rotateImageLeft` rejects local paths). Tests run in that mode. CLAUDE.md says shims are gone; this is the largest remaining one.
- **Controllers that skip the service layer.** `AssetStatusController` and `AdminController` inject repositories directly; the rest of the code goes through services.
- `AlbumService.extractFirstNumber` compiles a regex per comparison inside a sort.
- `ProcessingStatus` and `JobStatus` are two enums with identical values and meaning.

## What is good

Profile gating, deterministic storage keys, the `SKIP LOCKED` lease queue, the `TransactionTemplate` discipline on the upload path, the per-backend circuit breakers, and the habit of writing down *why* in comments. Keep all of that.
