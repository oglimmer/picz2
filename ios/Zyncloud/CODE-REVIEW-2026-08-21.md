# Zyncloud — code review, fixes applied, and next steps

**Date:** 2026-08-21
**Scope:** full read of 45 Swift files (~5.5k LOC), `project.pbxproj`, Info.plists, entitlements.
**Origin caveat:** all of this was originally produced in a Linux sandbox with **no Swift
toolchain** — nothing had been compiled or run, only structurally checked (brace balance,
`.pbxproj` parsed as an OpenStep plist, scheme validated as XML).

**Verified on macOS 2026-08-22.** The project builds, the suite is green at 77 cases, and one
real bug surfaced in the process (§3.6). One item did not survive contact: §3.5 is **not** fixed
— see the status block there. Results in §2.

---

## 1. Architecture, in brief

Two targets. The SwiftUI app follows MVVM (`Views` / `ViewModels` / `Services`); the share
extension is UIKit and largely standalone. Uploads have two paths — legacy multipart
(`Uploader`) and TUS (`TusUploader`) — chosen per batch by `SyncCoordinator.shouldUseTus()`,
which requires both the local `Settings.useTus` toggle and server-advertised
`/api/capabilities` → `tus.enabled`. Auth is HTTP Basic throughout, credentials in Keychain.
Sync is a hand-rolled queue capped at 3 concurrent uploads, with 429/503 backpressure and
post-upload processing-status polling.

The upload/sync core is well thought through — backpressure handling, checksum reconciliation
and the "why" comments are better than typical for this size. The problems cluster in **app
lifecycle wiring**, the **app/extension split**, and **project configuration**.

---

## 2. Verification — done 2026-08-22

Run on macOS, Xcode 27.0 (27A5228h), iPhone 17 simulator (iOS 26.5).

| Check | Result |
|---|---|
| Project opens, no "damaged project file" | pass |
| Three targets listed | pass |
| `ZyncloudTests` picks up the test files | pass — 47 test functions |
| `⌘B` — app target builds | pass |
| `⌘U` — tests build and run | pass — 77 cases, 0 failures |
| `Scripts/check-entitlements.sh` exits 0 | pass |
| Archive builds and is signable | builds, but signs wrong — **see §3.5** |

The first `⌘U` surfaced one genuine bug, now fixed (§3.6). Of the three snags predicted here
originally, the Swift Testing API was fine and the keychain tests did need the host app.

Two traps worth knowing before re-running any of this:

**`xcode-select` points at CommandLineTools**, so `xcodebuild` is not on PATH. Either prefix
`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` or run
`sudo xcode-select -s /Applications/Xcode-beta.app` once.

**Do not pass `CODE_SIGNING_ALLOWED=NO`.** It fails all 21 `KeychainHelperTests` cases with
`SecItemAdd → -34018` (`errSecMissingEntitlement`) — keychain access needs the signed host app.
The failures read like test bugs and are not.

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project Zyncloud/Zyncloud.xcodeproj \
  -scheme Zyncloud \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

---

## 3. What was fixed (14 issues)

### 3.1 Background TUS uploads were mis-routed on relaunch
`AppDelegate.swift` — `handleEventsForBackgroundURLSession` unconditionally handed the session
identifier to `Uploader`, so when the **TUS** session finished while the app was dead, it built
a second `URLSession` on an identifier `TusUploader` already owned, and
`TusUploader.onAllBackgroundEventsComplete` was never wired at all — meaning the system
completion handler for TUS sessions was never called. iOS punishes that with reduced background
time. Since `Settings.useTus` defaults to `true`, this was the *primary* path.

**Fix:** dispatch on the identifier; wire the callback *before* configuring the session; invoke
the system completion handler on the main thread (it was being called from the session's
delegate queue). `sessionId` changed from `private let` to `let` on both uploaders.

### 3.2 Both background sessions were re-created on every foreground
`SyncCoordinator.start()` calls `configureSession()` on both uploaders, and `start()` runs on
every `scenePhase == .active` (`RootView.swift:28`) plus three times in `SyncOptionsViewModel`.
`AppDelegate` also configured the multipart session at launch, so even the first launch created
two sessions with the same identifier. URLSession does not support this: the second session
orphans the first's delegate, and in-flight uploads lose the callback that frees their queue
slot and deletes their temp files. This is very likely the origin of the stuck
`uploads.uploading.ids` entries that `cleanupStaleUploading` exists to paper over.

**Fix:** `configureSession` returns early if a session with that identifier already exists.

**Knock-on change:** a background session's configuration is immutable after creation, so the
Wi-Fi-Only flags could no longer live there. New `URLRequest.applyNetworkPolicy()`
(`Services/Settings.swift`) is applied in `Uploader.queueUpload` and on both the TUS `POST` and
`PATCH`. Side benefit: the toggle now takes effect immediately instead of only after a session
rebuild.

**Also fixed here:** `TusUploader.shared.configureSession()` added to
`didFinishLaunchingWithOptions`. On a BGTask-only background launch no scene exists, so
`SyncCoordinator.start()` never runs — the TUS session was `nil` and `session.uploadTask` on
that implicitly-unwrapped optional would have crashed. Latent crash on the default path.

