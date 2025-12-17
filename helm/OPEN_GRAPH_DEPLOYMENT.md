# Open Graph Deployment Guide

## Changes Made to Helm Chart

### 1. Ingress Routing (`values.yaml`)

Added `/public/album` path to route Open Graph requests to the backend API:

```yaml
- path: /public/album
  pathType: Prefix
  backend: api
```

**Important**: This path must come BEFORE the catch-all `/` path to frontend.

### 2. Backend Environment Variable (`deployment-backend.yaml`)

Added `APP_BASE_URL` environment variable for generating absolute URLs in OG tags:

```yaml
- name: APP_BASE_URL
  value: "https://picz2.oglimmer.com"
```

### 3. Configuration (`values.yaml`)

Added baseUrl configuration option:

```yaml
backend:
  baseUrl: "https://picz2.oglimmer.com"
```

## Deployment Steps

### 1. Build and Push Images

Make sure to build and push the updated backend image with the new controller:

```bash
# Build backend
cd server
./mvnw clean package -DskipTests

# Build and push Docker image
docker build -t registry.oglimmer.com/picz2-be:latest -f Dockerfile .
docker push registry.oglimmer.com/picz2-be:latest
```

### 2. Update Helm Release

```bash
cd helm/photo-upload

# Dry run to verify changes
helm upgrade photo-upload . --dry-run --debug

# Apply the upgrade
helm upgrade photo-upload . --namespace default

# Or with specific values
helm upgrade photo-upload . \
  --namespace default \
  --set backend.baseUrl="https://picz2.oglimmer.com"
```

### 3. Verify Deployment

Check that pods are running:

```bash
kubectl get pods -n default
kubectl logs -f deployment/photo-upload-api -n default
```

### 4. Test the Open Graph Endpoints

Test that the backend is serving OG-enabled HTML:

```bash
# Should return HTML with OG meta tags
curl https://picz2.oglimmer.com/public/album/YOUR_SHARE_TOKEN | grep "og:"

# Check headers
curl -I https://picz2.oglimmer.com/public/album/YOUR_SHARE_TOKEN

# Test with Facebook bot user agent
curl -H "User-Agent: facebookexternalhit/1.1" \
  https://picz2.oglimmer.com/public/album/YOUR_SHARE_TOKEN \
  | grep "og:"
```

Expected output should include:

```html
<link rel="canonical" href="https://picz2.oglimmer.com/public/album/..." />
<meta property="og:type" content="website" />
<meta property="og:url" content="https://picz2.oglimmer.com/public/album/..." />
<meta property="og:title" content="Album Name" />
<meta property="og:image" content="https://picz2.oglimmer.com/api/i/..." />
```

### 5. Test Routing

Verify routing is working correctly:

```bash
# Backend endpoints (should return JSON)
curl https://picz2.oglimmer.com/api/version

# OG endpoint (should return HTML with meta tags, NOT Vue index.html)
curl https://picz2.oglimmer.com/public/album/YOUR_SHARE_TOKEN | head -30

# Frontend endpoint (should return Vue app)
curl https://picz2.oglimmer.com/app/public/album/YOUR_SHARE_TOKEN | head -20
```

### 6. Clear Social Media Caches

After deployment, social media platforms cache OG data. Use these tools to refresh:

- **Facebook**: https://developers.facebook.com/tools/debug/
- **Twitter**: https://cards-dev.twitter.com/validator
- **LinkedIn**: https://www.linkedin.com/post-inspector/

## Ingress Path Order

The order in `values.yaml` matters. Current order (correct):

1. `/api` → backend
2. `/swagger-ui` → backend
3. `/swagger-ui.html` → backend
4. `/v3/api-docs` → backend
5. **`/public/album` → backend** (NEW - for OG tags)
6. `/` → frontend (catch-all, must be last)

## Troubleshooting

### Issue: Still serving Vue index.html instead of OG template

**Symptoms**:

```bash
curl https://picz2.oglimmer.com/public/album/TOKEN
# Returns Vue app with <script src="/assets/index-xxx.js">
```

**Solutions**:

1. Verify ingress was updated: `kubectl get ingress photo-upload -o yaml`
2. Check pod logs: `kubectl logs -f deployment/photo-upload-api`
3. Verify backend has new code: `curl https://picz2.oglimmer.com/api/version`
4. Check ingress controller: `kubectl describe ingress photo-upload`

### Issue: Backend returns 404

**Symptoms**:

```bash
curl -I https://picz2.oglimmer.com/public/album/TOKEN
# HTTP/1.1 404 Not Found
```

**Solutions**:

1. Check if controller is loaded: Look for `PublicShareController` in logs
2. Verify security config allows public access: Check `SecurityConfig.java`
3. Check Thymeleaf templates exist in jar: `jar tf target/*.jar | grep templates`

### Issue: Images not loading in previews

**Symptoms**: OG tags present but social media shows no image

**Solutions**:

1. Verify image URLs are absolute: Check `og:image` content
2. Test image URL directly: `curl -I https://picz2.oglimmer.com/api/i/TOKEN`
3. Check CORS headers on `/api/i/**` endpoints
4. Verify image size: Social platforms have limits (Facebook max 8MB)

## Configuration Options

You can override the base URL during deployment:

```bash
# Using --set
helm upgrade photo-upload . --set backend.baseUrl="https://photos.example.com"

# Using values file
cat > custom-values.yaml <<EOF
backend:
  baseUrl: "https://photos.example.com"
EOF

helm upgrade photo-upload . -f custom-values.yaml
```

## Rollback

If something goes wrong:

```bash
# List releases
helm history photo-upload

# Rollback to previous version
helm rollback photo-upload <revision-number>
```
