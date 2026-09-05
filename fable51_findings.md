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

**Status 2026-09-05 (second pass):** done — 404 consistency in `SlideshowRecordingService`, the `published` gate moved into `listFilesByAlbumByShareToken`, COUNT + first-image queries on `GET /api/albums`, `@Getter`/`@Setter` on the five entities with collections, the regex hoisted, the Jackson 2 bean replaced by Boot's Jackson 3 `JsonMapper`. **Decided 2026-09-05:** gallery language names stay global but renaming is admin-only (D75); `JobStatus.FAILED` folded into `DEAD_LETTER` by V51 (D76); `User.createdAt`, the repository-injecting controllers and the twin enums are left as they are on purpose; the local-disk shim was removed on branch `fable51/remove-disk-mode` (D77).

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

---

# Web app code review — findings (Fable 5.1, 2026-09-05)

Scope: `frontend/` only. Engineering practice, dead code, bugs, patterns, architecture, composition.
Method: read all 66 files under `frontend/src` (37 Vue, 28 TS, `style.css`), plus `package.json`,
`eslint.config.js`, `vite.config.ts`, `Dockerfile-prod`, `nginx.conf`. Ran `vue-tsc --noEmit`
(0 errors) and `eslint .` (0 errors, 74 warnings). There is no frontend test suite to run.

Paths are relative to `frontend/src/`.

## Bugs — fix first

**Status 2026-09-05: all eight fixed.** `vue-tsc` 0 errors, `eslint --quiet` 0 errors after the change.
Details per item below.

1. ✅ FIXED (new `utils/basicAuth.ts`, used by `useAuth` and `useUpload`) — **Login fails for any non-ASCII password.** `btoa` encodes UTF-16 code units, not UTF-8, and throws above U+00FF. Spring decodes Basic auth as UTF-8. A password with "€", Cyrillic or an emoji could be registered (the register form posts JSON) but never used to log in from the browser. `composables/useAuth.ts:41`, `:129`; `composables/useUpload.ts:56`, `:122`.
2. ✅ FIXED — **Slideshow audio listeners were never removed.** `stopPlayback` passed *new* arrow functions to `removeEventListener`, which removes nothing. The `<audio>` element is reused, so every play stacked another `timeupdate`/`ended`/`error` handler. The handlers are now kept and detached by reference. `composables/useSlideshowPlayback.ts:176-178`.
3. ✅ FIXED — **A failed `/api/capabilities` fetch was cached for the life of the page.** The comment said "don't poison the cache"; the code stored the fallback anyway. One network blip hid the map and the TUS upload path until a hard refresh. The fallback is still returned for that call, but no longer cached. `composables/useCapabilities.ts:37-45`.
4. ✅ FIXED — **`FAILED` processing status still existed in the frontend.** The server folded it into `DEAD_LETTER` (D76, V51). Removed from `types/index.ts:103`, `composables/useProcessingPoller.ts:12`, `views/GalleryView.vue:2043`, `components/GalleryItem.vue:408/417` (the hover text "Processing failed — will retry" described a state the server can no longer report).
5. ✅ FIXED — **Stale UI copy.** `views/GalleryView.vue:798` told users to upload with the macOS Share Extension, deleted in D64. Line 748 said 'Click "Manage Album Tags"'; the control is now Manage → Album tags.
6. ✅ FIXED — **Analytics writes ignored the response.** `resetAlbumAnalytics` and `setAnalyticsPaused` never checked `response.ok`, so a 403 or 500 still produced "Counting paused." / "Analytics reset." toasts. `composables/useAnalytics.ts:147-156`.
7. ✅ FIXED — **A second confirm dialog orphaned the first.** `confirm()` replaced `currentDialog` without settling the previous promise, so that caller's `await` hung forever. The previous dialog is now resolved `false` first. `composables/useConfirm.ts:25`.
8. ✅ FIXED — **`formatDate` edge cases.** It used `Math.abs` and 24-hour blocks: a photo whose camera clock is in the future read "Today"; an exact-now timestamp read "-1 days ago"; 23:50 yesterday read "Today". Now counts signed calendar days. `utils/format.ts:30-35`.

## Architecture and composition