### 3.3 `applicationDidEnterBackground` was never called
`Info.plist` declares `UIApplicationSceneManifest`, so the app is scene-based and UIKit does not
call `applicationDidBecomeActive` / `applicationDidEnterBackground`. Background tasks were
therefore only scheduled at launch and from inside a running task handler — one missed handler
and scheduling stops until a cold launch.

**Fix:** `scenePhase == .background` in `ZyncloudApp.swift` now calls
`AppDelegate.scheduleBackgroundTasks()` (promoted to `static`). Both dead delegate methods were
deleted with a comment explaining why; their badge-clearing was already duplicated in `RootView`
and `ZyncloudApp`. The task handlers now call `scheduleBackgroundTasks()` directly instead
of round-tripping through `UIApplication.shared.delegate as? AppDelegate`.

### 3.4 Any password containing `:` silently broke login
`KeychainHelper` stored `"username:password"` and read it back with
`components(separatedBy: ":")` + `guard parts.count == 2`. Save succeeded, load returned `nil`,
and `RootView.checkLoginStatus()` read that as "not logged in" — a silent sign-out with no error.

**Fix:** JSON storage, plus a one-shot migration that reads legacy items by splitting on the
**first** colon only and rewrites them in the new format. The username was also removed from the
log line (it was printing on every keychain read, in release builds).

> **Verified on device 2026-08-23.** Installed the current build, signed in, upgraded in place,
> relaunched — still signed in. This was the highest-risk change in the batch: it touches every
> existing user's credentials and fails *silently*, as a sign-out with no error. It is no longer
> hypothetical.

### 3.5 Push would not have worked in TestFlight or the App Store
`aps-environment` was `development`, and one entitlements file served both Debug and Release —
so Release builds registered sandbox APNs tokens and production pushes would silently never
arrive.

**Fix:** new `Zyncloud.Release.entitlements` with `aps-environment = production`; Debug
keeps `development`. Wired into the project as a file reference, a group child, and the Release
config's `CODE_SIGN_ENTITLEMENTS`.

> **Status 2026-08-22 — not confirmed working; treat as open.** A local `xcodebuild archive`
> reports `ARCHIVE SUCCEEDED` but signs the app with `aps-environment = development` regardless.
> The entitlements file and the Release config are both correct. Automatic signing resolves
> `iOS Team Provisioning Profile: com.oglimmer.photosync` — a *development* profile — and
> reconciles the entitlements down to what that profile permits, silently and with no warning.
>
> The `CODE_SIGN_IDENTITY = "Apple Development"` pin this caveat originally predicted **has been
> removed** from the Release config. It was a real hazard, but removing it did not change the
> outcome: the profile is the cause. This machine has no App Store distribution identity (only
> Apple Development + Developer ID), so the fix cannot be verified here at all.
>
> **Verify at export time, not archive time**, on a machine with a distribution cert.
> `Scripts/check-entitlements.sh <exported .app or .xcarchive>` now asserts this against the
> *signed* binary — see §4. Note that the source-only checks passed cleanly the whole time this
> was broken, which is exactly why that mode was added.

### 3.6 `Retry-After: NaN` became a real retry delay
Found by the new tests on their first run, not by reading. `TimeInterval("NaN")` parses
successfully, so `Uploader.parseRetryAfter` returned `nan` rather than falling through to the
caller's 30 s default at `Uploader.swift:239` — and that value goes straight into a retry
deadline. `"inf"` and negative values got through the same way. `TusUploader.swift:199` had the
same bug in a shorter form (`return TimeInterval(...)`, no validation at all), which matters more
because TUS is the default path.

**Fix:** both parsers now require `seconds.isFinite, seconds >= 0`. The test's argument list grew
from `["", "soon", "30s", "-", "NaN"]` to also cover `"nan"`, `"inf"`, `"-inf"`, `"-1"`, `"-0.5"`
— that is what took the suite from 71 cases to 77.

### 3.7 The app and the share extension had separate logins (was §5.1)
Fixed 2026-08-22. `CredentialsManager` now delegates to `KeychainHelper` instead of keeping its
own item under `PhotoUploadCredentials`, so there is one credential store. Both logout paths
(`SyncOptionsViewModel.swift:192`, `ContentView.swift:177`) call `CredentialsManager.clear()`,
which signs the share sheet out as well.

`ShareExtension.entitlements` is now wired into the target via `CODE_SIGN_ENTITLEMENTS` on both
its build configurations, and `KeychainHelper.swift` is compiled into the extension through a
`membershipExceptions` entry on the `Utils` group — the same mechanism `Shared/` already used.

**Verified against the signed binary**, since the whole point of the finding was that the
entitlements file was inert. Archived before the change, `ShareExtension.appex` carried no
`keychain-access-groups` key at all; after, both the app and the appex sign with
`SBFZ9G94BG.com.oglimmer.PhotoCloudSync`.

> **Deviation from the fix proposed in §5.1:** no `kSecAttrAccessGroup` is passed explicitly.
> Both targets declare exactly one `keychain-access-groups` entry and the system uses the first
> entry as the default access group, so items already land in the shared group. Naming it in code
> would mean hardcoding the team prefix, and — more importantly — every existing user's item was
> written under the default group, so querying an explicitly-named one risks the same silent
> sign-out that §3.4 was about.
>
> **Verified on device 2026-08-23.** The share sheet inherited the app's login without a second
> sign-in, and logging out of the app left the extension asking to sign in — the security half of
> the finding, which previously stayed authenticated.
>
> **One sub-case remains unverified:** someone who signed into the share sheet but *never* into
> the app has credentials only in the old extension-private item, which
> `CredentialsManager.load()` adopts once and then deletes. That path needs a device that was in
> exactly that state before the upgrade, so it may simply not be reachable now. It is covered by
> `CredentialsManagerTests`, and its blast radius is one extra sign-in, not a silent sign-out.

