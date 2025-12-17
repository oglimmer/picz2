# Quick Start Guide

## 1. Open the Project

```bash
cd /Users/oli/dev/photo-upload
open PhotoUploader.xcodeproj
```

## 2. Build & Run

1. In Xcode, select the **PhotoUploader** scheme at the top
2. Press `⌘ + R` to build and run
3. The app will launch showing instructions

## 3. Test the Share Extension

1. Open **Photos.app**
2. Select one or more photos or videos
3. Click the **Share** button (square with arrow) in the toolbar
4. Look for **"Upload Photos"** in the share menu
5. Click it to see the upload dialog

## 4. Configure Your API (When Ready)

Edit `Shared/UploadService.swift`:

```swift
// Line 8: Change the API endpoint
private var apiEndpoint = "https://your-actual-api.com/upload"

// Line 26: Replace simulated upload with real upload
// Comment out:
simulateUpload(count: mediaItems.count, progress: progress, completion: completion)

// Uncomment:
performActualUpload(mediaItems: mediaItems, progress: progress, completion: completion)
```

The actual upload implementation is already written (but commented out). Just uncomment lines 37-104 and customize for your API.

## Current State

✅ Share Extension configured and working
✅ Accepts photos and videos from Photos.app
✅ UI shows progress and item counts
✅ Upload service with placeholder (simulated upload)
⏳ REST API integration (ready for your endpoint)

## Next Steps

1. Get your REST API endpoint
2. Update `UploadService.swift` with your endpoint
3. Uncomment and customize the actual upload code
4. Add authentication if needed
5. Test with your API
6. Update bundle identifiers before distributing
