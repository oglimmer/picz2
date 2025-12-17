# Photo Uploader for macOS

A macOS Share Extension that integrates seamlessly with Photos.app, allowing you to upload photos and videos directly to your server with just a few clicks.

## Features

- **Photos.app Integration** - Appears in the native macOS Share menu
- **Bulk Uploads** - Upload up to 100 photos/videos at once
- **Progress Tracking** - Real-time progress bar and status updates
- **Album Support** - Upload directly to specific albums
- **Authentication** - Basic Auth support for secure uploads
- **All Formats** - Supports JPEG, PNG, HEIC, MOV, MP4, and more

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later (for building from source)
- A server running the photo upload API (e.g., Spring Boot backend)

## Quick Install

### Option 1: Install Pre-built App (Easiest)

1. Download the latest `PhotoUploader.app` from releases
2. Move `PhotoUploader.app` to your `/Applications` folder
3. Double-click to launch the app (this registers the Share Extension)
4. Follow the setup wizard to configure your server

### Option 2: Build from Source

```bash
# Clone or navigate to the project
cd /path/to/UploadExtension

# Run the installation script
./install.sh
```

The script will:

- Build the app with Xcode
- Install it to `/Applications`
- Launch it automatically
- Guide you through configuration

### Option 3: Manual Build

```bash
# Open the project in Xcode
open PhotoUploader.xcodeproj

# Build and run (⌘+R)
# The app will launch and register the extension
```

## Configuration

### First Launch Setup

When you first launch Photo Uploader, you'll be prompted to configure:

1. **Server URL** - Your photo upload server endpoint (e.g., `http://localhost:8080`)
2. **Email** - Your account email for authentication
3. **Password** - Your account password

The credentials are stored securely in your system keychain.

### Manual Configuration

You can also configure the app by editing `~/Library/Application Support/PhotoUploader/config.json`:

```json
{
  "serverUrl": "http://localhost:8080",
  "email": "your-email@example.com"
}
```

Note: Passwords are stored in macOS Keychain, not in the config file.

## Usage

### Uploading Photos

1. Open **Photos.app**
2. Select one or more photos or videos
3. Click the **Share** button in the toolbar
4. Select **"Upload Photos"** from the share menu
5. (Optional) Choose an album from the dropdown
6. Click **Upload**
7. Wait for the progress bar to complete

### Managing Albums

To upload to a specific album:

- The album dropdown will show all available albums from your server
- Select an album before clicking Upload
- Or leave it as "No Album" for the default location

## Troubleshooting

### Extension Doesn't Appear in Share Menu

```bash
# Reset the share extensions database
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user

# Restart the app
open -a "Photo Uploader"
```

### Upload Fails with "No Internet Connection"

- Check that your server is running and accessible
- Verify the server URL in settings (no trailing slash)
- For local servers: use `http://localhost:8080`, not `127.0.0.1`

### Authentication Errors

- Verify your credentials in the app settings
- Check that your server's authentication endpoint is working
- Try logging out and logging back in

### Large Files Timeout

- The upload timeout is set to 120 seconds per file
- For very large videos, consider adjusting the timeout in code
- Check your server's upload size limits

### Permission Issues

The app requires these permissions:

- **Network Access** - To upload files to your server
- **User Selected Files** - To read photos you select in Photos.app

These permissions are requested automatically.

## For Developers

### Project Structure

```
.
├── PhotoUploader/          # Main app
│   ├── PhotoUploaderApp.swift
│   ├── ContentView.swift
│   └── Assets.xcassets/
├── ShareExtension/         # Share Extension
│   ├── ShareViewController.swift
│   ├── Info.plist
│   └── ShareExtension.entitlements
├── Shared/                 # Shared code
│   ├── UploadService.swift
│   └── Credentials.swift
└── PhotoUploader.xcodeproj/
```

### Building for Distribution

```bash
# Build release version
./build-release.sh

# Output: PhotoUploader.app in ./build/Release/
```

### Code Signing

To distribute the app outside the App Store:

1. Update `DEVELOPMENT_TEAM` in project settings
2. Set your Apple Developer Team ID
3. Enable "Sign to Run Locally" or use your distribution certificate
4. Notarize the app for Gatekeeper (required for macOS 10.15+)

```bash
# Sign the app
codesign --deep --force --sign "Developer ID Application: Your Name" PhotoUploader.app

# Notarize (requires Apple ID)
xcrun notarytool submit PhotoUploader.app --apple-id "your@email.com" --wait

# Staple the notarization
xcrun stapler staple PhotoUploader.app
```

### Customization

#### Change App Name

1. Update `PRODUCT_NAME` in project settings
2. Update `CFBundleDisplayName` in Info.plist
3. Update folder names if desired

#### Change Bundle Identifiers

Current IDs:

- Main app: `com.example.PhotoUploader`
- Extension: `com.example.PhotoUploader.ShareExtension`

Update in:

- Project settings > General > Bundle Identifier
- ShareExtension/Info.plist

#### Customize Upload Logic

Edit `Shared/UploadService.swift`:

- Modify `uploadFile()` for custom multipart format
- Add headers or authentication methods
- Change API endpoints

## Server API Requirements

Your server should implement:

### Upload Endpoint

```
POST /upload
Content-Type: multipart/form-data
Authorization: Basic <base64-encoded-credentials>

Form fields:
- file: The photo/video file
- albumId (optional): Target album ID
```

Response:

```json
{
  "success": true,
  "message": "File uploaded successfully"
}
```

### Authentication Endpoint

```
GET /auth/check
Authorization: Basic <base64-encoded-credentials>
```

Response:

```json
{
  "email": "user@example.com",
  "authenticated": true
}
```

### Albums Endpoint (Optional)

```
GET /albums
Authorization: Basic <base64-encoded-credentials>
```

Response:

```json
[
  { "id": 1, "name": "Vacation 2024" },
  { "id": 2, "name": "Family" }
]
```

## Privacy & Security

- **Local Processing** - All photos are processed locally on your Mac
- **Keychain Storage** - Passwords are stored securely in macOS Keychain
- **No Third Parties** - Data goes directly to your configured server
- **Sandboxed** - The app runs in a secure sandbox environment
- **User Control** - You explicitly select which photos to upload

## Support

- Report issues on GitHub
- Check documentation at your server's URL
- Review logs: `~/Library/Logs/PhotoUploader/`

## License

[Add your license here]

## Changelog

### Version 1.0

- Initial release
- Basic photo/video upload functionality
- Album support
- Basic authentication
- Progress tracking