### 3.8 The share extension hung on unsupported attachments (was §5.3)
Fixed 2026-08-22. `totalItemCount` counts every attachment, but the `if / else if / else if`
chain in `loadSharedItems` had no final `else`, so an attachment matching none of
fileURL/image/movie never incremented `loadedItemCount` — the counts never met,
`updateMediaSummary()` never ran, and the UI sat on "Preparing media files…" with Upload
permanently disabled. `loadItemAlternative` had the identical hole, and worse: it is called
*from* the fileURL completion, which has not counted the attachment yet.

**Fix:** both chains gained an `else` calling a new `noteUnusableAttachment()`, which increments
on the main queue and completes the batch like the other two paths. The pre-count of all
attachments was deliberately kept — counting only dispatched loads would let an instantly-
completing first attachment satisfy `loaded == total` before the loop finished queueing the rest.

Also closed the related silent drop: a payload arriving as an in-memory `UIImage`/`Data` rather
than a file URL, and both load-error paths, now increment a `skippedItemCount` that the summary
reports ("Ready to upload 3 photos (2 skipped)") instead of vanishing. Actually *uploading* an
in-memory payload needs it materialised to a temp file first, which the extension still does not
do — that part remains open.

### 3.9 Export failures retried forever (was §5.4)
Fixed 2026-08-22. A permanently un-exportable asset was re-appended every 10 s with no cap, for
as long as the app ran. Now `exportFailureCounts` tracks consecutive failures per local id and
gives up after 3, logging to `SyncLogger` with the underlying error. The asset is not marked
uploaded, so a later scan still retries it — the cap only ends the current spin. A successful
handoff clears the count, so a transient failure (an iCloud original that arrives on the second
attempt) doesn't accumulate toward a later give-up. `clearQueue()` resets the map.

### 3.10 Info.plist App Review risks (was §5.11, in part)
Fixed 2026-08-22. `NSPhotoLibraryUsageDescription` no longer says the app wants your photos
"to create audiobooks about them" — users see that string in the permission prompt.
`UIRequiredDeviceCapabilities` went `armv7` → `arm64` (32-bit was impossible against this
deployment target), and `ITSAppUsesNonExemptEncryption = false` was added so export compliance
stops being a manual answer on every upload.

`IPHONEOS_DEPLOYMENT_TARGET = 26.0` was left alone at the time and has since been **confirmed
as intentional** (2026-08-23): iOS 26 is the minimum the product wants. See §5.11.

Guarded by the new `Scripts/check-infoplist.sh` (§4), which was verified by regressing the plist
to all three original values and confirming it fails on each.

### 3.11 Background task expiry killed the app (found on device, 2026-08-23)
Found by the §6 step 3 device pass, not by reading. Simulating a `BGAppRefreshTask` launch ended
in `Debug session ended with code 9: killed` — a `SIGKILL`.

Cause: **neither expiration handler called `task.setTaskCompleted(success:)`.** The refresh
handler logged "Expired" and returned; the processing handler cancelled its queue and relied on
`op.completionBlock`, which cannot be counted on because the operation blocks in `group.wait()`
and may not finish before the system's patience runs out. iOS terminates an app that lets a
background task expire uncompleted, and reduces its future background time — so this both killed
the debug session and quietly degraded the thing §3.3 was about.

A refresh task gets a short window while `performBackgroundSync` scans the library and uploads,
so expiry here is the normal case rather than an edge case.

**Fix:** new `Services/SingleShotCompletion.swift`, a lock-guarded one-shot. Both handlers build
one and both paths — normal finish and expiry — call `fire(success:)`. Completing twice is also a
trap, and the two paths race on different threads, so a plain `Bool` would not do: two threads
could both read "not fired yet". Covered by `SingleShotCompletionTests` (6 cases), including 200
concurrent callers where exactly one must win.

### 3.12 Two API endpoints were called at paths the server does not have (found on device, 2026-08-23)
Also from the B5 device pass. With the §3.11 kill fixed, the task ran to completion and the log
showed what it had been hiding:

```
GET /api/sync/target-album          -> HTTP 500
GET /api/sync/checksums?days=4      -> HTTP 500
```

The api pod explains them: `NoResourceFoundException: No static resource api/sync/target-album`.
Nothing is mapped there, so the request falls through to static-resource handling and the error
surfaces as a **500 rather than a 404**, which is why it read like a server fault.

| Client called | Server actually exposes |
|---|---|
| `GET /api/sync/target-album` | `GET /api/settings/target-album` (`SettingsController`) |
| `PUT`/`DELETE` same path | same, on `/api/settings` |
| `GET /api/sync/checksums` | `GET /api/sync/uploaded-checksums` (`SyncController`) |

Two different mistakes: the target-album trio had the wrong controller prefix, the checksums call
the wrong resource name. Response shapes were correct — `TargetAlbumResponse` and
`SyncChecksumsResponse` match the client models — so only the four paths changed.

