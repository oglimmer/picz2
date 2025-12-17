#!/usr/bin/env bash

set -eu

cd "$(dirname "$0")/.."

# Display usage help
show_usage() {
    echo "Usage: $(basename "$0") <major|minor|patch> [--restart]"
    echo ""
    echo "Bumps the semantic version according to the specified level:"
    echo "  major    Increment major version (x.0.0)"
    echo "  minor    Increment minor version (0.x.0)"
    echo "  patch    Increment patch version (0.0.x)"
    echo ""
    echo "Options:"
    echo "  --restart    Pass --restart flag to build_local.sh"
    echo ""
    echo "This script will:"
    echo "  1. Read current version from pom.xml and remove -SNAPSHOT"
    echo "  2. Increment the appropriate version component"
    echo "  3. Update VERSION, frontend/package.json, and server/pom.xml with release version"
    echo "  4. Create git commit and tag for release"
    echo "  5. Run build_local.sh script"
    echo "  6. Add -SNAPSHOT suffix back to frontend/package.json and server/pom.xml"
    echo "  7. Create git commit for next development version"
    echo ""
    exit 1
}

# Check arguments
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Error: Invalid number of arguments"
    show_usage
fi

BUMP_TYPE=$1
RESTART_FLAG=""

# Check for --restart flag
if [ $# -eq 2 ]; then
    if [ "$2" == "--restart" ]; then
        RESTART_FLAG="--restart"
    else
        echo "Error: Invalid option '$2'"
        show_usage
    fi
fi

# Validate bump type
case "$BUMP_TYPE" in
    major|minor|patch)
        ;;
    *)
        echo "Error: Invalid bump type '$BUMP_TYPE'"
        show_usage
        ;;
esac

# Read current version from pom.xml and remove -SNAPSHOT
if [ ! -f server/pom.xml ]; then
    echo "Error: server/pom.xml not found"
    exit 1
fi

# Extract version from pom.xml (expecting format like 1.0.0-SNAPSHOT)
CURRENT_VERSION_WITH_SNAPSHOT=$(grep -A 1 "<artifactId>photo-upload-server</artifactId>" server/pom.xml | grep "<version>" | sed 's/.*<version>\(.*\)<\/version>.*/\1/')

# Remove -SNAPSHOT suffix
CURRENT_VERSION="${CURRENT_VERSION_WITH_SNAPSHOT%-SNAPSHOT}"

echo "Current version (after removing -SNAPSHOT): $CURRENT_VERSION"

# Validate version format
if ! [[ "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Error: Invalid version format: $CURRENT_VERSION"
    echo "Expected format: X.Y.Z"
    exit 1
fi

# Extract version components
MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

# Bump the appropriate version component
case "$BUMP_TYPE" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"

echo "Bumping version from $CURRENT_VERSION to $NEW_VERSION"

# Update VERSION file with release version
echo "$NEW_VERSION" > VERSION
echo "✅ Updated VERSION file to $NEW_VERSION"

# Update frontend package.json with release version
if [ -f frontend/package.json ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/\"version\": \".*\"/\"version\": \"$NEW_VERSION\"/" frontend/package.json
    else
        # Linux
        sed -i "s/\"version\": \".*\"/\"version\": \"$NEW_VERSION\"/" frontend/package.json
    fi
    echo "✅ Updated frontend/package.json to version $NEW_VERSION"
else
    echo "⚠️  Warning: frontend/package.json not found"
fi

# Update server pom.xml with release version (no -SNAPSHOT)
if [ -f server/pom.xml ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "/<artifactId>photo-upload-server<\/artifactId>/{n;s|<version>.*</version>|<version>$NEW_VERSION</version>|;}" server/pom.xml
    else
        # Linux
        sed -i "/<artifactId>photo-upload-server<\/artifactId>/{n;s|<version>.*</version>|<version>$NEW_VERSION</version>|;}" server/pom.xml
    fi
    echo "✅ Updated server/pom.xml to version $NEW_VERSION"
else
    echo "⚠️  Warning: server/pom.xml not found"
fi

# Create git commit and tag for release
echo ""
echo "Creating git commit and tag for release version $NEW_VERSION..."
git add VERSION frontend/package.json server/pom.xml
git commit -m "Release version $NEW_VERSION"
git tag "v$NEW_VERSION"
echo "✅ Created git commit and tag v$NEW_VERSION"

# Run build_local.sh with --release flag
echo ""
echo "Running build_local.sh with --release flag $RESTART_FLAG..."
if [ -f bin/build_local.sh ]; then
    if [ -n "$RESTART_FLAG" ]; then
        bin/build_local.sh all --release --restart
    else
        bin/build_local.sh all --release
    fi
    echo "✅ Build completed successfully"
else
    echo "⚠️  Warning: bin/build_local.sh not found, skipping build"
fi

# Add -SNAPSHOT suffix back to frontend/package.json and server/pom.xml
echo ""
echo "Adding -SNAPSHOT suffix back for next development version..."

# Update frontend package.json with -SNAPSHOT version
if [ -f frontend/package.json ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - Note: package.json doesn't typically use -SNAPSHOT, but doing it for consistency
        sed -i '' "s/\"version\": \".*\"/\"version\": \"$NEW_VERSION-SNAPSHOT\"/" frontend/package.json
    else
        # Linux
        sed -i "s/\"version\": \".*\"/\"version\": \"$NEW_VERSION-SNAPSHOT\"/" frontend/package.json
    fi
    echo "✅ Updated frontend/package.json to version $NEW_VERSION-SNAPSHOT"
fi

# Update server pom.xml with -SNAPSHOT version
if [ -f server/pom.xml ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "/<artifactId>photo-upload-server<\/artifactId>/{n;s|<version>.*</version>|<version>$NEW_VERSION-SNAPSHOT</version>|;}" server/pom.xml
    else
        # Linux
        sed -i "/<artifactId>photo-upload-server<\/artifactId>/{n;s|<version>.*</version>|<version>$NEW_VERSION-SNAPSHOT</version>|;}" server/pom.xml
    fi
    echo "✅ Updated server/pom.xml to version $NEW_VERSION-SNAPSHOT"
fi

# Create git commit for next development version
echo ""
echo "Creating git commit for next development version..."
git add frontend/package.json server/pom.xml
git commit -m "Prepare for next development iteration"
echo "✅ Created git commit for development version $NEW_VERSION-SNAPSHOT"

echo ""
echo "🎉 Version bump completed successfully!"
echo ""
echo "Summary:"
echo "  - Release version: $NEW_VERSION (tagged as v$NEW_VERSION)"
echo "  - Development version: $NEW_VERSION-SNAPSHOT"
echo ""
echo "Next steps:"
echo "  1. Review the changes and commits"
echo "  2. Push the commits: git push"
echo "  3. Push the tag: git push origin v$NEW_VERSION"
