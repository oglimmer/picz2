# Code Signing Guide

This guide explains how to properly sign Photo Uploader for distribution outside the Mac App Store.

## Why Sign Your App?

- **Required for macOS 10.15+**: Unsigned apps show scary warnings or won't run
- **User Trust**: Users can verify the app comes from you
- **Notarization**: Required for apps downloaded from the internet
- **Gatekeeper**: Allows smooth installation without warnings

## Prerequisites

1. **Apple Developer Account** ($99/year)
   - Sign up at: https://developer.apple.com

2. **Developer ID Certificate**
   - Type: "Developer ID Application"
   - Download from Apple Developer Portal

3. **Xcode Command Line Tools**
   ```bash
   xcode-select --install
   ```

## Step 1: Get Your Developer ID

### In Xcode:

1. Open `PhotoUploader.xcodeproj`
2. Select the PhotoUploader target
3. Go to "Signing & Capabilities" tab
4. Enable "Automatically manage signing"
5. Select your Team

### Command Line:

```bash
# List available signing identities
security find-identity -v -p codesigning

# You should see something like:
# 1) XXXX "Developer ID Application: Your Name (TEAM_ID)"
```

## Step 2: Update Bundle Identifiers

Before distributing, change from `com.example.*` to your own domain:

1. Open Xcode
2. Select **PhotoUploader** target
3. Change Bundle Identifier to: `com.yourdomain.PhotoUploader`
4. Select **ShareExtension** target
5. Change Bundle Identifier to: `com.yourdomain.PhotoUploader.ShareExtension`

Or edit directly in `PhotoUploader.xcodeproj/project.pbxproj`:

- Line 390: `PRODUCT_BUNDLE_IDENTIFIER = com.yourdomain.PhotoUploader;`
- Line 440: `PRODUCT_BUNDLE_IDENTIFIER = com.yourdomain.PhotoUploader.ShareExtension;`

## Step 3: Build with Signing

### Using build-release-signed.sh (Recommended):

Create this script:

```bash
#!/bin/bash
# Save as: build-release-signed.sh

IDENTITY="Developer ID Application: Your Name (TEAM_ID)"
PROJECT_FILE="PhotoUploader.xcodeproj"

xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "PhotoUploader" \
    -configuration Release \
    -derivedDataPath "./build" \
    clean build \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES

echo "✓ Build complete with code signing"
```

Make executable and run:

```bash
chmod +x build-release-signed.sh
./build-release-signed.sh
```

### Manual Signing:

```bash
# Build unsigned first
./build-release.sh

# Sign the app and extension
codesign --deep --force --verify --verbose \
    --sign "Developer ID Application: Your Name (TEAM_ID)" \
    --options runtime \
    --entitlements ShareExtension/ShareExtension.entitlements \
    release/PhotoUploader.app/Contents/PlugIns/ShareExtension.appex

codesign --deep --force --verify --verbose \
    --sign "Developer ID Application: Your Name (TEAM_ID)" \
    --options runtime \
    --entitlements PhotoUploader/PhotoUploader.entitlements \
    release/PhotoUploader.app

# Verify signing
codesign --verify --verbose=4 release/PhotoUploader.app
spctl --assess --verbose=4 release/PhotoUploader.app
```

## Step 4: Notarize with Apple

Notarization is required for apps distributed outside the App Store.

### Create an App-Specific Password:

1. Go to: https://appleid.apple.com
2. Sign in with your Apple ID
3. Go to "Security" → "App-Specific Passwords"
4. Click "Generate Password"
5. Name it "PhotoUploader Notarization"
6. Save the password securely

### Store credentials (one-time):

```bash
xcrun notarytool store-credentials "PhotoUploader" \
    --apple-id "your@email.com" \
    --team-id "YOUR_TEAM_ID"
# Enter the app-specific password when prompted
```

### Notarize the app:

```bash
# Create a ZIP for notarization
cd release
zip -r PhotoUploader-Notarize.zip PhotoUploader.app
cd ..

# Submit for notarization
xcrun notarytool submit release/PhotoUploader-Notarize.zip \
    --keychain-profile "PhotoUploader" \
    --wait

# If successful, staple the notarization ticket
xcrun stapler staple release/PhotoUploader.app

# Verify
xcrun stapler validate release/PhotoUploader.app
spctl --assess --verbose release/PhotoUploader.app
```

