# Testing Steps - Updated

## Recent Fixes Applied

1. ✅ Fixed "Extension Context does not have a Principal Object" error
2. ✅ Added file URL support for better Photos.app compatibility
3. ✅ Improved item loading with fallback mechanisms
4. ✅ Added support for `NSExtensionActivationSupportsFileWithMaxCount`

## Complete Testing Procedure

### Step 1: Clean Rebuild (Important!)

```bash
# Clean previous builds
xcodebuild clean -scheme PhotoUploader

# Rebuild
xcodebuild -scheme PhotoUploader -configuration Debug
```

### Step 2: Kill Any Running Instances

```bash
# Kill Photos.app
killall Photos 2>/dev/null || true

# Kill any running instances of the extension
killall -9 ShareExtension 2>/dev/null || true

# Reset Launch Services cache (optional but recommended)
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
```

### Step 3: Run the App Once

```bash
# Find and run the built app
open ~/Library/Developer/Xcode/DerivedData/PhotoUploader-*/Build/Products/Debug/PhotoUploader.app
```

**Wait** for the app to fully launch, then you can close it.

### Step 4: Start the Server

```bash
cd server
npm start
```

You should see:

```
📸 Photo Upload Server Running
Server: http://localhost:3000
```

### Step 5: Test in Photos.app

1. **Open Photos.app** (fresh launch)
2. **Select 1-3 photos** (start small for testing)
3. **Click the Share button** (toolbar or right-click)
4. **Look for "Upload Photos"** in the share menu

### Step 6: Use the Extension

If "Upload Photos" appears:

1. Click it
2. Extension window should appear
3. Should show: "Ready to upload" and photo count
4. Click "Upload" button
5. Watch progress bar
6. Should show "Successfully uploaded N items!"

### Step 7: Verify Upload

```bash
# Check uploaded files
ls -lh server/uploads/

# Should show your uploaded files with timestamps
```

## Debugging

### If Extension Doesn't Appear

```bash
# Check if extension is registered
pluginkit -m -p com.apple.share-services | grep -i upload

# If not found, try:
pluginkit -a ~/Library/Developer/Xcode/DerivedData/PhotoUploader-*/Build/Products/Debug/PhotoUploader.app/Contents/PlugIns/ShareExtension.appex

# Then restart Photos
killall Photos
```

### If Extension Crashes

Check Console.app or run:

```bash
log stream --predicate 'subsystem contains "ShareExtension"' --level debug
```

Then try the extension again and watch for errors.

### View Detailed Logs

**Terminal 1 - Server logs:**

```bash
cd server && npm start
```

**Terminal 2 - System logs:**

```bash
log stream --predicate 'process == "ShareExtension" OR process == "Photos"' --level debug
```

**Terminal 3 - Test the extension in Photos.app**

## Expected Behavior

### ✅ Success Indicators:

1. Extension appears in Photos.app share menu
2. Extension window opens without crashing
3. Shows correct file count (e.g., "3 photos")
4. Upload button is enabled
5. Progress bar moves
6. Files appear in `server/uploads/`
7. Server logs show successful uploads

### ❌ If You See Errors:

**"Extension Context does not have a Principal Object"**

- Already fixed - make sure you did a clean rebuild

**"UIKit_PKSubsystem refused setup"**

- This is a warning, not an error - ignore it

**"Unable to obtain task name port"**

- This is also a warning - ignore it

**"makeKeyWindow returned NO"**

- Warning about alerts - can be ignored

**Actual errors to worry about:**

- Extension crashes immediately
- "No items to share"
- Upload fails with network errors

## Test Different Scenarios

### Test 1: Single Photo

- Select 1 photo
- Upload
- Verify in `server/uploads/`

### Test 2: Multiple Photos

- Select 3-5 photos
- Upload
- Verify all uploaded

### Test 3: Video

- Select 1 video
- Upload
- Check file size and format

### Test 4: Mixed Media

- Select 2 photos + 1 video
- Upload
- Verify all types work

### Test 5: Large Files

- Select a large video (>100MB)
- Upload
- Watch progress and verify completion

## Success Checklist

- [ ] Extension appears in share menu
- [ ] Extension opens without crash
- [ ] Shows correct item count
- [ ] Progress bar works
- [ ] Files upload to server
- [ ] Server receives files correctly
- [ ] Files saved to `server/uploads/`
- [ ] Extension closes properly after success

## If All Else Fails

1. **Complete reset:**

   ```bash
   # Clean everything
   rm -rf ~/Library/Developer/Xcode/DerivedData/PhotoUploader-*

   # Rebuild from scratch
   cd /Users/oli/dev/photo-upload
   xcodebuild -scheme PhotoUploader -configuration Debug

   # Reset launch services
   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user

   # Run app
   open PhotoUploader.xcodeproj
   # Press ⌘+R
   ```

2. **Check logs for specific error messages**

3. **Verify entitlements** in `ShareExtension/ShareExtension.entitlements`

4. **Test with Xcode debugger attached** to see actual errors

## Notes

- The warnings about UIKit and port rights are normal for share extensions
- The extension runs in a separate process from Photos.app
- Files are accessed via security-scoped bookmarks
- The temporary exception in entitlements allows reading Photos.app files