**Status 2026-09-05 (second pass): all done.** Session tokens are **D78** (`V52`, `SessionTokenService`, `SessionTokenAuthenticationFilter`, `POST/DELETE /api/auth/sessions`); the five JS SFCs are TypeScript; `GalleryView.vue` is ~1050 lines over `composables/gallery/*` and five new components; the two galleries share `useLightboxNavigation`, `usePlaybackControls`, `useMapViewMode`, `useDayRegionView`, `countTags`, `DayRegionSections`, `PresentationSectionList`; one poller (`useProcessingPoller.waitFor`) and `useFiles.rotateFile`; `useApi.requestJson`; `composables/README.md` documents state scope; one album loader with a generation counter plus a load sequence in `useFiles`; one router guard; `utils/cookies.ts`. Verified with `vue-tsc`, `eslint`, `vite build` and the server suite (289/0). Each item below is kept as written for the record.

- **`views/GalleryView.vue` is 2917 lines of plain JavaScript.** Its `<script>` has no `lang="ts"`, so `vue-tsc` skips it, and `setup()` returns about 130 bindings. Same in `views/PublicGalleryView.vue` (914), `components/Lightbox.vue`, `components/SubscriptionDialog.vue`, `views/SubscriptionConfirmView.vue`. The other 32 SFCs use `<script setup lang="ts">`. Suggested split for GalleryView: upload flow, recording/playback, reorder mode, duplicate mode, tag picker, group dialogs, each a composable or child component.
- **`GalleryView` and `PublicGalleryView` duplicate each other.** Tag counting (`composables/useFiles.ts:42` vs `PublicGalleryView.vue:565`), `hasRecordingForLanguage`/`getRecordingForLanguage`, `navigateNext`/`navigatePrevious`, `handlePauseResume`/`handleStopPlayback`, the map and day-region wiring, and the ~80-line day-and-region template block all exist twice. Candidates: `useRecordingPicker`, `useLightboxNavigation`, `useDayRegionView`, a `DayRegionSections` component.
- **Two pollers for one endpoint.** `useProcessingPoller` and `GalleryView.awaitProcessingDone` (`:2025`) both poll `/api/assets/{id}/status` with their own backoff. `enqueueRotate` (`:2004`) is a raw `fetchWithAuth` in the view; every other file operation lives in `useFiles`. Rotate should enqueue via `useFiles` and let the poller drive the status.
- **The fetch → `json()` → `success` check → throw sequence is written ~30 times.** Several skip `response.ok` (`useFiles.loadAlbumFiles`, `useAlbums.loadAlbums`, `useTags.loadTags`, `useSettings.load*`), so a 401 HTML body surfaces as a JSON parse error. Most also wrap in `try { … } catch (err) { console.error(…); throw err }`, which adds nothing (61 `console.*` calls total). One `requestJson(url, init)` helper in `useApi` would replace nearly all of it.
- **Composable state scope is inconsistent.** `useAuth`, `useTags`, `useSettings`, `useNotifications`, `useConfirm`, `useCapabilities` hold module-level singletons. `useFiles`, `useAlbums`, `useStorageBackends`, `useSlideshow*`, `usePresentationGroups` create fresh state per call. It works only because each view calls each once; nothing documents the rule, and `AlbumAnalyticsView` already gets a `currentAlbum` that no one else sees.
- **The album load sequence is written three times in `GalleryView`** (`onMounted` `:1785`, `watch(presentationMode)` `:1828`, `watch(albumId)` `:1840`) with no cancellation token, so switching albums quickly can land a stale response last.
- **Three identical `beforeEnter` guards** in `router/index.ts` (`:37`, `:76`, `:95`). One `redirectIfLoggedIn`.
- **Three cookie parsers.** `useAnalytics.checkConsentStatus`, `CookieConsent.getConsentStatus`, `PublicGalleryView.hasConsentCookie`.
- **`useFiles.selectedTag` is watched twice with different strategies.** `useFiles.ts:65` filters client-side whenever `allFilesUnfiltered` is non-empty; `GalleryView.vue:1757` reloads from the server. In the logged-in gallery both fire on every tag change.
- **Plaintext password in `localStorage`, re-sent as Basic on every request.** `composables/useAuth.ts:73-74`. D44 already rejected "base64 is not encryption" for the tusd metadata; the same reasoning applies to the browser: any XSS is a full account takeover and there is no server-side revoke. A session cookie or short-lived token is the fix. **Decision needed** — this is an auth-model change, not a patch.
- `AlbumFile` carries both `mimeType` and `mimetype` (`types/index.ts:113-114`); the server sends only `mimetype` (`FileInfoMapper`). Drop `mimeType`. *(still open — dead-code sweep)*
- `utils/api-config.ts` hard-codes `localhost:8080` and `<ip>:8080`; a `VITE_API_URL` env override is the usual pattern and would remove the guessing.

## Dead code

**Status 2026-09-05: open** (no runtime effect; sweep in one PR).