**Impact while broken:** every sync silently skipped both server-side checks. Target album was
never read, so the app fell back to its cached setting, and checksum reconciliation never ran —
which quietly compounds §5.8. `SyncCoordinator` logged both failures and then reported
"Background sync completed successfully", so nothing surfaced.

> **Confirmed on device 2026-08-23.** Both endpoints now answer 200 with the expected bodies —
> `{"success":true,"albumId":37}` and a checksum list — and `SyncCoordinator` logged
> "Reconciled with server, found 2 uploaded checksums", which it had never managed before.
> Checksum reconciliation is running for the first time.
>
> (An earlier unauthenticated `curl` check was inconclusive: Spring Security rejects before
> routing, so every path returns 401 whether or not it exists. The device run is the real proof.)

---

## 4. What was added (tests + a CI guard)

There were **zero** tests before this: no test target, no `XCTest`/`Testing` imports, and the
shared scheme had an empty `<TestAction>`, so `⌘U` did nothing.

### New target: `ZyncloudTests`
Unit-test bundle, hosted by the app (`TEST_HOST` / `BUNDLE_LOADER` set so keychain access
works), depends on the app target, uses a file-system-synchronized group so new test files need
no project edits. Bundle id `com.oglimmer.photosync.tests`. `ENABLE_TESTABILITY` was already
`YES` at project level. Written with **Swift Testing** (`import Testing`).

| File | Cases | What it covers |
|---|---|---|
| `KeychainHelperTests` | ~21 | Round-trip with `:`, unicode, whitespace, newlines. Legacy `"user:pass"` items being read *and* rewritten as JSON. Legacy items with colons in the password. Unparseable data → `nil`. Uses a UUID-scoped service name and cleans up, so it never touches the real credential item. |
| `TusUploadMetadataTests` | ~11 | `Upload-Metadata` framing: keys, base64 of every value, filenames containing commas/spaces/emoji, `albumId`/`auth` present only when they should be, `:`-bearing password surviving the `auth` pair. |
| `MultipartBodyTests` | 6 | Byte-exact `writeMultipartBody` framing, incl. a 130 KB non-UTF-8 payload crossing several 64 KB streaming chunks, an empty file, and the overwrite branch. |
| `ServerResponseDecodingTests` | 14 | Decoding contracts for every response model — including two tests that **document fragilities** (see §5.13, §5.14). |
| `UploadResponseParsingTests` | ~20 | `parseRetryAfter` / `parseServerAssetId`: mostly that malformed input degrades rather than crashing, since these run on background-relaunch paths where a truncated body is normal. |

**Seams added to production code** (minimal, behaviour-preserving):
`KeychainHelper.init(service:)` is now injectable (default unchanged);
`Uploader.parseServerAssetId` and `parseRetryAfter` dropped `private`.

> **Fixture caveat:** the JSON in `ServerResponseDecodingTests` was written from the *client*
> models, not captured from the live server. It locks down what the client requires — enough to
> catch accidental model drift — but is not authoritative about what the server actually sends.
> Replacing it with recorded real responses is a worthwhile follow-up.

### Second round of tests — 2026-08-22
The §3.7/§3.8/§3.9 fixes landed with no coverage, so the decisions behind them were extracted
into testable units and covered. Suite went 77 → **114 cases**.

| File | Cases | What it covers |
|---|---|---|
| `AttachmentLoadingTests` | ~20 | `AttachmentRoute` truth table over all 8 type-check combinations — the original `if / else if / else if` had exactly one combination with no answer, and that was §5.3. Plus `AttachmentLoadTally`: a batch of nothing but unusable attachments still completes, and an overcount finishes early rather than hanging. |
| `ExportRetryPolicyTests` | 8 | The §5.4 give-up rule: retries up to the cap, never returns to retrying after giving up, a success clears earlier failures, assets counted independently, cap of 1 gives up immediately. |
| `CredentialsManagerTests` | 10 | §5.1: what the extension saves the app reads and vice versa, logout signs both out, the legacy extension item is adopted once and deleted, the shared store wins over a stale legacy item, unreadable legacy data degrades to nil. `.serialized` — the seams are static and parallel cases would overwrite each other's scratch stores. |

**Seams added:** `ExportRetryPolicy` (new, extracted from `SyncCoordinator`); `AttachmentRoute` +
`AttachmentLoadTally` in `Shared/` so both the extension and the app-hosted test bundle see them;
`CredentialsManager.keychain` / `.legacyService` injectable, same rationale as
`KeychainHelper.init(service:)`.

> **These were mutation-tested.** All three original bugs were deliberately reintroduced at once
> — no retry cap, no `unusable` route, `==` instead of `>=` in `isComplete`, and a logout that
> leaves the legacy item behind — and the suite went to 9 failures across all three files. The
> tests fail when the bugs come back, which is the only property that makes them worth keeping.

### Third round — the UploadStore/Settings state machine (§6 step 7), 2026-08-22
`Settings` and `UploadStore` (both in `Services/Settings.swift`) took an injectable
`init(defaults: UserDefaults = .standard)`, and the state machine behind the "stuck uploading"
bugs is now covered. Suite went 114 → **141 cases**.

