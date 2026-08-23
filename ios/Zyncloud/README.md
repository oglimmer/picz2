# Zyncloud (iOS)

The iOS client for the picz2 photo server: it finds photos and videos the server does not
have yet, uploads them in the background, and shares them from the system share sheet.

Named `Zyncloud` as of 2026-08-22. The bundle identifier is still `com.oglimmer.photosync`
and deliberately stays that way — it is what identifies the app to the App Store, the keychain
and APNs, and changing it would orphan every existing install.

## Requirements

**iOS 26 minimum**, deliberately. The code's actual API floor is lower, so a lower target would
compile — that is not a reason to change it. See §5.11 in `CODE-REVIEW-2026-08-21.md`.

## Layout

Open `Zyncloud.xcodeproj`. Three targets:

| Target | What it is |
|---|---|
| `Zyncloud` | The SwiftUI app. MVVM — `Views` / `ViewModels` / `Services`. |
| `ShareExtension` | UIKit share sheet extension. Largely standalone; shares `Shared/` with the app. |
| `ZyncloudTests` | Swift Testing unit tests. File-system-synchronized, so new files need no project edit. |

`Shared/` is compiled into both the app and the extension (via `membershipExceptions` on the
group), as is `Utils/KeychainHelper.swift` — that is how both sides read the same login.

## Uploading

Two paths, chosen per batch by `UploadRouting.selectPath`:

- **TUS** (`TusUploader`) — the default. `POST /files/` to create, then `PATCH` the bytes.
- **Multipart** (`Uploader`) — the legacy path, used when the user opts out or when
  `/api/capabilities` has not been fetched yet.

Both run on background `URLSession`s so uploads continue after the app is suspended. The two
sessions must keep **distinct identifiers** (`…​.tus` and `…​.upload`); URLSession does not support
two sessions sharing one, and `UploadRoutingTests` guards it.

Auth is HTTP Basic throughout, credentials in the keychain, shared with the extension through the
`com.oglimmer.PhotoCloudSync` access group.

### Known limitation

Videos are uploaded as **untouched originals**, so anything over tusd's 500 MB cap is refused with
`413` before a byte is sent — which in practice means most real 4K footage. See **D41** in
`upload-concept-plan.md`. This is the largest open issue in the client.

## Building and testing

`xcode-select` may point at CommandLineTools, in which case `xcodebuild` is not on PATH:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project Zyncloud.xcodeproj \
  -scheme Zyncloud \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

**Do not pass `CODE_SIGNING_ALLOWED=NO`.** It fails every `KeychainHelperTests` case with
`errSecMissingEntitlement` — keychain access needs the signed host app, and the failures look
like broken tests rather than a broken invocation.

`UploadStoreTests` and `CredentialsManagerTests` are `@Suite(.serialized)` and must stay that way:
the first blocks on `DispatchQueue.sync` and wedges the run in parallel, the second mutates static
seams.

### Guard scripts

Neither invariant is reachable from a unit test, so both are shell scripts — run them in CI:

```bash
Scripts/check-entitlements.sh                       # source invariants
Scripts/check-entitlements.sh <exported .app>       # plus the *signed* aps-environment
Scripts/check-infoplist.sh                          # usage string, arm64, device family, encryption
```

## Pointing at a different server

Release builds always use production. Debug builds honour the `ZYNCLOUD_BASE_URL` environment
variable (Product → Scheme → Edit Scheme → Run → Arguments). A plain `http://` address also needs
a local, uncommitted ATS exception in `Info.plist`.

## Background tasks

Two identifiers, which must match `Info.plist`:

- `com.oglimmer.photosync.process` — `BGProcessingTask`, network + CPU
- `com.oglimmer.photosync.refresh` — `BGAppRefreshTask`, quick checks

Scheduling happens on the scene's background transition. It is deliberately **not** in
`applicationDidEnterBackground`: the app is scene-based, so UIKit never calls that, and for a
long time tasks were only scheduled at launch.

**They do not run automatically during development.** To force one, pause the debugger with the
app backgrounded and run:

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] \
  _simulateLaunchForTaskWithIdentifier:@"com.oglimmer.photosync.refresh"]
```

The **Sync tab** shows last-scheduled and last-run timestamps per task, plus queue depth and
upload counts. "Scheduled, never run" is normal for a while after install; permanently never run
is not.

## Related documents

- `CODE-REVIEW-2026-08-21.md` — findings, what was fixed, what is still open.
- `../../upload-concept-plan.md` — architecture and the D1–D41 decision log.
