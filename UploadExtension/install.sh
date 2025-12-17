#!/bin/bash

# Photo Uploader Installation Script
# This script builds and installs the Photo Uploader app

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
INSTALL_DIR="/Applications"
BUILD_DIR="./build"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Photo Uploader Installation Script  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}❌ Error: Xcode is not installed${NC}"
    echo "Please install Xcode from the App Store and try again."
    exit 1
fi

echo -e "${GREEN}✓${NC} Xcode found: $(xcodebuild -version | head -n 1)"

# Check if project file exists
if [ ! -d "$PROJECT_FILE" ]; then
    echo -e "${RED}❌ Error: Project file not found: $PROJECT_FILE${NC}"
    echo "Please run this script from the project root directory."
    exit 1
fi

echo -e "${GREEN}✓${NC} Project file found"

# Clean previous build
echo ""
echo -e "${YELLOW}🧹 Cleaning previous build...${NC}"
if [ -d "$BUILD_DIR" ]; then
    rm -rf "$BUILD_DIR"
fi

# Build the app
echo ""
echo -e "${YELLOW}🔨 Building $PROJECT_NAME...${NC}"
echo "This may take a minute..."

xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$PROJECT_NAME" \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR" \
    clean build \
    CODE_SIGN_STYLE=Automatic \
    > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Build failed${NC}"
    echo "Run the build manually to see detailed errors:"
    echo "  xcodebuild -project $PROJECT_FILE -scheme $PROJECT_NAME -configuration Release"
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

# Check if app is already installed
if [ -d "$INSTALL_DIR/$APP_NAME" ]; then
    echo ""
    echo -e "${YELLOW}⚠ Warning: $APP_NAME is already installed${NC}"
    read -p "Do you want to replace it? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi

    echo "Removing old version..."
    # Try to quit the app if it's running
    osascript -e "quit app \"$PROJECT_NAME\"" 2>/dev/null || true
    sleep 1

    rm -rf "$INSTALL_DIR/$APP_NAME"
fi

# Install the app
echo ""
echo -e "${YELLOW}📦 Installing $APP_NAME to $INSTALL_DIR...${NC}"

cp -R "$BUILT_APP" "$INSTALL_DIR/"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Installation failed${NC}"
    echo "You may need to run with sudo:"
    echo "  sudo ./install.sh"
    exit 1
fi

echo -e "${GREEN}✓${NC} Installation successful"

# Remove quarantine attributes that prevent extension registration
echo ""
echo -e "${YELLOW}🔓 Removing quarantine attributes...${NC}"
xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP_NAME" 2>/dev/null || true
echo -e "${GREEN}✓${NC} Quarantine removed"

# Reset Share Extensions database to register the extension
echo ""
echo -e "${YELLOW}🔄 Registering Share Extension...${NC}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user 2>/dev/null || true

# Launch the app (this is required to register the extension with pluginkit)
echo ""
echo -e "${YELLOW}🚀 Launching $PROJECT_NAME...${NC}"
sleep 1
open -a "$PROJECT_NAME"

# Wait for the app to fully launch and register
echo -e "${YELLOW}⏳ Waiting for extension to register...${NC}"
sleep 3

# Force pluginkit to register the extension
echo -e "${YELLOW}🔌 Registering with pluginkit...${NC}"
pluginkit -a "$INSTALL_DIR/$APP_NAME/Contents/PlugIns/ShareExtension.appex" 2>/dev/null || true
pluginkit -e use -i com.example.PhotoUploader.ShareExtension 2>/dev/null || true

# Verify registration
if pluginkit -m -v 2>/dev/null | grep -q "ShareExtension"; then
    echo -e "${GREEN}✓${NC} Extension registered successfully"
else
    echo -e "${YELLOW}⚠${NC} Extension registration pending (may need to restart Photos.app)"
fi

# Final instructions
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Installation Complete! ✓              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📝 Next Steps:${NC}"
echo ""
echo "1. Configure your server settings in the app"
echo "2. Enter your credentials (email and password)"
echo "3. Open Photos.app and select some photos"
echo "4. Click Share → 'Upload Photos'"
echo ""
echo -e "${BLUE}📚 Troubleshooting:${NC}"
echo ""
echo "If the extension doesn't appear in the Share menu:"
echo "  1. Quit and restart Photos.app completely"
echo "  2. Check System Settings → Extensions → Sharing"
echo "  3. Make sure 'Upload Photos' is enabled"
echo "  4. Try running these commands manually:"
echo ""
echo "     # Register the extension"
echo "     pluginkit -a /Applications/$APP_NAME/Contents/PlugIns/ShareExtension.appex"
echo "     pluginkit -e use -i com.example.PhotoUploader.ShareExtension"
echo ""
echo "     # Reset launch services"
echo "     /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user"
echo ""
echo "  5. Restart your Mac (if still not working)"
echo ""
echo -e "${BLUE}For more information, see README.md${NC}"
echo ""
