# Installation Guide

Quick installation guide for Photo Uploader.

## For End Users (Non-Developers)

### Step 1: Download

Download `PhotoUploader.zip` from the releases page or from your administrator.

### Step 2: Extract

Double-click the ZIP file to extract `PhotoUploader.app`.

### Step 3: Install

Drag `PhotoUploader.app` to your `/Applications` folder.

### Step 4: Launch

1. Go to `/Applications` and double-click `Photo Uploader`
2. If you see a security warning: **Right-click → Open** (first time only)
3. The app will launch and show setup instructions

### Step 5: Configure

Enter your server details when prompted:

- **Server URL**: Your photo server (e.g., `http://localhost:8080`)
- **Email**: Your account email
- **Password**: Your account password

Click "Save" to store your settings.

### Step 6: Test

1. Open **Photos.app**
2. Select a photo
3. Click the **Share** button (⌘+I or the share icon)
4. Select **"Upload Photos"**
5. Click **Upload**

If you don't see "Upload Photos" in the share menu:

- Restart Photos.app
- Check System Settings → Extensions → Sharing
- Enable "Upload Photos" if disabled

## For Developers

### Build from Source

```bash
# Clone the repository
cd /path/to/UploadExtension

# Run the installation script
./install.sh
```

The script will:

1. Build the app with Xcode
2. Install to `/Applications`
3. Register the Share Extension
4. Launch the app

### Manual Build

```bash
# Open in Xcode
open PhotoUploader.xcodeproj

# Build and Run
# Press ⌘+R or click the Run button

# For release build
./build-release.sh
```

### Build Output

- Debug builds: `./build/Build/Products/Debug/PhotoUploader.app`
- Release builds: `./release/PhotoUploader.app`

## System Requirements

- **macOS**: 14.0 (Sonoma) or later
- **Disk Space**: ~5 MB
- **Network**: Internet connection to reach your server
- **Server**: Photo upload API server must be running

## Permissions

The app will request:

1. **Network Access** - To upload photos to your server
2. **User Selected Files** - To read photos you select (automatically granted when you select files)

No additional permissions are needed. The app is sandboxed for security.

## Troubleshooting

### "App is damaged and can't be opened"

This happens with unsigned apps. Fix:

```bash
# Remove the quarantine flag
xattr -d com.apple.quarantine /Applications/Photo\ Uploader.app
```

Or right-click the app and select "Open" instead of double-clicking.

### Share Extension Not Appearing

Try these steps in order:

1. **Restart Photos.app** (quit completely, then reopen)

2. **Check System Settings**:
   - Go to System Settings → Extensions → Sharing
   - Look for "Upload Photos"
   - Make sure it's enabled with the checkbox

3. **Run the fix script**:

   ```bash
   ./fix-extension.sh
   ```

4. **Manual registration** (if fix script doesn't work):

   ```bash
   # Reset Launch Services
   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user

   # Register with pluginkit
   pluginkit -a /Applications/PhotoUploader.app/Contents/PlugIns/ShareExtension.appex
   pluginkit -e use -i com.example.PhotoUploader.ShareExtension

   # Restart Photos.app
   killall Photos
   open -a Photos
   ```

5. **Verify registration**:
   ```bash
   pluginkit -m -v | grep PhotoUploader
   ```
   You should see output like: `com.example.PhotoUploader.ShareExtension`

### "Could not connect to server"

- Verify server is running: `curl http://localhost:8080/auth/check`
- Check the server URL has no trailing slash
- For local servers, use `localhost` not `127.0.0.1`
- Check firewall settings

### Extension Crashes

View crash logs:

```bash
# Extension logs
log show --predicate 'process == "Photo Uploader"' --last 1h

# Or check Console.app
# Filter for "Photo Uploader" or "ShareExtension"
```

## Uninstallation

To remove Photo Uploader:

```bash
# Remove the app
rm -rf /Applications/Photo\ Uploader.app

# Remove config files (optional)
rm -rf ~/Library/Application\ Support/PhotoUploader

# Remove from keychain (optional)
# Open Keychain Access.app
# Search for "PhotoUploader"
# Delete the entries
```

## Advanced Configuration

### Custom Server Port

Edit the server URL in settings to use a custom port:

```
http://localhost:3000
http://192.168.1.100:8080
https://photos.example.com
```

### Multiple Users

Each macOS user account has separate credentials. Settings are stored per-user.

### Enterprise Deployment

To deploy to multiple Macs:

1. Build and sign the app with your Developer ID certificate
2. Notarize with Apple
3. Distribute via MDM or package installer
4. Pre-configure with a config file at:
   `/Library/Application Support/PhotoUploader/default-config.json`

## Getting Help

- Check README.md for detailed documentation
- Review server logs for API errors
- Check Console.app for app logs
- Report issues to your administrator or the developer

## Security Notes

- Credentials are stored in macOS Keychain (encrypted)
- Config file contains server URL only (no passwords)
- All uploads use your configured authentication
- The app is sandboxed and cannot access files outside of what you explicitly select
