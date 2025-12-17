Photo Cloud Sync (iOS) — Skeleton

This is a minimal SwiftUI-based iOS app skeleton that:

- Requests photo library access.
- Finds unsynced photos using PhotoKit.
- Exports original photo/video data to a temp file.
- Uploads files via a background URLSession.
- Schedules BackgroundTasks to keep syncing periodically.

This is not a full Xcode project — add these files into a new iOS App target in Xcode and follow Setup to enable capabilities.

Setup

1. Create a new iOS App in Xcode (SwiftUI lifecycle).
2. Add all Swift files under `ios/PhotoCloudSync/` to the target.
3. Add the Info.plist keys from `InfoPlist-Additions.plist` (merge into your target Info).
4. Enable Capabilities in Signing & Capabilities:
   - Background Modes: check “Background fetch” and “Background processing”.
   - Background Processing: adds the entitlement `com.apple.developer.background-processing`.
   - Background Fetch: adds the entitlement `com.apple.developer.background-fetch`.
5. BackgroundTasks identifiers (must match code and plist):
   - com.oglimmer.photosync.process
   - com.oglimmer.photosync.refresh
6. Replace the placeholder upload endpoint in `APIClient.swift` with your backend URL and auth.
7. Update bundle identifiers in code constants if needed (search for `com.oglimmer.photosync`).

Limitations and Notes

- iOS does not allow continuous background execution. Reliable uploads use BackgroundTasks and background URLSession; uploads continue when the system grants time.
- For very large libraries, initial scan + export will take time. This sample keeps state in UserDefaults — consider Core Data for robustness, dedupe, and metadata.
- Silent push notifications can improve timeliness (not shown here). If used, add `remote-notification` to Background Modes.
- For multipart or S3 presigned flows, adjust `Uploader`/`APIClient` accordingly.

Server Expectations (simple path)

- POST /upload — accepts raw bytes as the HTTP body.
- Returns 200–299 on success.
- Optional headers read by server:
  - X-Asset-Id: the device-local PHAsset localIdentifier
  - X-Filename: original or generated filename
  - X-Mime-Type: image/jpeg, video/quicktime, etc.
  - X-Creation-Date: ISO-8601

You may prefer a two-step flow to request a presigned URL first, then PUT directly to object storage.

Testing Tips

- Run on a physical device with a real photo library.
- Watch uploads continue after pressing Home; the system may defer based on network/power.
- In Debug Schemes, enable background fetch/processing for more frequent triggers during development.

Testing Background Tasks (IMPORTANT!)

⚠️ **Background tasks DO NOT run automatically during development!** iOS uses machine learning to decide when to run them based on user behavior patterns. To test background tasks:

**Method 1: Xcode Debugger (Manual Trigger)**

1. Run the app from Xcode on a real device
2. Put the app in the background (press Home)
3. In Xcode, pause the debugger
4. In the LLDB console, type:
   ```
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.oglimmer.photosync.refresh"]
   ```
5. Resume execution - your background task handler will be called immediately

**Method 2: Command Line (Better for Testing)**

1. Build and run the app on your device
2. Close the app completely (swipe up from app switcher)
3. From Terminal, run:
   ```bash
   xcrun simctl spawn booted log stream --predicate 'subsystem == "com.apple.BackgroundTasks"' --level debug
   ```
4. To manually trigger (replace DEVICE_ID with your device UDID):
   ```bash
   xcrun devicectl device process launch --device DEVICE_ID \
     com.oglimmer.photosync --terminate-existing \
     --environment BGTaskSchedulerSimulatedLaunchIdentifier=com.oglimmer.photosync.refresh
   ```

**Method 3: Xcode Scheme Configuration**

1. In Xcode, go to Product > Scheme > Edit Scheme
2. Select "Run" in the left sidebar
3. Under "Options" tab, find "Background Fetch"
4. Check the boxes for background modes you want to simulate

**Why Background Tasks May Not Run:**

- 📱 **User behavior**: iOS learns when you use the app and schedules tasks accordingly
- 🔋 **Battery level**: Tasks may be deferred if battery is low
- 📶 **Network**: `requiresNetworkConnectivity` tasks wait for WiFi/cellular
- 🔒 **Device locked**: Some tasks only run when device is locked
- ⏰ **Time windows**: iOS decides when to grant background time (not guaranteed every 15 min)
- 🐛 **Debugging**: Tasks are paused when attached to debugger unless manually triggered

**Checking Logs:**
Monitor console logs for these messages:

- "AppDelegate: Successfully scheduled refresh task" - Task scheduling succeeded
- "SyncCoordinator: Background sync started" - Task actually executed
- Check the "Background Sync Diagnostics" section in the app's Sync tab for status

**Production Behavior:**
In production (TestFlight or App Store builds), iOS will eventually run your background tasks, but timing is unpredictable and based on:

- How frequently the user opens the app
- Device charging patterns
- Network availability
- System load and battery optimization