- Types with no reference outside `types/index.ts`: `AuthState`, `FileFilters`, `SlideshowRecording`, `AlbumSettings`, `ImageTiming`, `PresentationMode`.
- `usePresentationGroups.groupEndingAt` (`:220`) — defined, exported, never called.
- `useAnalytics.visitorId` is exported but only used internally. (`verifyCredentials` and the `AuthState` type went with D78.)
- `defineExpose({ tagInput })` in `components/BulkTagBar.vue:173` and `defineExpose({ close })` in `components/MenuButton.vue:72` — no parent holds a ref to either.
- `TagManager` emits `tag-created` / `tag-updated` / `tag-deleted`; `SubscriptionDialog` emits `subscribed` — no listeners anywhere. `TagManager`'s `tags` prop duplicates the shared `useTags` state it also imports.
- `PublicGalleryView.isConfirmationMode` (`:477`) is never set true, so `SubscriptionDialog`'s `isConfirmation` branch is unreachable. `hasConsent` is destructured and unused (`:459`, eslint warns).
- `SubscriptionConfirmView.albumName` is never assigned; its template branch (`:25-27`) is dead. Its `token` is interpolated into the query string without `encodeURIComponent`.
- `GalleryView` returns `mapFilterAvailable`, `dayRegionAvailable`, `toggleFileSelection` — unused in the template. `handleDeleteSelected` (`:1592`) is a copy of `handleBulkDelete` (`:2179`). `handleDragLeave` is a no-op relayed through two components. `handleDragStart` copies `innerHTML` into `dataTransfer` for no consumer.
- `components/GalleryItem.vue:430`: `canRotate = computed(() => true)`.
- `assets/css/legal.css` is a one-line comment, imported by three views.
- `style.css` classes with no matching markup: `album-label`, `album-select`, `album-select-wrapper`, `album-selection`, `analytics-loading`, `btn-large`, `cta-section`, `feature-icon`, `highlight-feature`, `save-btn`, `target-album-panel`, `editable-title-wrapper`.
- `frontend/.idea/` is tracked in git.
- ~~`package.json` `lint` scripts pass `--ext`, which ESLint 9 flat config ignores.~~ Fixed.

## Engineering practice

**Status 2026-09-05 (second pass):** the test suite exists — vitest + jsdom, 68 tests over `utils/*` (Basic auth encoding, dates, byte sizes, tag counts, cookies, the day/region clustering incl. the camera-clock day cut and the no-chaining guarantee) and the composables (`requestJson` error shapes, the D78 session flow incl. the legacy-password migration, the poller's `waitFor`, `buildSections`/`groupContextFor`, lightbox wrap, upload error copy, selection, reorder, duplicate mode, bulk actions, the album loader's cancellation). `npm test`, `npm run type-check:test`. The ESLint `--ext` flag is gone. Still open: CI, `npm ci` and pinned images in the Dockerfile, `index.html` caching, and any component-level or browser test.

- **No frontend tests.** *(fixed, see above)* No vitest, no Playwright, nothing. `utils/dayRegionGrouping.ts` (clustering, day cut with UTC offsets), `usePresentationGroups.buildSections`, `useUpload.translateUploadError`, `utils/format.ts` and the new `utils/basicAuth.ts` are pure and cheap to cover. Any refactor of `GalleryView` needs a net first.
- **No CI.** There is no `.github/`; `oglimmer.sh` builds the image. `vue-tsc` runs in `npm run build`, but lint does not, and the ESLint config downgrades `no-explicit-any`, `no-unused-vars` and `vue/no-dupe-keys` to warn "so linting does not fail builds initially" — the 74 warnings are the result.
- **`Dockerfile-prod`** uses `npm i` instead of `npm ci` (lockfile not enforced) and unpinned `FROM node` / `nginx:latest`.
- **`nginx.conf`** caches hashed assets 30 days but sets no `Cache-Control: no-cache` on `index.html`; a stale shell can reference assets that no longer exist after a deploy.
- Cookies are set with `Secure` on every origin (`useAnalytics.ts:97`, `CookieConsent.vue:112`); on plain `http://` dev hosts other than localhost the cookie is dropped silently.

## What is good

The comments say *why*, not what. `LazyImage`'s scroll-aware loading, `PhotoMap`'s build token against overlapping builds, `useRegionNames`' batching and backoff, `useUpload`'s error translation, `dayRegionGrouping`'s complete-linkage clustering with the leader-pass fallback, and the second `hidden` filter on the public gallery are all careful, well-reasoned code. Keep the habit.
