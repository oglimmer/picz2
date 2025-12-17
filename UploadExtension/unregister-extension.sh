#!/bin/bash

# Script to un-register the PhotoUploader Share Extension from macOS

echo "🔧 Un-registering PhotoUploader Share Extension..."

# Kill the extension if it's running
echo "1. Killing running extension processes..."
killall -9 ShareExtension 2>/dev/null || true
killall -9 PhotoUploader 2>/dev/null || true

# Reset the pluginkit database for this extension
echo "2. Removing extension from pluginkit database..."

# Check /Applications first (most common location)
APPLICATIONS_PATH="/Applications/PhotoUploader.app/Contents/PlugIns/ShareExtension.appex"
if [ -d "$APPLICATIONS_PATH" ]; then
    pluginkit -r "$APPLICATIONS_PATH"
    echo "   ✅ Extension removed from /Applications"
else
    echo "   ℹ️  Extension not found in /Applications"
fi

# Check debug build path
APP_PATH="${PWD}/build/Build/Products/Debug/PhotoUploader.app"
EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/ShareExtension.appex"

if [ -d "$EXTENSION_PATH" ]; then
    pluginkit -r "$EXTENSION_PATH"
    echo "   ✅ Debug extension removed from pluginkit"
else
    echo "   ℹ️  Extension not found at: $EXTENSION_PATH"
fi

# Also try the release path
RELEASE_APP_PATH="${PWD}/release/PhotoUploader.app"
RELEASE_EXTENSION_PATH="${RELEASE_APP_PATH}/Contents/PlugIns/ShareExtension.appex"

if [ -d "$RELEASE_EXTENSION_PATH" ]; then
    pluginkit -r "$RELEASE_EXTENSION_PATH"
    echo "   ✅ Release extension removed from pluginkit"
fi

# Reset the entire pluginkit cache (more aggressive)
echo "3. Resetting pluginkit cache..."
pluginkit -m -v -A 2>&1 | grep -i photouploader && echo "   ⚠️  Extension still registered" || echo "   ✅ Extension not found in registry"

# Kill cfprefsd to clear caches
echo "4. Clearing system caches..."
killall -9 cfprefsd 2>/dev/null || true

# Kill ShareKit daemon
killall -9 sharingd 2>/dev/null || true

echo ""
echo "✅ Un-registration complete!"
echo ""
echo "You may need to:"
echo "  - Log out and log back in"
echo "  - Or restart your Mac for complete removal"
echo ""
echo "To verify removal, run: pluginkit -m -v | grep -i photouploader"