| File | Cases | What it covers |
|---|---|---|
| `UploadStoreTests` | 17 | `isUploaded` / `markAsUploading` / `markUploaded` / `removeFromUploading` / `cleanupStaleUploading` / `clear`, persistence across a restart, and checksum reconciliation. Includes the property that makes a stuck entry expensive — an in-flight upload reports as *uploaded* so the scanner skips it — and the §3.2 case that matters on relaunch: cleanup must preserve assets with live background tasks. |
| `SettingsTests` | 10 | The documented `useTus` "never written vs explicitly false" behaviour (a `bool(forKey:)` here would silently force TUS on), the other defaults, persistence, and `clear()`. |

Two tests deliberately document current behaviour rather than assert desired behaviour:
`reconcilingDoesNothingOnAFreshInstallBecauseTheLocalMapIsEmpty` pins §5.8, and
`clearRewritesTheKeysItJustRemoved` pins the fact that `clear()` removes each key and then
assigns the default, whose `didSet` writes it straight back — harmless today because the value
written *is* the default, but it means `clear()` cannot restore first-launch semantics.

> **Mutation-tested**, like the previous round. Reintroducing three bugs at once — in-flight
> uploads not counting as uploaded, cleanup ignoring live tasks, and an explicit `useTus = false`
> treated as unset — produced 5 failures across both files.

> **`@Suite(.serialized)` is required on `UploadStoreTests`, not cosmetic.** `UploadStore` guards
> its state with `queue.sync` on a concurrent `DispatchQueue`. Run in parallel, a dozen Swift
> Testing cases block cooperative threads inside `_dispatch_sync_f_slow` simultaneously and the
> whole run wedges — sampling a stuck run showed 11 threads parked in `isUploaded`. The same
> applies to `CredentialsManagerTests`, for a different reason (static seams). If a future test
> touches either, serialize it.

### Fourth round — the routing decisions (§6 step 8), 2026-08-23
The two decisions that caused §3.1 and §3.2 lived inline inside `SyncCoordinator` and
`AppDelegate`, where no test could reach them. Both are now `Services/UploadRouting.swift`, a
pure `enum` with no dependencies, and both call sites delegate to it. Suite 141 → **156 cases**.

| File | Cases | What it covers |
|---|---|---|
| `UploadRoutingTests` | 15 | `selectPath` as a full truth table (toggle × server × not-yet-loaded), and `route(forSessionIdentifier:)` including the §3.1 regression, exact-not-prefix matching, case sensitivity, and unknown identifiers still being handled rather than dropped. |

Two tests are invariants rather than examples: `theTwoUploadersUseDistinctSessionIdentifiers`
guards §3.2 directly — if those two constants ever became equal, URLSession would orphan one
session's delegate again — and `theProductionIdentifiersRouteToTheirOwnUploaders` routes the real
constants rather than copies, so renaming either one without updating the pairing fails here.

The "capabilities not yet loaded" state gets two tests of its own. It is a third state, not a
`false`, and collapsing it into the boolean is the most natural way for a future refactor to
break this quietly.

> **Mutation-tested.** Reintroducing all three at once — TUS sessions routed to `Uploader`,
> unfetched capabilities treated as "server said yes", and the user's opt-out ignored — produced
> 6 failures across the file.

### Fifth round — observability (§6 step 10), 2026-08-23
New `Services/BackgroundTaskLog.swift`: UserDefaults-backed, injectable, records when tasks were
last **scheduled** and last **run**, per kind, with run counts. Wired into
`AppDelegate.scheduleBackgroundTasks` and both handlers. The Sync tab gained two sections —
"Sync Status" (queued / uploading / uploaded / in scope / last sync, from the previously unread
`SyncCoordinator.metrics`) and "Background Tasks".

Scheduled and run are tracked separately on purpose: "scheduled but never run" is iOS declining
to grant time, "never scheduled" is our own wiring broken again — which is exactly what §3.3 was,
and it was invisible in code. `hasScheduledButNeverRun` distinguishes them and drives the footer.

| File | Cases | What it covers |
|---|---|---|
| `BackgroundTaskLogTests` | 10 | Per-kind isolation, run counts, latest-run-wins, the two "never" states being distinct, and survival across a restart — a background-only launch builds a fresh instance, and if history did not persist the screen would read "Never" on every cold start. |

Suite 156 → **166 cases**.

### `Scripts/check-entitlements.sh`
Asserts Debug→`development`, Release→`production`, and that the project references the Release
entitlements file. Shellcheck-clean. This is the mechanism for §3.5, which **no unit test can
reach**. Run it in CI or add it as a Run Script build phase.

### `Scripts/check-infoplist.sh`
Same idea for the Info.plist invariants App Review would otherwise catch: the usage string is
present and no longer mentions audiobooks, `UIRequiredDeviceCapabilities` is `arm64` and not
`armv7`, and `ITSAppUsesNonExemptEncryption` exists. Shellcheck-clean, and verified by
regressing the plist and confirming all three checks fail.

Given an optional path to an `.xcarchive` or `.app`, it also verifies the **signed**
`aps-environment` via `codesign -d --entitlements`, and on a mismatch names the provisioning
profile responsible. That mode exists because the source-only checks above returned exit 0 for a
build that was signed `development` (§3.5) — the entitlements file is not authoritative about
what actually ships, only the signed binary is.

---

## 5. Findings still open

Line numbers are current as of this document.

### High

