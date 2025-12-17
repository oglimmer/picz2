# Photo Uploader - macOS Share Extension

A complete photo upload solution with a macOS Share Extension and Node.js server that allows you to upload photos and videos from Photos.app to a local or remote server.

## Features

### macOS Extension

- ✅ Share Extension integration with Photos.app
- ✅ Support for multiple photos and videos (up to 100)
- ✅ Progress indicator during upload
- ✅ Clean, native macOS UI
- ✅ Real file uploads with progress tracking

### Node.js Server

- ✅ Express-based upload server
- ✅ Multer for file handling
- ✅ File type validation
- ✅ Automatic unique filenames
- ✅ CORS enabled
- ✅ File size limits (configurable)
- ✅ REST API endpoints

## Project Structure

```
PhotoUploader/
├── PhotoUploader/              # Main app
│   ├── PhotoUploaderApp.swift
│   ├── ContentView.swift
│   └── Assets.xcassets/
├── ShareExtension/             # Share Extension
│   ├── ShareViewController.swift
│   ├── Info.plist
│   └── ShareExtension.entitlements
└── Shared/                     # Shared code
    └── UploadService.swift     # Upload logic
```

## Quick Start

**See START.md for detailed step-by-step instructions.**

### 1. Start the Server

```bash
cd server
npm install
npm start
```

### 2. Build the Extension

```bash
open PhotoUploader.xcodeproj
# Press ⌘+R
```

### 3. Test It

1. Open Photos.app
2. Select photos/videos
3. Share → "Upload Photos"
4. Watch files upload to `server/uploads/`

## Complete Guide

- **START.md** - Quick start guide
- **INTEGRATION_GUIDE.md** - Full integration documentation
- **server/README.md** - Server API documentation

## How It Works

### Upload Flow

1. User selects photos/videos in Photos.app
2. Clicks Share → "Upload Photos"
3. Extension loads selected media
4. User clicks "Upload" button
5. Files are uploaded to `http://localhost:3000/upload`
6. Server saves files to `server/uploads/`
7. Success message shown

### Current Configuration

- **Server:** `http://localhost:3000/upload`
- **Method:** HTTP POST with multipart/form-data
- **Files:** Uploaded individually with progress tracking
- **Storage:** `server/uploads/` directory

### Changing the Server URL

Edit `Shared/UploadService.swift:7`:

```swift
private var apiEndpoint = "http://localhost:3000/upload"
// Change to your server:
private var apiEndpoint = "https://your-server.com/upload"
```

## Entitlements

The app uses the following entitlements:

- **App Sandbox:** Enabled for security
- **Network Client:** Required for API uploads
- **User Selected Files (Read-Only):** Access shared files from Photos.app
- **Temporary File Access:** Read photos/videos from Photos.app's temporary location

## Bundle Identifiers

- Main App: `com.example.PhotoUploader`
- Share Extension: `com.example.PhotoUploader.ShareExtension`

**Important:** Change these to match your developer account before distributing.

## Supported Media Types

- **Images:** All formats supported by Photos.app (JPEG, PNG, HEIC, etc.)
- **Videos:** All formats supported by Photos.app (MOV, MP4, etc.)
- **Max items:** 100 photos or videos per upload (configurable in Info.plist)

## Customization

### Change the display name:

Edit `ShareExtension/Info.plist`:

```xml
<key>INFOPLIST_KEY_CFBundleDisplayName</key>
<string>Your Custom Name</string>
```

### Adjust supported file types:

Edit `ShareExtension/Info.plist` under `NSExtensionActivationRule`:

```xml
<key>NSExtensionActivationSupportsImageWithMaxCount</key>
<integer>100</integer>
<key>NSExtensionActivationSupportsMovieWithMaxCount</key>
<integer>100</integer>
```

## Troubleshooting

### Share Extension doesn't appear:

1. Make sure the main app runs at least once
2. Restart Photos.app
3. Check System Settings > Privacy & Security > Extensions

### Upload fails:

1. Check network permissions in entitlements
2. Verify API endpoint is correct
3. Check console logs for error messages

### Can't access photos:

1. Ensure file access entitlements are configured
2. Check that Photos.app has proper permissions
3. Verify share extension is signed correctly

## License

MIT License - Feel free to modify and use as needed.
