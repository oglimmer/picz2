# Troubleshooting Guide

## Common Issues and Solutions

### Issue: "Extension Context does not have a Principal Object" crash

**Error Message:**

```
Extension Context does not have a Principal Object
*** Assertion failure in -[NSSharingUIExtensionContext performServiceWithOptionsDictionaryData:completion:]
```

**Solution:**
This was fixed in the latest version. If you see this error:

1. **Make sure you have the latest code**
2. **Verify `ShareExtension/Info.plist` contains:**

   ```xml
   <key>NSExtensionPrincipalClass</key>
   <string>ShareExtension.ShareViewController</string>
   ```

   And does NOT contain `NSExtensionMainStoryboard`

3. **Clean and rebuild:**

   ```bash
   xcodebuild clean -scheme PhotoUploader
   xcodebuild -scheme PhotoUploader -configuration Debug
   ```

4. **Restart Photos.app:**
   ```bash
   killall Photos
   ```

See `FIX_APPLIED.md` for technical details.

### Issue: Share Extension doesn't appear in Photos.app

**Solutions:**

1. **Run the main app first**
   - Build and run PhotoUploader.app at least once
   - This registers the extension with macOS

2. **Restart Photos.app**

   ```bash
   killall Photos
   # Then reopen Photos.app
   ```

3. **Check System Settings**
   - Go to System Settings > Privacy & Security > Extensions
   - Make sure "Upload Photos" is enabled under "Share Menu"

4. **Reset Launch Services** (if still not appearing)
   ```bash
   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
   ```
   Then rebuild and run the app.

### Issue: Build fails with "Cannot find 'MediaItem' in scope"

**Solution:**
This was already fixed. Make sure you have the latest version where `MediaItem` is only defined once in `Shared/UploadService.swift`.

### Issue: Extension crashes when loading photos

**Potential causes:**

1. **Entitlements issue** - Check that `ShareExtension.entitlements` includes:
   - `com.apple.security.files.user-selected.read-only`
   - `com.apple.security.temporary-exception.files.absolute-path.read-only`

2. **Sandboxing** - Photos.app shares files via temporary locations. The entitlements are already configured for this.

### Issue: "Upload Photos" is grayed out

**Causes:**

- You've selected items that aren't photos or videos
- Mixed content types not configured in `Info.plist`

**Solution:**
Check `ShareExtension/Info.plist` and verify:

```xml
<key>NSExtensionActivationSupportsImageWithMaxCount</key>
<integer>100</integer>
<key>NSExtensionActivationSupportsMovieWithMaxCount</key>
<integer>100</integer>
```

### Issue: Upload fails immediately

**If using simulated upload:**

- Should work automatically
- Check console logs for errors

**If using real API:**

- Verify API endpoint is correct
- Check network permissions in entitlements
- Ensure API is reachable
- Check authentication headers

### Issue: Can't upload large videos

**Solutions:**

1. Increase timeout in URLSession configuration
2. Implement chunked upload
3. Add progress tracking for large files

### Issue: Bundle identifier conflicts

**Solution:**
Change the bundle IDs in the project settings:

- Main app: `com.yourcompany.PhotoUploader`
- Extension: `com.yourcompany.PhotoUploader.ShareExtension`

**Important:** The extension ID must start with the main app ID.

### Issue: Code signing errors

**Solutions:**

1. **For development:**
   - Set to "Automatically manage signing"
   - Select your development team

2. **If you don't have a team:**
   - Leave DEVELOPMENT_TEAM empty in project.pbxproj
   - Build will use ad-hoc signing (works for local testing)

### Issue: Extension UI looks wrong

The UI is created programmatically in `ShareViewController.swift`. To customize:

1. **Change colors:**

   ```swift
   statusLabel.textColor = .systemBlue
   ```

2. **Adjust layout:**

   ```swift
   statusLabel.frame = NSRect(x: 20, y: 180, width: 360, height: 30)
   ```

3. **Modify sizes:**
   ```swift
   preferredContentSize = NSSize(width: 500, height: 300)
   ```

### Debugging Tips

1. **View console logs:**

   ```bash
   log stream --predicate 'subsystem contains "com.example.PhotoUploader"' --level debug
   ```

2. **Check extension loading:**

   ```bash
   pluginkit -m -p com.apple.share-services
   ```

3. **Rebuild extension:**
   - Clean build folder: `⌘ + Shift + K`
   - Clean DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData/PhotoUploader-*`
   - Rebuild: `⌘ + B`

4. **Debug with Xcode:**
   - Debug menu > Attach to Process > Photos
   - Set breakpoints in ShareViewController.swift
   - Trigger the extension from Photos.app

### Getting Help

1. Check Xcode console for error messages
2. Look at the system console: Console.app
3. Search for the error message online
4. Check Apple's App Extension Programming Guide

### Useful Commands

```bash
# Clean build
xcodebuild clean -scheme PhotoUploader

# Build from terminal
xcodebuild -scheme PhotoUploader -configuration Debug

# Run the app
open ~/Library/Developer/Xcode/DerivedData/PhotoUploader-*/Build/Products/Debug/PhotoUploader.app

# Kill Photos.app
killall Photos

# View running extensions
pluginkit -m -v
```

## Still Having Issues?

1. Try the steps in order from this guide
2. Check the project files match the ones in this directory
3. Make sure you're running macOS 14.0 or later
4. Verify Xcode is up to date