**5.1 — The app and the share extension have separate, unsynchronized logins.** — **FIXED, see §3.7.**
The app writes `KeychainHelper` (service `com.oglimmer.photosync`); the extension reads/writes
`CredentialsManager` (service `PhotoUploadCredentials`, `Shared/Credentials.swift:10-11`, used at
`ShareViewController.swift:388, 468, 528`). So signing into the app does not sign into the share
sheet, and — more seriously — **signing out of the app leaves the extension fully
authenticated**: `SyncOptionsViewModel.swift:191` and `ContentView.swift:176` clear only
`KeychainHelper`. That violates a reasonable user expectation of "log out".

Compounding it: `ShareExtension/ShareExtension.entitlements` declares a shared
`keychain-access-groups`, but the ShareExtension target has **no** `CODE_SIGN_ENTITLEMENTS`
build setting — grep `project.pbxproj`, it appears only for the app target. That file is inert,
so keychain sharing would not work even if both sides used the same service.

*Fix:* wire the entitlements file into the target, pass `kSecAttrAccessGroup` explicitly in both
helpers, collapse to one credential store, and make logout clear it.

**5.2 — `start()` blocks the main thread for up to 4 seconds.**
`Uploader.swift:73` and `TusUploader.swift:69` use `DispatchSemaphore.wait(timeout: .now() + 2)`
around `session.getAllTasks`; `SyncCoordinator.swift:92-93` calls both, from the main thread, on
every activation. *Fix:* make `start()` async, or hop off main before the cleanup step.

**5.3 — The share extension hangs on unsupported attachment types.** — **FIXED, see §3.8.**
`ShareViewController.swift:551` counts *every* attachment into `totalItemCount`, but
`loadedItemCount` only increments at lines 716 and 741. An attachment matching none of the three
type checks — or one whose `loadItemAlternative` (line 701) also matches nothing — never
increments, so `loadedItemCount == totalItemCount` is never true, `updateMediaSummary()` never
runs, and the UI sits on "Preparing media files…" with Upload permanently disabled. Related:
line 747 silently drops any item that is not a `URL` (in-memory `UIImage`, `Data`) while still
counting it as loaded. *Fix:* count only attachments you actually dispatch a load for, and
complete on the failure paths.

**5.4 — Export failures retry forever.** — **FIXED, see §3.9.**
`SyncCoordinator.swift:421` re-appends a failed asset after 10s with no attempt cap. A
permanently un-exportable asset (iCloud original unavailable, corrupt resource) spins every ten
seconds for as long as the app runs. *Fix:* per-asset failure count with a give-up threshold
logged to `SyncLogger`.

**5.5 — Wi-Fi Only / sync-days toggles may not update visually.**
`Settings` is an `ObservableObject` held inside another (`SyncCoordinator.swift:8`). Views bind
`$sync.settings.wifiOnly` (`SyncOptionsView.swift:29, 31, 45`), but mutating a property of the
nested object never fires `SyncCoordinator.objectWillChange`, so SwiftUI has no reason to
re-render. *Fix:* observe `Settings.shared` directly in the view, or forward via
`settings.objectWillChange.sink`.

**5.20 — Real videos are never backed up: the app uploads untouched 4K originals.**
Found 2026-08-23. `Uploader.exportAsset` writes the raw `PHAssetResource` to disk
(`PHAssetResourceManager.writeData`) and uploads that; `AVAssetExportSession` appears nowhere in
the app. A 4:30 iPhone clip is ~1.6 GB, and tusd refuses anything over 500 MB with
`413 ERR_MAX_SIZE_EXCEEDED` before a byte is sent.

The library confirms the effect rather than the theory: 85 videos, 4.18 GB, mean 50 MB, **largest
ever stored 137 MB** — nothing has approached the cap because everything larger was refused. The
Toronto trip stored 397 photos (1964 MB) and **4 videos** (193 MB, largest 69 MB). This is data
loss, not a storage-efficiency issue.

*Fix (client side, unblocks everything):* export video assets through `AVAssetExportSession` at
1080p HEVC before upload — roughly 300 MB for that clip, under the existing cap, no server change.
Skip assets already ≤1080p, fall back to the original if export fails.

*Trap:* `Uploader.sha256(ofFileAt:)` hashes the **uploaded** file and feeds
`UploadStore.storeChecksumMapping`. Encoders are not byte-deterministic, so hashing a transcode
makes the local re-upload guard fail silently every run. Hash the original instead —
`contentId` is `asset.localIdentifier`, so server-side dedupe is unaffected.

*Open product question:* the server copy becomes permanently lossy. The phone keeps its 4K, but
for a lost phone the 1080p copy is what survives.

Full chain — including the server transcode having no `-vf scale`, retention leaving the
transcode as the only surviving copy for 50 of 85 videos, and the client never resuming
(`Upload-Offset` hardcoded to `0`) — is recorded as **D41** in `upload-concept-plan.md`.

### Medium

**5.6 — Temp file leaks on TUS create-failure paths.** `TusUploader.createUpload` returns at
lines 123, 129, 140, 162 (and the 429/503 branch) without deleting `exp.fileURL`. Same in
`Uploader.queueUpload` when `writeMultipartBody` throws — both the exported file and the partial
multipart file survive.

**5.7 — `UploadStore` grows unbounded in `UserDefaults`.** Every completed upload is appended to
a `Set<String>` re-serialized in full on each write, plus a parallel checksum dictionary. O(n)
per upload and an ever-growing plist. The README already flags this ("consider Core Data").

