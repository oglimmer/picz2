#!/usr/bin/env bash

set -euo pipefail

# Define script metadata
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR"

# Default configuration
DEFAULT_REGISTRIES=("registry.oglimmer.com")
DEFAULT_FRONTEND_IMAGE="picz2-fe"
DEFAULT_BACKEND_IMAGE="picz2-be"
DEFAULT_FRONTEND_DEPLOYMENT="photo-upload-frontend"
DEFAULT_BACKEND_DEPLOYMENT="photo-upload-backend"
DEFAULT_WORKER_DEPLOYMENT="photo-upload-worker"

# Configuration variables (can be overridden by parameters)
REGISTRIES=("${DEFAULT_REGISTRIES[@]}")
FRONTEND_IMAGES=()
BACKEND_IMAGES=()
FRONTEND_DEPLOYMENT="$DEFAULT_FRONTEND_DEPLOYMENT"
BACKEND_DEPLOYMENT="$DEFAULT_BACKEND_DEPLOYMENT"
WORKER_DEPLOYMENT="$DEFAULT_WORKER_DEPLOYMENT"

# Directories
FRONTEND_DIR="$SCRIPT_DIR/frontend"
SERVER_DIR="$SCRIPT_DIR/server"
VERSION_FILE="$SCRIPT_DIR/VERSION"

# Default options (can be overridden by environment variables)
BUILD_FRONTEND="${BUILD_FRONTEND:-false}"
BUILD_BACKEND="${BUILD_BACKEND:-false}"
VERBOSE="${VERBOSE:-false}"
DRY_RUN="${DRY_RUN:-false}"
RESTART="${RESTART:-true}"
PUSH="${PUSH:-true}"
NO_CACHE="${NO_CACHE:-false}"
HELP=false
PLATFORM="${PLATFORM:-auto}"
RELEASE_FLAG=false
RELEASE_MODE=false
SHOW_VERSION=false

# Color output (only if terminal supports it)
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold)"
  GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"
  RED="$(tput setaf 1)"
  BLUE="$(tput setaf 4)"
  RESET="$(tput sgr0)"
else
  BOLD="" GREEN="" YELLOW="" RED="" BLUE="" RESET=""
fi

log_info()    { echo -e "${BLUE}[INFO]${RESET} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${RESET} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${RESET} $1"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $1" >&2; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo -e "${BLUE}[VERBOSE]${RESET} $1" || true; }

execute_cmd() {
    local cmd="$1"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} ${cmd}"
        return 0
    fi
    log_verbose "Executing: $cmd"
    if [[ "$VERBOSE" == true ]]; then
        eval "$cmd"
    else
        eval "$cmd" >/dev/null 2>&1
    fi
}

# Cross-platform in-place sed
sed_inplace() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

show_help() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS] [COMMAND]

Build, deploy, and release the photo-upload application.

COMMANDS:
    build               Build and deploy components (default)
    release             Bump version, tag, build a release, then re-arm -SNAPSHOT
    show                Show current version

BUILD OPTIONS:
    -f, --frontend          Build and deploy frontend only
    -s, --server            Build and deploy server only
    -a, --all               Build and deploy both (default if no component specified)
    -v, --verbose           Enable verbose output
    -n, --no-restart        Skip Kubernetes deployment restart (default: restart)
    --no-push               Skip pushing images to registry
    --no-cache              Pass --no-cache to docker build (force full layer rebuild)
    --dry-run               Show what would be done without executing
    --release               Build as release (no -SNAPSHOT suffix in pom.xml)

    --registries "R1,R2"        Comma-separated list of registries (default: ${DEFAULT_REGISTRIES[0]})
    --frontend-deploy NAME      Frontend deployment name (default: $DEFAULT_FRONTEND_DEPLOYMENT)
    --backend-deploy NAME       Backend deployment name (default: $DEFAULT_BACKEND_DEPLOYMENT)
    --worker-deploy NAME        Worker deployment name (default: $DEFAULT_WORKER_DEPLOYMENT)
    --platform PLATFORM         Target platform: amd64 | arm64 | multi | auto (default: auto)

    -h, --help              Show this help message

VERSION MANAGEMENT:
    Versions are read from the VERSION file and applied to:
      - Frontend image tag (e.g., registry.oglimmer.com/${DEFAULT_FRONTEND_IMAGE}:X.Y.Z)
      - Backend image tag  (e.g., registry.oglimmer.com/${DEFAULT_BACKEND_IMAGE}:X.Y.Z)
      - frontend/package.json "version" field
      - server/pom.xml artifact version (keeps -SNAPSHOT on main unless --release)

    Use "${SCRIPT_NAME} release" to bump the version, tag, and build a release.

