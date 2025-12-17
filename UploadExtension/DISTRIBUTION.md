# Distribution Checklist

Use this checklist when preparing Photo Uploader for distribution.

## Pre-Distribution Setup

### 1. Update Bundle Identifiers

- [ ] Change `com.example.PhotoUploader` to your domain
- [ ] Update main app identifier in project settings
- [ ] Update ShareExtension identifier in project settings
- [ ] Verify both match pattern: `com.yourdomain.PhotoUploader` and `com.yourdomain.PhotoUploader.ShareExtension`

**Files to update:**

- `PhotoUploader.xcodeproj/project.pbxproj` (lines 390, 416, 440, 465)

### 2. Update App Metadata

- [ ] Set version number (default: 1.0)
- [ ] Add copyright information
- [ ] Update app name if desired
- [ ] Add app icon (if not already present)

**Files to update:**

- `PhotoUploader.xcodeproj/project.pbxproj` (MARKETING_VERSION)
- `PhotoUploader/Assets.xcassets/AppIcon.appiconset/`

### 3. Configure Build Settings

- [ ] Set `DEVELOPMENT_TEAM` to your Apple Team ID
- [ ] Enable "Automatically manage signing" OR
- [ ] Configure manual signing with your certificates

**Where:**

- Xcode → Target → Signing & Capabilities

## Build Options

### Option A: Unsigned Build (Testing Only)

For local testing or internal use:

```bash
./build-release.sh
```

**Pros:**

- No Apple Developer account needed
- Quick and easy
- Free

**Cons:**

- Security warnings for users
- Requires manual security bypass
- Not suitable for distribution

**Who it's for:**

- Personal use
- Internal testing
- Development builds

### Option B: Signed Build (Development)

For sharing with a small team:

```bash
# Set your team ID in Xcode
# Build with automatic signing
xcodebuild -project PhotoUploader.xcodeproj \
  -scheme PhotoUploader \
  -configuration Release \
  CODE_SIGN_IDENTITY="Apple Development"
```

**Pros:**

- Better than unsigned
- Works for registered devices

**Cons:**

- Limited distribution
- Still has warnings
- Not for public release

**Who it's for:**

- Small teams
- Beta testers with registered devices

### Option C: Signed + Notarized (Production)

For public distribution:

```bash
# Follow CODE_SIGNING.md for complete guide
./build-release-signed.sh  # (create this from guide)
./notarize.sh              # (create this from guide)
```

**Pros:**

- No security warnings
- Professional appearance
- Wide distribution

**Cons:**

- Requires Apple Developer account ($99/year)
- More complex process
- Takes time to notarize (~10 minutes)

**Who it's for:**

- Public release
- Professional distribution
- Wide audience

## Distribution Methods

### Method 1: Direct Download

Package the app as a ZIP file:

```bash
cd release
zip -r PhotoUploader-v1.0.zip PhotoUploader.app
```

**How users install:**

1. Download ZIP
2. Extract
3. Drag to Applications
4. Double-click to launch

**Pros:** Simple, direct
**Cons:** Users need to know where to get it

### Method 2: DMG Installer

Create a disk image (prettier, more professional):

```bash
# Create DMG with background image and layout
hdiutil create -volname "Photo Uploader" \
  -srcfolder release/PhotoUploader.app \
  -ov -format UDZO \
  PhotoUploader-v1.0.dmg
```

**How users install:**

1. Download DMG
2. Double-click to mount
3. Drag app to Applications folder (shown in window)
4. Eject DMG

**Pros:** Professional, guided installation
**Cons:** Slightly larger file size

### Method 3: PKG Installer

Create a package installer (for enterprise/MDM):

```bash
pkgbuild --root release/PhotoUploader.app \
  --identifier com.yourdomain.PhotoUploader \
  --version 1.0 \
  --install-location /Applications/Photo\ Uploader.app \
  PhotoUploader-v1.0.pkg
```

**How users install:**

1. Download PKG
2. Double-click
3. Follow installer prompts

**Pros:** Automated installation, MDM-compatible
**Cons:** More complex to create with customization

### Method 4: Mac App Store

Submit through App Store Connect:

1. Archive in Xcode
2. Upload to App Store Connect
3. Fill out app metadata
4. Submit for review
5. Wait for approval (1-2 weeks)

**Pros:**

- Widest distribution
- Automatic updates
- User trust

**Cons:**

