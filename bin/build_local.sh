#!/usr/bin/env bash

set -eu

cd "$(dirname "$0")/.."

# Display usage help
show_usage() {
    echo "Usage: $(basename "$0") [option] [--restart] [--release]"
    echo ""
    echo "Options:"
    echo "  all    Build and push both frontend and backend images"
    echo "  fe     Build and push only the frontend image"
    echo "  be     Build and push only the backend image"
    echo "  help   Display this help message"
    echo ""
    echo "Parameters:"
    echo "  --restart   Restart the corresponding Kubernetes deployments after build"
    echo "  --release   Build as release version (no -SNAPSHOT suffix in pom.xml)"
    echo ""
    echo "Version Management:"
    echo "  Versions are automatically read from VERSION file and applied to:"
    echo "  - Frontend Docker image tags (e.g., registry.oglimmer.com/picz2-fe:1.0.0)"
    echo "  - Backend Docker image tags (e.g., registry.oglimmer.com/picz2-be:1.0.0)"
    echo "  - Frontend package.json version field"
    echo "  - Backend pom.xml keeps -SNAPSHOT suffix on main branch (unless --release)"
    echo ""
    echo "  Use bin/bump_version.sh to increment versions"
    echo ""
    exit 1
}

# Function to read and validate version
get_version() {
    if [ ! -f VERSION ]; then
        echo "Error: VERSION file not found"
        exit 1
    fi

    VERSION=$(cat VERSION)

    # Validate version format (semantic versioning: X.Y.Z)
    if ! [[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        echo "Error: Invalid version format in VERSION file: $VERSION"
        echo "Expected format: X.Y.Z (e.g., 1.0.0)"
        exit 1
    fi

    echo "$VERSION"
}

# Function to update frontend package.json version
update_frontend_version() {
    local version=$1

    if [ ! -f frontend/package.json ]; then
        echo "⚠️  Warning: frontend/package.json not found, skipping version update"
        return
    fi

    echo "Updating frontend/package.json to version $version..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/\"version\": \".*\"/\"version\": \"$version\"/" frontend/package.json
    else
        # Linux
        sed -i "s/\"version\": \".*\"/\"version\": \"$version\"/" frontend/package.json
    fi
    echo "✅ Frontend package.json updated to version $version"
}

# Function to update backend pom.xml version
update_backend_version() {
    local version=$1
    local is_release=${2:-false}

    if [ ! -f server/pom.xml ]; then
        echo "⚠️  Warning: server/pom.xml not found, skipping version update"
        return
    fi

    # Determine whether to use -SNAPSHOT
    if [ "$is_release" == "true" ]; then
        # Release build - no -SNAPSHOT
        POM_VERSION="$version"
        echo "Updating server/pom.xml to version $POM_VERSION (release build)..."
    else
        # Check current git branch
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

        # On main branch, keep -SNAPSHOT suffix; on build tags, remove it
        if [ "$CURRENT_BRANCH" == "main" ] || [ "$CURRENT_BRANCH" == "master" ]; then
            POM_VERSION="${version}-SNAPSHOT"
            echo "Updating server/pom.xml to version $POM_VERSION (main branch)..."
        else
            POM_VERSION="$version"
            echo "Updating server/pom.xml to version $POM_VERSION (release branch)..."
        fi
    fi

    # Update only the artifact version, not the parent version
    # This targets the version tag that comes after the artifactId tag
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "/<artifactId>photo-upload-server<\/artifactId>/{n;s|<version>.*</version>|<version>$POM_VERSION</version>|;}" server/pom.xml
    else
        # Linux
        sed -i "/<artifactId>photo-upload-server<\/artifactId>/{n;s|<version>.*</version>|<version>$POM_VERSION</version>|;}" server/pom.xml
    fi
    echo "✅ Backend pom.xml updated to version $POM_VERSION"
}

# Parse arguments
if [ $# -lt 1 ] || [ $# -gt 3 ]; then
    echo "Error: Invalid number of arguments"
    show_usage
fi

BUILD_OPTION=$1
RESTART_FLAG=false
RELEASE_FLAG=false

# Parse additional flags
shift
while [ $# -gt 0 ]; do
    case "$1" in
        --restart)
            RESTART_FLAG=true
            shift
            ;;
        --release)
            RELEASE_FLAG=true
            shift
            ;;
        *)
            echo "Error: Unknown parameter '$1'"
            show_usage
            ;;
    esac
done

# Get version from VERSION file
VERSION=$(get_version)
echo "📦 Using version: $VERSION"
echo ""

# Process the build command
case "$BUILD_OPTION" in
    all)
        echo "Building both frontend and backend..."

        # Update versions in config files
        update_frontend_version "$VERSION"
        update_backend_version "$VERSION" "$RELEASE_FLAG"

        echo ""
        echo "Building Docker images with version tags..."

        # Build and tag frontend with version
        docker build \
            --tag registry.oglimmer.com/picz2-fe:${VERSION} \
            --tag registry.oglimmer.com/picz2-fe:latest \
            --push . -f frontend/Dockerfile-prod

        # Build and tag backend with version (without -SNAPSHOT for Docker tags)
        docker build \
            --tag registry.oglimmer.com/picz2-be:${VERSION} \
            --tag registry.oglimmer.com/picz2-be:latest \
            --push . -f server/Dockerfile

        echo "✅ All builds completed successfully!"
        echo "   Frontend: registry.oglimmer.com/picz2-fe:${VERSION}"
        echo "   Backend:  registry.oglimmer.com/picz2-be:${VERSION}"

        if [ "$RESTART_FLAG" == "true" ]; then
            echo ""
            echo "Restarting Kubernetes deployments..."
            kubectl rollout restart deployment photo-upload-backend
            kubectl rollout restart deployment photo-upload-frontend
            echo "✅ Deployments restarted successfully!"
        fi
        ;;
    fe)
        echo "Building frontend only..."

        # Update frontend version
        update_frontend_version "$VERSION"

        echo ""
        echo "Building Docker image with version tags..."

        # Build and tag frontend with version
        docker build \
            --tag registry.oglimmer.com/picz2-fe:${VERSION} \
            --tag registry.oglimmer.com/picz2-fe:latest \
            --push . -f frontend/Dockerfile-prod

        echo "✅ Frontend build completed successfully!"
        echo "   Image: registry.oglimmer.com/picz2-fe:${VERSION}"

        if [ "$RESTART_FLAG" == "true" ]; then
            echo ""
            echo "Restarting frontend Kubernetes deployment..."
            kubectl rollout restart deployment photo-upload-frontend
            echo "✅ Frontend deployment restarted successfully!"
        fi
        ;;
    be)
        echo "Building backend only..."

        # Update backend version
        update_backend_version "$VERSION" "$RELEASE_FLAG"

        echo ""
        echo "Building Docker image with version tags..."

        # Build and tag backend with version (without -SNAPSHOT for Docker tags)
        docker build \
            --tag registry.oglimmer.com/picz2-be:${VERSION} \
            --tag registry.oglimmer.com/picz2-be:latest \
            --push . -f server/Dockerfile

        echo "✅ Backend build completed successfully!"
        echo "   Image: registry.oglimmer.com/picz2-be:${VERSION}"

        if [ "$RESTART_FLAG" == "true" ]; then
            echo ""
            echo "Restarting backend Kubernetes deployment..."
            kubectl rollout restart deployment photo-upload-backend
            echo "✅ Backend deployment restarted successfully!"
        fi
        ;;
    help)
        show_usage
        ;;
    *)
        echo "Error: Invalid option '$BUILD_OPTION'"
        show_usage
        ;;
esac