EXAMPLES:
    ${SCRIPT_NAME} build                            # Build and deploy both with defaults
    ${SCRIPT_NAME} build -f                         # Build and deploy frontend only
    ${SCRIPT_NAME} build -s --release               # Release backend build (restart by default)
    ${SCRIPT_NAME} build -f -n                      # Frontend build, skip k8s restart
    ${SCRIPT_NAME} release                          # Bump version, tag, and build a release
    ${SCRIPT_NAME} show                             # Show current version

ENVIRONMENT VARIABLES:
    FRONTEND_DEPLOYMENT / BACKEND_DEPLOYMENT / WORKER_DEPLOYMENT    Override deployment names
    PLATFORM                                    amd64 | arm64 | multi | auto
    DEFAULT_REGISTRIES_ENV                      Comma-separated registries
    VERBOSE / DRY_RUN / PUSH / RESTART / NO_CACHE  true/false toggles
EOF
}

parse_args() {
    if [[ $# -gt 0 ]]; then
        case $1 in
            build)   shift ;;
            release) RELEASE_MODE=true; shift ;;
            show)    SHOW_VERSION=true; shift ;;
            help|-h|--help) HELP=true; shift ;;
        esac
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--frontend)  BUILD_FRONTEND=true; shift ;;
            -s|--server)    BUILD_BACKEND=true; shift ;;
            -a|--all)       BUILD_FRONTEND=true; BUILD_BACKEND=true; shift ;;
            -v|--verbose)   VERBOSE=true; shift ;;
            -n|--no-restart) RESTART=false; shift ;;
            --no-push)      PUSH=false; shift ;;
            --no-cache)     NO_CACHE=true; shift ;;
            --dry-run)      DRY_RUN=true; shift ;;
            --release)      RELEASE_FLAG=true; shift ;;
            --registries)
                REGISTRIES=()
                IFS=',' read -ra ADDR <<< "$2"
                for reg in "${ADDR[@]}"; do
                    REGISTRIES+=("$(echo "$reg" | xargs)")
                done
                shift 2
                ;;
            --frontend-deploy) FRONTEND_DEPLOYMENT="$2"; shift 2 ;;
            --backend-deploy)  BACKEND_DEPLOYMENT="$2";  shift 2 ;;
            --worker-deploy)   WORKER_DEPLOYMENT="$2";   shift 2 ;;
            --platform)        PLATFORM="$2";            shift 2 ;;
            -h|--help)         HELP=true; shift ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [[ -n "${DEFAULT_REGISTRIES_ENV:-}" ]]; then
        REGISTRIES=()
        IFS=',' read -ra ADDR <<< "$DEFAULT_REGISTRIES_ENV"
        for reg in "${ADDR[@]}"; do
            REGISTRIES+=("$(echo "$reg" | xargs)")
        done
    fi

    FRONTEND_IMAGES=()
    BACKEND_IMAGES=()
    for reg in "${REGISTRIES[@]}"; do
        FRONTEND_IMAGES+=("$reg/$DEFAULT_FRONTEND_IMAGE")
        BACKEND_IMAGES+=("$reg/$DEFAULT_BACKEND_IMAGE")
    done

    if [[ ! "$PLATFORM" =~ ^(amd64|arm64|multi|auto)$ ]]; then
        log_error "Invalid platform: $PLATFORM. Must be one of: amd64, arm64, multi, auto"
        exit 1
    fi

    if [[ "$PUSH" == false && "$RESTART" == true ]]; then
        log_warning "Cannot restart deployments without pushing images. Setting --no-restart."
        RESTART=false
    fi

    if [[ "$RELEASE_MODE" == false && "$SHOW_VERSION" == false \
          && "$BUILD_FRONTEND" == false && "$BUILD_BACKEND" == false ]]; then
        BUILD_FRONTEND=true
        BUILD_BACKEND=true
    fi
}

check_prerequisites() {
    local tools=("docker")
    [[ "$RESTART" == true ]] && tools+=("kubectl")
    [[ "$RELEASE_MODE" == true ]] && tools+=("git")

    local missing=()
    for t in "${tools[@]}"; do
        command -v "$t" >/dev/null 2>&1 || missing+=("$t")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        exit 1
    fi

    if [[ "$DRY_RUN" != true ]] && ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        exit 1
    fi

    if [[ "$PLATFORM" == "multi" ]]; then
        if ! docker buildx version &>/dev/null; then
            log_error "Docker buildx is required for multi-platform builds"
            exit 1
        fi
        docker buildx inspect &>/dev/null || \
            docker buildx create --use --name multiplatform-builder 2>/dev/null || true
    fi
}