**5.8 — Checksum reconciliation is a no-op after reinstall.**
`Settings.swift:158` only marks assets present in the local `checksumToLocalId` map, which is
empty on a fresh install — so the mechanism that exists to avoid re-uploading is inert exactly
when it matters most. Server-side `contentId` dedupe (409) covers TUS, so the cost is re-export
and re-transmit, not duplicate rows.

**5.9 — Credentials travel inside `Upload-Metadata`.** `TusUploader.swift:280` and
`UploadService.swift:221`. Deliberate (tusd does not forward arbitrary headers to hooks) and
documented in-code, but base64 is not encryption and tusd persists metadata to a `.info` file on
disk. A scoped upload token would be meaningful hardening whenever the server can support one.

**5.10 — PII in release logs, and a keychain read per API call.**
`SyncCoordinator.swift:20` and `PushNotificationManager.swift:10` are computed properties that
call `KeychainHelper.shared.load()` on *every* access. `PushNotificationManager.swift:59, 67` log
token prefix and username, un-gated. *Fix:* cache the `APIClient`; move to `os.Logger` with
`privacy: .private`.

**5.11 — `Info.plist` issues.** — **usage string, `armv7` and `ITSAppUsesNonExemptEncryption` FIXED, see §3.10. Deployment target still open — your call.**
- `NSPhotoLibraryUsageDescription` reads *"…to create audiobooks about them"* — copy-paste from
  another project. Users see this in the permission prompt; so will App Review.
- `UIRequiredDeviceCapabilities` is `armv7` (32-bit) while the deployment target is iOS 26 —
  mutually impossible. Should be `arm64`.
- ~~`IPHONEOS_DEPLOYMENT_TARGET = 26.0` on both targets locks out everything below iOS 26.~~
  **Decided 2026-08-23: iOS 26 is the intended minimum and stays.** The API floor is lower
  (~iOS 18 — `MeshGradient` and `count(where:)` are the binding constraints), so this is a
  deliberate audience choice, not an oversight. Recorded here so it is not "fixed" later by
  someone reading the API floor and assuming the target drifted. Do not lower it without asking.
- No `ITSAppUsesNonExemptEncryption` — adds a manual step to every upload.

### Low / cleanup

**5.12 — Dead code.** — **FIXED 2026-08-23.** `Views/ContentView.swift` (199 lines, fully superseded by
`RootView`/`MainTabView`, and containing a *third* copy of the album-selection logic);
`DebugPushView` and `NotificationSettingsView` (never referenced from any view);
`PhotoLibraryManager.fetchAllAssets`; `APIClient.createMultipartBody` (superseded by
`writeMultipartBody`); `Data.sha256()` in `Settings.swift` (superseded by
`Uploader.sha256(ofFileAt:)`); `AlbumDetailViewModel.loadMorePhotos`; the always-`nil` computed
properties on `FileInfo`.

**5.13 — `FileInfo.tags` is non-optional**, so a server that omits the key for an untagged file
breaks the whole album listing. Documented by a test in `ServerResponseDecodingTests`
(`aFileMissingTagsFailsToDecode`). If it ever bites, change the model to `[String]?` and invert
that test.

**5.14 — `lookupAssetByContentId` decodes the *status* model just to read `id`.** That couples
TUS status polling to a field `/api/assets/by-content` has no obvious reason to return. If that
endpoint ever answers with a slimmer payload, `resolveTusUploadServerId` exhausts its retries and
polling silently stops — visible only as "Processing status unavailable" log lines. Documented by
`byContentLookupBreaksIfTheResponseOmitsProcessingStatus`.

**5.15 — Stale files.** — **FIXED 2026-08-23.** `InfoPlist-Additions.plist` (contents already merged into `Info.plist`),
`project.pbxproj.backup`, `project.pbxproj.backup2`, three `.DS_Store` files.

**5.16 — `AppConfiguration.developmentBaseURL` is unreachable** — **FIXED 2026-08-23.** (`isProduction` is a hardcoded
`let true`) and is `http://` with no ATS exception, so flipping the flag would not work without
also editing `Info.plist`. Drive it from `#if DEBUG`.

**5.17 — README is badly out of date.** — **FIXED 2026-08-23; `metrics` is now consumed by the Sync tab.** It describes the repo as a "skeleton… not a full Xcode
project", documents a `POST /upload` raw-bytes contract that no longer exists, and points at a
"Background Sync Diagnostics" section in the Sync tab that does not exist. No mention of the
share extension, TUS, albums or push. Relatedly, `SyncCoordinator.metrics` is `@Published` and
**no view consumes it**.

**5.18 — Retain cycles in alert closures.** `SyncOptionsViewModel.swift:147, 189` and
`AlbumsViewModel.swift:202` capture `self` strongly in `AlertState` actions stored on `self`.
Broken when `.alert(item:)` nils the binding, so benign in practice — but `[weak self]` is free.

**5.19 — ~200 lines of duplicated request boilerplate** — **FIXED 2026-08-23.** in `APIClient.swift`: `fetchAlbums`,
`fetchUploadedChecksums`, `getTargetAlbum`, `setTargetAlbum`, `clearTargetAlbum` each
re-implement the error ladder that `performRequest` (`APIClientExtensions.swift:201`) already
generalizes.

---

## 6. Next steps, in the order I would do them

