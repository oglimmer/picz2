# Integration Guide - Extension + Server

This guide shows how to use the macOS Share Extension with the Node.js upload server.

## Quick Start

### 1. Start the Server

```bash
# Install dependencies (first time only)
cd server
npm install

# Start the server
npm start
```

The server will start at `http://localhost:3000`

You should see:

```
=====================================
📸 Photo Upload Server Running
=====================================
Server: http://localhost:3000
Upload endpoint: http://localhost:3000/upload
Files directory: /path/to/server/uploads
=====================================
```

### 2. Build and Run the Extension

```bash
# Open in Xcode
open PhotoUploader.xcodeproj

# Build and run (⌘+R)
```

Or from command line:

```bash
xcodebuild -scheme PhotoUploader -configuration Debug
```

### 3. Test the Integration

1. **Run the main app once** to register the extension
2. **Open Photos.app**
3. **Select one or more photos/videos**
4. **Click the Share button** in the toolbar
5. **Choose "Upload Photos"**
6. **Click Upload**

You'll see:

- Progress bar in the extension UI
- Upload logs in the terminal where the server is running
- Files saved to `server/uploads/`

## What Happens

### In the Share Extension:

1. User selects photos in Photos.app
2. Extension loads the selected media files
3. On "Upload" click, files are sent to `UploadService`
4. Each file is uploaded via HTTP POST to `http://localhost:3000/upload`
5. Progress updates are shown in real-time
6. Success/error message displayed

### In the Server:

1. Server receives POST request at `/upload`
2. Multer processes the multipart form data
3. File is validated (type and size)
4. File is saved with unique filename to `uploads/`
5. JSON response sent back with file info
6. Console logs the upload

## Configuration

### Change Server Port

**In server:**

```bash
PORT=8080 npm start
```

**In Swift (Shared/UploadService.swift:7):**

```swift
private var apiEndpoint = "http://localhost:8080/upload"
```

### Change Upload Directory

**In server/server.js (line 16):**

```javascript
const uploadsDir = path.join(__dirname, "my-uploads");
```

### Increase File Size Limit

**In server/server.js (line 50):**

```javascript
limits: {
  fileSize: 1000 * 1024 * 1024; // 1GB
}
```

### Configure Timeout

**In Shared/UploadService.swift (line 78):**

```swift
request.timeoutInterval = 300 // 5 minutes
```

## Testing the Integration

### Test Server Manually

```bash
# Test with curl
curl -X POST http://localhost:3000/upload \
  -F "file=@/path/to/test-image.jpg"

# Expected response:
{
  "success": true,
  "file": {
    "originalName": "test-image.jpg",
    "filename": "test-image-1234567890.jpg",
    "size": 102400,
    "mimetype": "image/jpeg",
    "path": "/path/to/uploads/test-image-1234567890.jpg",
    "uploadedAt": "2025-10-06T21:00:00.000Z"
  }
}
```

### Run Server Tests

```bash
cd server
./test.sh
```

### View Server Logs

The server logs every upload:

```
✅ File uploaded: IMG_1234.jpg (2.5 MB)
✅ File uploaded: video.mov (45.3 MB)
```

### View Extension Logs

Check Xcode console for upload progress:

```
📤 Uploading: IMG_1234.jpg (2.5 MB)
✅ Upload successful: IMG_1234.jpg
📤 Uploading: video.mov (45.3 MB)
✅ Upload successful: video.mov
```

## Advanced Usage

### Upload to Remote Server

1. **Deploy server** to a hosting service (e.g., Heroku, DigitalOcean)
2. **Get the URL** (e.g., `https://my-server.com`)
3. **Update Swift code** (Shared/UploadService.swift:7):
   ```swift
   private var apiEndpoint = "https://my-server.com/upload"
   ```
4. **Rebuild the app**

### Add Authentication

**In server/server.js (before upload endpoint):**

```javascript
app.use((req, res, next) => {
  const apiKey = req.headers["x-api-key"];
  if (apiKey !== "your-secret-key") {
    return res.status(401).json({ error: "Unauthorized" });
  }
  next();
});
```

**In Shared/UploadService.swift (in uploadFile method):**

```swift
request.setValue("your-secret-key", forHTTPHeaderField: "X-API-Key")
```

### Custom Upload Metadata

**Add metadata in Swift (Shared/UploadService.swift):**

```swift
// After line 93, add more form fields:
body.append("--\(boundary)\r\n".data(using: .utf8)!)
body.append("Content-Disposition: form-data; name=\"user_id\"\r\n\r\n".data(using: .utf8)!)
body.append("12345\r\n".data(using: .utf8)!)
```

**Access in server (server.js):**

```javascript
app.post("/upload", upload.single("file"), (req, res) => {
  const userId = req.body.user_id;
  console.log("Upload from user:", userId);
  // ...
});
```

## Troubleshooting

### Extension shows "Upload failed"

**Check:**

1. Is the server running? (`curl http://localhost:3000/health`)
2. Is the endpoint correct? (Check `UploadService.swift:7`)
3. Check Xcode console for error details
4. Check server console for errors

### Server returns 400 Bad Request

**Common causes:**

- Invalid file type
- File too large
- Malformed request

**Fix:**

- Check allowed types in `server.js`
- Increase size limit
- Check Swift multipart formatting

### Connection refused / Network error

**Solutions:**

1. Make sure server is running:
   ```bash
   lsof -i :3000
   ```
2. Check firewall settings
3. For remote servers, verify URL is correct
4. Ensure network.client entitlement is enabled

### Files not appearing in uploads/

**Check:**

1. Server has write permissions:
   ```bash
   ls -la server/uploads/
   ```
2. Upload completed successfully (check logs)
3. Looking in the right directory

### Large videos timeout

**Solutions:**

1. Increase timeout in Swift (line 78)
2. Increase timeout in server
3. Implement chunked uploads
4. Use background upload session

## Monitoring

### View Uploaded Files

**Web browser:**

```
http://localhost:3000/files
```

**Command line:**

```bash
ls -lh server/uploads/
```

**Via API:**

```bash
curl http://localhost:3000/files | jq
```

### Server Stats

```bash
# Number of files
ls server/uploads/ | wc -l

# Total size
du -sh server/uploads/

# Recent uploads
ls -lt server/uploads/ | head -10
```

## Production Checklist

Before deploying to production:

- [ ] Add authentication/authorization
- [ ] Use HTTPS (not HTTP)
- [ ] Restrict CORS to your domain
- [ ] Add rate limiting
- [ ] Implement file scanning
- [ ] Set up logging and monitoring
- [ ] Configure backups
- [ ] Add error tracking
- [ ] Use environment variables for config
- [ ] Update bundle identifiers
- [ ] Code sign the app properly

## Architecture

```
┌─────────────────────┐
│   Photos.app        │
│   (User selects)    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Share Extension    │
│  ShareViewController│
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  UploadService      │
│  (Swift)            │
│  localhost:3000     │
└──────────┬──────────┘
           │ HTTP POST
           ▼
┌─────────────────────┐
│  Express Server     │
│  (Node.js)          │
│  Port 3000          │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Multer Middleware  │
│  (File Processing)  │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  File System        │
│  server/uploads/    │
└─────────────────────┘
```

## Next Steps

1. ✅ Server and extension integrated
2. Test with various file types and sizes
3. Deploy server to production
4. Add authentication
5. Implement additional features
6. Distribute the app

## Support

For issues:

- Check server logs
- Check Xcode console
- Review this guide
- Check TROUBLESHOOTING.md