# Read and validate VERSION file
get_version() {
    if [[ ! -f "$VERSION_FILE" ]]; then
        log_error "VERSION file not found at $VERSION_FILE"
        exit 1
    fi
    local v
    v=$(cat "$VERSION_FILE")
    if ! [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid version in VERSION file: $v (expected X.Y.Z)"
        exit 1
    fi
    echo "$v"
}

bump_semver() {
    local current="$1" bump="$2"
    IFS='.' read -r major minor patch <<< "$current"
    case "$bump" in
        major)         major=$((major + 1)); minor=0; patch=0 ;;
        minor)         minor=$((minor + 1)); patch=0 ;;
        patch|bugfix)  patch=$((patch + 1)) ;;
        *) log_error "Unknown bump type: $bump"; exit 1 ;;
    esac
    echo "$major.$minor.$patch"
}

update_frontend_version() {
    local v="$1"
    if [[ ! -f "$FRONTEND_DIR/package.json" ]]; then
        log_warning "frontend/package.json not found, skipping"
        return
    fi
    log_info "Updating frontend/package.json to version $v"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} sed version=$v frontend/package.json"
        return
    fi
    sed_inplace "s/\"version\": \".*\"/\"version\": \"$v\"/" "$FRONTEND_DIR/package.json"
}

# Write the artifact version in server/pom.xml. Release builds and non-main
# branches drop -SNAPSHOT; main branch keeps it unless --release is passed.
update_backend_version() {
    local v="$1" is_release="${2:-false}"
    if [[ ! -f "$SERVER_DIR/pom.xml" ]]; then
        log_warning "server/pom.xml not found, skipping"
        return
    fi

    local pom_version
    if [[ "$is_release" == true ]]; then
        pom_version="$v"
    else
        local branch
        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
        if [[ "$branch" == "main" || "$branch" == "master" ]]; then
            pom_version="${v}-SNAPSHOT"
        else
            pom_version="$v"
        fi
    fi

    log_info "Updating server/pom.xml to version $pom_version"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} sed version=$pom_version server/pom.xml"
        return
    fi
    sed_inplace "/<artifactId>photo-upload-server<\/artifactId>/{n;s|<version>.*</version>|<version>$pom_version</version>|;}" "$SERVER_DIR/pom.xml"
}

get_platform_args() {
    case "$PLATFORM" in
        amd64) echo "--platform linux/amd64" ;;
        arm64) echo "--platform linux/arm64" ;;
        multi) echo "--platform linux/amd64,linux/arm64" ;;
        *)     echo "" ;;
    esac
}

# Build and (optionally) push a single component.
#   $1 component label (for logging)
#   $2 dockerfile path (relative to repo root)
#   $3 version tag
#   $4..$n image names (without tag)
build_image() {
    local component="$1"
    local dockerfile="$2"
    local version="$3"
    shift 3
    local images=("$@")
    local platform_args
    platform_args=$(get_platform_args)

    local tag_args=""
    for img in "${images[@]}"; do
        tag_args+=" --tag $img:$version --tag $img:latest"
    done

    log_info "Building $component image(s):"
    for img in "${images[@]}"; do
        log_info "  - $img:$version"
    done
    [[ -n "$platform_args" ]] && log_info "Target platform(s): $PLATFORM"

    local cache_flag=""
    [[ "$NO_CACHE" == true ]] && cache_flag=" --no-cache"

    local build_cmd=""
    if [[ "$PLATFORM" == "multi" || ( -n "$platform_args" && "$PLATFORM" != "auto" ) ]]; then
        build_cmd="docker buildx build$cache_flag $platform_args$tag_args"
        if [[ "$PUSH" == true ]]; then
            build_cmd+=" --push"
        elif [[ "$PLATFORM" != "multi" ]]; then
            build_cmd+=" --load"
        else
            log_warning "Multi-platform builds cannot be loaded locally; forcing --push"
            build_cmd+=" --push"
        fi
        build_cmd+=" -f $dockerfile ."
    else
        build_cmd="docker build$cache_flag$tag_args -f $dockerfile ."
        if [[ "$PUSH" == true ]]; then
            for img in "${images[@]}"; do
                build_cmd+=" && docker push $img:$version && docker push $img:latest"
            done
        fi
    fi

    log_verbose "Build command: $build_cmd"
    if execute_cmd "$build_cmd"; then
        log_success "$component image built"
        [[ "$PUSH" == true ]] && log_success "$component pushed to ${#images[@]} registry target(s)"
    else
        log_error "Failed to build $component image"
        exit 1
    fi
}

restart_deployment() {
    local dep="$1"
    log_info "Restarting deployment: $dep"
    if execute_cmd "kubectl rollout restart deployment/$dep"; then
        log_success "Deployment $dep restarted"
        if [[ "$VERBOSE" == true ]]; then
            kubectl rollout status "deployment/$dep" --timeout=300s
        fi
    else
        log_error "Failed to restart deployment: $dep"
        exit 1
    fi
}

