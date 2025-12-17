# Debug Test - See What's Happening

The extension now has detailed logging to help debug issues.

## How to Test with Debug Logs

### Step 1: Rebuild with Debug Logging

```bash
xcodebuild clean -scheme PhotoUploader
xcodebuild -scheme PhotoUploader -configuration Debug
```

### Step 2: Run the App

```bash
open ~/Library/Developer/Xcode/DerivedData/PhotoUploader-*/Build/Products/Debug/PhotoUploader.app
```

### Step 3: Start Watching Logs

Open a new terminal and run:

```bash
log stream --predicate 'process == "ShareExtension" OR subsystem CONTAINS "ShareExtension"' --level debug --color always
```

Keep this terminal visible!

### Step 4: Start the Server (Another Terminal)

```bash
cd server
npm start
```

### Step 5: Test in Photos.app

1. Open Photos.app
2. Select 1-2 photos
3. Click Share → "Upload Photos"
4. **Watch the log terminal!**

## What You Should See in Logs

### ✅ Good Output:

```
🟢 ShareViewController viewDidLoad - Extension started
📦 Found 1 extension items
📎 Total attachments: 2
🔍 Processing attachment 1/2
   Registered types: ["public.file-url", "public.jpeg", "public.image"]
   ✅ Has file URL type - loading...
✅ Loaded URL: /private/var/folders/.../IMG_1234.jpg
🔍 Processing attachment 2/2
   Registered types: ["public.file-url", "public.jpeg", "public.image"]
   ✅ Has file URL type - loading...
✅ Loaded URL: /private/var/folders/.../IMG_5678.jpg
🔄 Updating UI - 2 items loaded
```

### ❌ If You See Problems:

**No logs at all:**

```
(Extension not loading - check if it appears in share menu)
```

**No extension context:**

```
❌ No extension context or input items
```

**No attachments:**

```
📦 Found 1 extension items
📎 Total attachments: 0
❌ No attachments found
```

**Loading errors:**

```
🔍 Processing attachment 1/1
❌ Error loading URL: ...
```

## Debug Different Scenarios

### Test 1: Single Photo

- Select 1 photo
- Watch logs
- Should see: `📎 Total attachments: 1`

### Test 2: Multiple Photos

- Select 3 photos
- Watch logs
- Should see: `📎 Total attachments: 3`

### Test 3: See What File Types Photos Provides

Look for: `Registered types: [...]`

This will show us what types Photos.app is actually providing!

## Common Log Messages Explained

### Normal (Ignore These):

```
UIKit_PKSubsystem refused setup
Unable to obtain task name port
makeKeyWindow returned NO
```

### Important (Pay Attention):

```
🟢 ShareViewController viewDidLoad - Extension started
📦 Found N extension items
📎 Total attachments: N
✅ Loaded URL: /path/to/file
🔄 Updating UI - N items loaded
```

### Errors (Need to Fix):

```
❌ No extension context or input items
❌ No attachments found
❌ Error loading URL: ...
```

## Upload Test

If items load successfully:

1. Click "Upload" button
2. Watch for upload logs:

   ```
   📤 Uploading: IMG_1234.jpg (2.5 MB)
   ✅ Upload successful: IMG_1234.jpg
   ```

3. Check server terminal for:

   ```
   ✅ File uploaded: IMG_1234.jpg (2.5 MB)
   ```

4. Verify files:
   ```bash
   ls -lh server/uploads/
   ```

## Save Debug Output

If you want to save logs for review:

```bash
log stream --predicate 'process == "ShareExtension"' --level debug > extension-debug.log 2>&1
```

Then test the extension, and check `extension-debug.log` file.

## Quick Test Script

Save this as `test-extension.sh`:

```bash
#!/bin/bash

echo "Starting debug test..."

# Terminal 1: Logs
osascript -e 'tell app "Terminal" to do script "cd /Users/oli/dev/photo-upload && log stream --predicate \"process == \\\"ShareExtension\\\"\" --level debug --color always"'

# Terminal 2: Server
osascript -e 'tell app "Terminal" to do script "cd /Users/oli/dev/photo-upload/server && npm start"'

# Wait a bit
sleep 2

# Open Photos
open -a Photos

echo "✅ Setup complete!"
echo "1. Logs are streaming in a new terminal"
echo "2. Server is running in another terminal"
echo "3. Photos.app is open"
echo "4. Now select photos and test the extension!"
```

Make it executable and run:

```bash
chmod +x test-extension.sh
./test-extension.sh
```

## What to Share if Asking for Help

If it still doesn't work, share:

1. The log output (especially the emoji lines)
2. What you see in the extension window
3. Any error messages
4. The "Registered types" line (shows what Photos provides)

The debug output will tell us exactly what's happening!