## Step 5: Create Distribution Package

```bash
# Create final ZIP for distribution
cd release
zip -r PhotoUploader-v1.0-signed.zip PhotoUploader.app
cd ..

# Calculate checksum
shasum -a 256 release/PhotoUploader-v1.0-signed.zip
```

Now you can distribute `PhotoUploader-v1.0-signed.zip`!

## Automated Script

Create `notarize.sh` for full automation:

```bash
#!/bin/bash

set -e

IDENTITY="Developer ID Application: Your Name (TEAM_ID)"
BUNDLE_ID="com.yourdomain.PhotoUploader"
APPLE_ID="your@email.com"
TEAM_ID="YOUR_TEAM_ID"
VERSION="1.0"

echo "🔨 Building signed app..."
./build-release-signed.sh

echo "📦 Creating ZIP..."
cd release
zip -r "PhotoUploader-v${VERSION}.zip" PhotoUploader.app
cd ..

echo "☁️  Submitting for notarization..."
xcrun notarytool submit "release/PhotoUploader-v${VERSION}.zip" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "@keychain:PhotoUploader-Notary" \
    --wait

echo "📌 Stapling ticket..."
xcrun stapler staple release/PhotoUploader.app

echo "✅ Verification..."
spctl --assess --verbose release/PhotoUploader.app

echo "📦 Creating final distribution package..."
cd release
rm -f "PhotoUploader-v${VERSION}.zip"
zip -r "PhotoUploader-v${VERSION}-signed.zip" PhotoUploader.app
cd ..

echo ""
echo "✓ Complete! Distribute: release/PhotoUploader-v${VERSION}-signed.zip"
```

## Troubleshooting

### "No valid signing identity found"

```bash
# Check certificates
security find-identity -v -p codesigning

# If empty, download from developer.apple.com
# Or create in Xcode: Preferences → Accounts → Manage Certificates
```

### Notarization Failed

```bash
# Get detailed log
xcrun notarytool log <submission-id> --keychain-profile "PhotoUploader"

# Common issues:
# - Hardened Runtime not enabled (add --options runtime)
# - Code signature invalid (re-sign with --deep --force)
# - Entitlements issues (verify .entitlements files)
```

### "App is damaged and can't be opened"

This means Gatekeeper is blocking it. Either:

1. App isn't signed properly
2. App isn't notarized
3. Quarantine flag is set

Fix:

```bash
xattr -cr /path/to/PhotoUploader.app
```

### "Developer cannot be verified"

- The app is signed but not notarized
- Complete Step 4 (Notarization)

## For Development Only

If you're only testing locally and not distributing:

```bash
# Build without signing
./build-release.sh

# Remove quarantine flag after copying
xattr -d com.apple.quarantine /Applications/Photo\ Uploader.app

# Or allow in System Settings:
# System Settings → Privacy & Security → Allow apps from: App Store and identified developers
# Then click "Open Anyway" when the warning appears
```

## Certificate Management

### Renew Expired Certificate:

1. Go to: https://developer.apple.com/account/resources/certificates
2. Revoke the old certificate
3. Create a new "Developer ID Application" certificate
4. Download and double-click to install
5. Rebuild and re-sign your app

### Backup Your Certificate:

```bash
# Export certificate and private key
# Open Keychain Access.app
# File → Export Items
# Save as: PhotoUploader-Certificate.p12
# Store securely (you'll need this to sign on other Macs)
```

## Resources

- [Apple Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
- [Notarization Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [TN3147: Resolving Notarization Issues](https://developer.apple.com/documentation/technotes/tn3147-resolving-common-notarization-issues)

## Quick Reference

```bash
# Check signing
codesign -dvvv PhotoUploader.app

# Check entitlements
codesign -d --entitlements :- PhotoUploader.app

# Verify signature
spctl --assess --verbose PhotoUploader.app

# Check notarization
xcrun stapler validate PhotoUploader.app

# View certificate info
security find-identity -v -p codesigning
```