1. ~~**Verify** — §2 checklist.~~ **Done 2026-08-22.** `⌘U` is green at 77 cases and one real
   bug fell out of it (§3.6). The archive row did *not* pass: §3.5 is still open and needs a
   distribution-signed export to close, which cannot be done on this machine.
2. ~~**Device-test the keychain migration** (§3.4).~~ **Done 2026-08-23 — passed.** Upgraded in
   place over a signed-in install and stayed signed in. The single riskiest item in the batch.
3. **Confirm the background-upload fixes on a real device.** Unit tests cannot reach these.
   **Mostly done 2026-08-23** — B1/B2/B3/B5 all passed. It found two bugs no unit test could
   reach: §3.11 (app killed on task expiry) and §3.12 (two endpoints called at paths the server
   does not have). **Still outstanding: B4**, a background upload surviving the app being killed,
   which needs a video under 500 MB.
   Suggested manual pass: queue a large video over TUS, background the app, kill it from the app
   switcher, wait for completion, relaunch — the upload should be recorded, the temp file gone,
   and no duplicate re-upload on the next scan. Use the LLDB `_simulateLaunchForTaskWithIdentifier`
   trick in the README to force BG task runs.
4. ~~**Fix 5.1** (credential stores + extension entitlements).~~ **Done 2026-08-22** — §3.7.
   Folded into the device-test pass above: the legacy-adoption path needs a real device.
5. ~~**Fix 5.3 and 5.4**~~ **Done 2026-08-22** — §3.8, §3.9.
6. ~~**Fix 5.11**~~ **Done** — §3.10 closed the two App Review risks on 2026-08-22, and on
   2026-08-23 the deployment target was decided: **iOS 26 is the intended minimum and stays.**
7. ~~**Testing phase 2**~~ **Done 2026-08-22** — see §4. 141 cases, mutation-tested.
8. **Fix 5.20 / D41** — 1080p export before upload. Highest user-visible severity of what
   remains: right now no real video reaches the server at all.
9. ~~**Testing phase 3**~~ **Done 2026-08-23** — see §4. All three landed: attachment counting
   in `AttachmentLoadingTests`, and `shouldUseTus()` plus background-session routing in
   `UploadRoutingTests`. 156 cases, mutation-tested.
10. **Observability, not tests** — surface `SyncCoordinator.metrics` plus last-scheduled and
   last-run background-task timestamps in the Sync tab. §3.3 was undetectable in code; it would
   have been obvious on that screen. This also makes the README's claim true.
10. ~~**Observability**~~ **Done 2026-08-23** — see §4. The Sync tab now shows metrics and
    background-task timestamps.
11. ~~**Cleanup pass**~~ **Done 2026-08-23.** 5.12 (three dead views incl. the 199-line
    `ContentView.swift`, plus `fetchAllAssets`, `createMultipartBody`, `loadMorePhotos`,
    `Data.sha256`), 5.15 (`InfoPlist-Additions.plist`, two `.pbxproj` backups, three `.DS_Store`),
    5.16 (`AppConfiguration` now overridable via `ZYNCLOUD_BASE_URL` in Debug instead of an
    unreachable `isProduction = true`), 5.17 (README rewritten), 5.19 (`APIClient.validate`
    extracted; the five endpoints delegate — `APIClient.swift` 350 → 158 lines).

---

## 7. Files changed in this session

**Modified**
- `ShareExtension/ShareViewController.swift` — attachment accounting, skipped-item reporting
- `Services/SyncCoordinator.swift` — export failure cap
- `AppDelegate.swift` — session routing, static scheduling, dead delegate methods removed
- `ZyncloudApp.swift` — `scenePhase == .background` schedules BG tasks
- `Services/Uploader.swift` — idempotent session, per-request network policy, parsers internal, `parseRetryAfter` validation
- `Services/TusUploader.swift` — idempotent session, per-request network policy, `parseRetryAfter` validation
- `Services/Settings.swift` — new `URLRequest.applyNetworkPolicy()`; `Settings` and `UploadStore`
  take an injectable `UserDefaults`
- `Utils/KeychainHelper.swift` — JSON storage, legacy migration, injectable service; now
  compiled into the ShareExtension target too
- `Shared/Credentials.swift` — `CredentialsManager` delegates to `KeychainHelper`, adopts and
  deletes the legacy extension item
- `ViewModels/SyncOptionsViewModel.swift`, `Views/ContentView.swift` — logout clears both
- `Zyncloud.xcodeproj/project.pbxproj` — Release entitlements, test target, Release
  `CODE_SIGN_IDENTITY` pin removed, ShareExtension entitlements wired in, `KeychainHelper.swift`
  shared with the extension
- `Zyncloud.xcodeproj/xcshareddata/xcschemes/Zyncloud.xcscheme` — testable reference

**Added**
- `Services/ExportRetryPolicy.swift`, `Shared/AttachmentLoading.swift`,
  `Services/UploadRouting.swift` — extracted decisions
- `ZyncloudTests/` — now ten files (added attachment, retry, credentials, store, settings)
- `Scripts/check-infoplist.sh`
- `Zyncloud.Release.entitlements`
- `ZyncloudTests/` — five test files
- `Scripts/check-entitlements.sh` — source invariants plus optional signed-binary check
- `CODE-REVIEW-2026-08-21.md` — this file
