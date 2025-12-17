#!/bin/bash

# Photo Uploader Release Build Script
# Creates a distributable .app bundle

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="PhotoUploader"
PROJECT_FILE="${PROJECT_NAME}.xcodeproj"
APP_NAME="${PROJECT_NAME}.app"
BUILD_DIR="./build"
RELEASE_DIR="./release"
ARCHIVE_NAME="${PROJECT_NAME}.zip"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Photo Uploader Release Builder      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}❌ Error: Xcode is not installed${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Xcode found: $(xcodebuild -version | head -n 1)"

# Check if project file exists
if [ ! -d "$PROJECT_FILE" ]; then
    echo -e "${RED}❌ Error: Project file not found: $PROJECT_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Project file found"

# Clean previous builds
echo ""
echo -e "${YELLOW}🧹 Cleaning previous builds...${NC}"
rm -rf "$BUILD_DIR"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Build the app
echo ""
echo -e "${YELLOW}🔨 Building Release version...${NC}"
echo "This may take a minute..."

xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$PROJECT_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    clean build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | grep -E "error:|warning:|Build succeeded|Build FAILED" || true

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Build successful"

# Find the built app
BUILT_APP=$(find "$BUILD_DIR" -name "$APP_NAME" -type d | head -n 1)

if [ -z "$BUILT_APP" ]; then
    echo -e "${RED}❌ Error: Built app not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} App located: $BUILT_APP"

# Copy to release directory
echo ""
echo -e "${YELLOW}📦 Creating release package...${NC}"

cp -R "$BUILT_APP" "$RELEASE_DIR/"

# Get app size
APP_SIZE=$(du -sh "$RELEASE_DIR/$APP_NAME" | cut -f1)
echo -e "${GREEN}✓${NC} App size: $APP_SIZE"

# Create ZIP archive
echo ""
echo -e "${YELLOW}🗜️  Creating archive...${NC}"

cd "$RELEASE_DIR"
zip -r -q "$ARCHIVE_NAME" "$APP_NAME"
cd - > /dev/null

ARCHIVE_SIZE=$(du -sh "$RELEASE_DIR/$ARCHIVE_NAME" | cut -f1)
echo -e "${GREEN}✓${NC} Archive created: $ARCHIVE_SIZE"

# Calculate checksum
echo ""
echo -e "${YELLOW}🔐 Calculating checksum...${NC}"
CHECKSUM=$(shasum -a 256 "$RELEASE_DIR/$ARCHIVE_NAME" | cut -d' ' -f1)
echo -e "${GREEN}✓${NC} SHA-256: $CHECKSUM"

# Create release notes
cat > "$RELEASE_DIR/RELEASE_NOTES.txt" << EOF
Photo Uploader v1.0
Release Date: $(date +"%Y-%m-%d")

Package Contents:
- PhotoUploader.app (macOS 14.0+)

Installation:
1. Extract the ZIP file
2. Move PhotoUploader.app to /Applications
3. Double-click to launch
4. Follow the setup wizard

SHA-256 Checksum:
$CHECKSUM

Requirements:
- macOS 14.0 or later
- Photo upload server (Spring Boot or compatible)

For more information, see README.md
EOF

echo -e "${GREEN}✓${NC} Release notes created"

# Final summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Build Complete! ✓                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📦 Release Package:${NC}"
echo "   Location: $RELEASE_DIR/"
echo "   App:      $APP_NAME ($APP_SIZE)"
echo "   Archive:  $ARCHIVE_NAME ($ARCHIVE_SIZE)"
echo ""
echo -e "${BLUE}📝 Files created:${NC}"
echo "   - $RELEASE_DIR/$APP_NAME"
echo "   - $RELEASE_DIR/$ARCHIVE_NAME"
echo "   - $RELEASE_DIR/RELEASE_NOTES.txt"
echo ""
echo -e "${BLUE}🚀 Next Steps:${NC}"
echo "   1. Test the app: open $RELEASE_DIR/$APP_NAME"
echo "   2. Distribute: Share the ZIP file"
echo "   3. (Optional) Code sign and notarize for distribution"
echo ""
echo -e "${YELLOW}⚠️  Note:${NC} This app is not code-signed. Users may see a security"
echo "   warning on first launch. For production distribution, consider:"
echo "   - Signing with a Developer ID certificate"
echo "   - Notarizing with Apple"
echo ""
