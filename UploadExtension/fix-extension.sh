#!/bin/bash

# Fix Share Extension Registration
# Run this if the extension doesn't appear in Photos.app Share menu

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

APP_PATH="/Applications/PhotoUploader.app"
EXTENSION_PATH="$APP_PATH/Contents/PlugIns/ShareExtension.appex"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Share Extension Fix Script          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if app is installed
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ Error: PhotoUploader.app not found in /Applications${NC}"
    echo "Please install the app first using ./install.sh"
    exit 1
fi

echo -e "${GREEN}✓${NC} App found: $APP_PATH"

# Check if extension exists
if [ ! -d "$EXTENSION_PATH" ]; then
    echo -e "${RED}❌ Error: ShareExtension not found in app bundle${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Extension found: $EXTENSION_PATH"

# Quit Photos.app if running
echo ""
echo -e "${YELLOW}📱 Checking for running Photos.app...${NC}"
if pgrep -x "Photos" > /dev/null; then
    echo "Quitting Photos.app..."
    osascript -e 'quit app "Photos"' 2>/dev/null || killall Photos 2>/dev/null || true
    sleep 2
fi
echo -e "${GREEN}✓${NC} Photos.app not running"

# Quit PhotoUploader if running
echo ""
echo -e "${YELLOW}📱 Checking for running PhotoUploader...${NC}"
if pgrep -x "PhotoUploader" > /dev/null; then
    echo "Quitting PhotoUploader..."
    osascript -e 'quit app "PhotoUploader"' 2>/dev/null || killall PhotoUploader 2>/dev/null || true
    sleep 2
fi
echo -e "${GREEN}✓${NC} PhotoUploader not running"

# Remove quarantine attributes
echo ""
echo -e "${YELLOW}🔓 Removing quarantine attributes...${NC}"
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
xattr -cr "$APP_PATH" 2>/dev/null || true
echo -e "${GREEN}✓${NC} Quarantine attributes removed"

# Reset Launch Services
echo ""
echo -e "${YELLOW}🔄 Resetting Launch Services database...${NC}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user 2>/dev/null || true
sleep 1
echo -e "${GREEN}✓${NC} Launch Services reset"

# Launch the app to trigger extension registration
echo ""
echo -e "${YELLOW}🚀 Launching PhotoUploader...${NC}"
open -a PhotoUploader
sleep 3
echo -e "${GREEN}✓${NC} App launched"

# Register extension with pluginkit
echo ""
echo -e "${YELLOW}🔌 Registering extension with pluginkit...${NC}"

# Add the extension
pluginkit -a "$EXTENSION_PATH" 2>/dev/null || true

# Enable the extension
pluginkit -e use -i com.example.PhotoUploader.ShareExtension 2>/dev/null || true

sleep 2

# Verify registration
echo ""
echo -e "${YELLOW}🔍 Verifying registration...${NC}"
if pluginkit -m -v 2>/dev/null | grep -q "PhotoUploader"; then
    echo -e "${GREEN}✓${NC} Extension is registered!"
    echo ""
    pluginkit -m -v 2>/dev/null | grep PhotoUploader
else
    echo -e "${YELLOW}⚠${NC} Extension not yet visible in pluginkit"
    echo "This is sometimes normal - it may appear after the next step"
fi

# Final instructions
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Fix Complete! ✓                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📝 Next Steps:${NC}"
echo ""
echo "1. Open Photos.app (or restart if already open):"
echo "   open -a Photos"
echo ""
echo "2. Select one or more photos"
echo ""
echo "3. Click the Share button (or press ⌘+I)"
echo ""
echo "4. Look for 'Upload Photos' in the share menu"
echo ""
echo -e "${BLUE}🔧 If still not working:${NC}"
echo ""
echo "1. Check System Settings → Extensions → Sharing"
echo "   Make sure 'Upload Photos' is enabled"
echo ""
echo "2. Restart your Mac (this sometimes helps)"
echo ""
echo "3. Check extension status:"
echo "   pluginkit -m -v | grep -i upload"
echo ""
echo "4. If you see the extension but it's disabled:"
echo "   pluginkit -e use -i com.example.PhotoUploader.ShareExtension"
echo ""