execute_build() {
    local version
    version=$(get_version)

    echo -e "${BOLD}=== Build Configuration ===${RESET}"
    echo "Version:           $version"
    echo "Registries:        ${REGISTRIES[*]}"
    echo "Platform:          $PLATFORM"
    echo "Build Frontend:    $BUILD_FRONTEND"
    echo "Build Backend:     $BUILD_BACKEND"
    echo "Push to Registry:  $PUSH"
    echo "Restart K8s:       $RESTART"
    echo "Release build:     $RELEASE_FLAG"
    echo "No-cache build:    $NO_CACHE"
    echo "Dry-run:           $DRY_RUN"
    echo -e "${BOLD}===========================${RESET}"
    echo

    if [[ "$BUILD_FRONTEND" == true ]]; then
        update_frontend_version "$version"
        build_image "frontend" "frontend/Dockerfile-prod" "$version" "${FRONTEND_IMAGES[@]}"
    fi

    if [[ "$BUILD_BACKEND" == true ]]; then
        update_backend_version "$version" "$RELEASE_FLAG"
        build_image "backend" "server/Dockerfile" "$version" "${BACKEND_IMAGES[@]}"
    fi

    if [[ "$RESTART" == true ]]; then
        [[ "$BUILD_FRONTEND" == true ]] && restart_deployment "$FRONTEND_DEPLOYMENT"
        # Backend and worker share the same image (Phase 4 split, see upload-concept-plan.md).
        # Restarting only the backend leaves the worker on its already-cached :latest, which
        # silently runs old code against new schema/jobs. Always roll both together.
        [[ "$BUILD_BACKEND"  == true ]] && restart_deployment "$BACKEND_DEPLOYMENT"
        [[ "$BUILD_BACKEND"  == true ]] && restart_deployment "$WORKER_DEPLOYMENT"
    fi

    echo
    echo -e "${BOLD}${GREEN}All operations completed successfully${RESET}"
}

# Re-arm -SNAPSHOT on frontend and backend after a release build,
# and commit the result on main-style branches.
rearm_snapshot() {
    local v="$1"
    log_info "Re-arming -SNAPSHOT for next development iteration"
    if [[ -f "$FRONTEND_DIR/package.json" ]]; then
        sed_inplace "s/\"version\": \".*\"/\"version\": \"$v-SNAPSHOT\"/" "$FRONTEND_DIR/package.json"
    fi
    if [[ -f "$SERVER_DIR/pom.xml" ]]; then
        sed_inplace "/<artifactId>photo-upload-server<\/artifactId>/{n;s|<version>.*</version>|<version>$v-SNAPSHOT</version>|;}" "$SERVER_DIR/pom.xml"
    fi
    git add "$FRONTEND_DIR/package.json" "$SERVER_DIR/pom.xml"
    git commit -m "Prepare for next development iteration"
}

execute_release() {
    log_info "Starting release process..."

    local current
    current=$(get_version)
    echo "Current version: $current"
    echo
    echo "Select which part to bump (semantic versioning):"
    echo "  1) major  - incompatible API changes"
    echo "  2) minor  - backwards-compatible new features"
    echo "  3) patch  - backwards-compatible bug fixes"
    PS3="Enter choice (1-3): "
    local bump=""
    select b in major minor patch; do
        if [[ -n "$b" ]]; then bump="$b"; break; fi
        echo "Invalid choice."
    done

    local new_version
    new_version=$(bump_semver "$current" "$bump")
    log_info "Releasing version $new_version"

    # Write release versions
    echo "$new_version" > "$VERSION_FILE"
    update_frontend_version "$new_version"
    update_backend_version "$new_version" true

    # Commit + tag the release
    git add "$VERSION_FILE" "$FRONTEND_DIR/package.json" "$SERVER_DIR/pom.xml"
    git commit -m "Release version $new_version"
    git tag "v$new_version"
    log_success "Created git commit and tag v$new_version"

    # Build the release (both components, release mode)
    BUILD_FRONTEND=true
    BUILD_BACKEND=true
    RELEASE_FLAG=true
    execute_build

    # Re-arm -SNAPSHOT + commit
    rearm_snapshot "$new_version"

    echo
    log_success "Release v$new_version complete."
    echo "Next steps:"
    echo "  git push && git push origin v$new_version"
}

show_version() {
    echo "Version: $(get_version)"
}

main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    parse_args "$@"

    if [[ "$HELP" == true ]]; then show_help; exit 0; fi
    if [[ "$SHOW_VERSION" == true ]]; then show_version; exit 0; fi

    check_prerequisites

    if [[ "$RELEASE_MODE" == true ]]; then
        execute_release
    else
        execute_build
    fi
}

main "$@"