- Review process
- 30% commission
- Stricter requirements
- Annual fee

## Release Checklist

### Before Building

- [ ] All code tested and working
- [ ] Version number updated
- [ ] Bundle IDs updated
- [ ] Signing configured
- [ ] README.md updated
- [ ] CHANGELOG created/updated

### Building

- [ ] Clean build successful
- [ ] App runs without errors
- [ ] Share Extension appears in Photos.app
- [ ] Upload functionality tested
- [ ] All features working

### Signing (if applicable)

- [ ] App signed with Developer ID
- [ ] Extension signed with Developer ID
- [ ] Signing verified: `codesign --verify`
- [ ] Gatekeeper accepts: `spctl --assess`

### Notarizing (if applicable)

- [ ] App submitted for notarization
- [ ] Notarization succeeded
- [ ] Ticket stapled to app
- [ ] Verified: `xcrun stapler validate`

### Packaging

- [ ] App packaged (ZIP/DMG/PKG)
- [ ] Package tested on clean Mac
- [ ] SHA-256 checksum calculated
- [ ] Release notes written
- [ ] Installation instructions included

### Distribution

- [ ] Upload to distribution platform
- [ ] Update download link
- [ ] Announce release
- [ ] Monitor for issues

## File Checklist

Include these files in your distribution:

**Essential:**

- `PhotoUploader.app` or packaged version
- `README.md` - Complete user guide
- `INSTALL.md` - Installation instructions

**Optional but Recommended:**

- `CHANGELOG.md` - Version history
- `LICENSE.txt` - Software license
- `TROUBLESHOOTING.md` - Common issues
- Sample configuration file

## Version Numbering

Follow semantic versioning: `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes (2.0.0)
- **MINOR**: New features (1.1.0)
- **PATCH**: Bug fixes (1.0.1)

Examples:

- `1.0.0` - Initial release
- `1.0.1` - Bug fix release
- `1.1.0` - Added new feature
- `2.0.0` - Major redesign

## Testing Before Release

Test on multiple systems:

- [ ] Latest macOS version (15.0+)
- [ ] Minimum supported version (14.0)
- [ ] Clean Mac (no development tools)
- [ ] Different user account
- [ ] With and without server running

Test scenarios:

- [ ] Fresh installation
- [ ] Upgrade from previous version
- [ ] First launch configuration
- [ ] Upload photos
- [ ] Upload videos
- [ ] Bulk upload (10+ files)
- [ ] Error handling (server down)
- [ ] Authentication failure

## Post-Release

After distributing:

- [ ] Monitor user feedback
- [ ] Watch for crash reports
- [ ] Check server logs for errors
- [ ] Respond to issues promptly
- [ ] Plan next release

## Support Resources

Create these for users:

1. **Download Page**
   - Current version download link
   - Checksums for verification
   - System requirements
   - Release notes

2. **Documentation**
   - Installation guide
   - Configuration guide
   - Usage tutorial
   - FAQ

3. **Support Channels**
   - GitHub Issues
   - Email support
   - Community forum
   - Documentation site

## License

Choose a license before distributing:

- **MIT License** - Very permissive, simple
- **Apache 2.0** - Permissive with patent grant
- **GPL v3** - Copyleft, requires source sharing
- **Proprietary** - Your own custom terms

Include `LICENSE.txt` in your distribution.

## Security Considerations

- [ ] No hardcoded credentials in code
- [ ] Sensitive data in Keychain only
- [ ] HTTPS for production servers
- [ ] Input validation on all user data
- [ ] Sandboxing enabled
- [ ] Minimal permissions requested

## Common Issues

### "App can't be opened because it is from an unidentified developer"

**Solution:** Sign and notarize the app (Option C)

**Workaround:** Users can right-click → Open (first time only)

### Share Extension not appearing

**Solution:** Include registration instructions in README

**User action:**

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
```

### Upload fails

**Check:**

- Server is running
- Server URL is correct
- Authentication is working
- Network connectivity

## Quick Start Scripts

Create these for easy distribution:

**For developers:**

```bash
./install.sh          # Build and install locally
./build-release.sh    # Build release version
```

**For advanced distribution:**

```bash
./build-release-signed.sh  # Build with signing
./notarize.sh             # Sign and notarize
./create-dmg.sh           # Package as DMG
```

## Support This Checklist

- Update with each release
- Keep track of issues
- Document solutions
- Share with team

---

Last updated: 2024-10-11
