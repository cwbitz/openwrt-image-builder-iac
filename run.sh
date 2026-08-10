#!/bin/bash

set -euo pipefail

# Optional logging and debug configurations (defaults)
BW_LOG_ENABLE="${BW_LOG_ENABLE:-1}"
BW_DEBUG="${BW_DEBUG:-0}"

log_error() {
    if [ "$BW_LOG_ENABLE" == "1" ]; then
        echo -e "\033[31m[ERROR]\033[0m $1" >&2
    fi
}

log_warn() {
    if [ "$BW_LOG_ENABLE" == "1" ]; then
        echo -e "\033[33m[WARN]\033[0m $1" >&2
    fi
}

log_info() {
    if [ "$BW_LOG_ENABLE" == "1" ]; then
        echo -e "\033[32m[INFO]\033[0m $1"
    fi
}

log_debug() {
    if [ "$BW_LOG_ENABLE" == "1" ] && [ "$BW_DEBUG" == "1" ]; then
        echo -e "\033[36m[DEBUG]\033[0m $1"
    fi
}

usage()
{
    echo "Usage: ./run.sh [OPTIONS]"
    echo ""
    echo "Docker container and pull policies:"
    echo "  -i | --image                specify the openwrt/imagebuilder Docker image; find it at https://hub.docker.com/r/openwrt/imagebuilder/tags"
    echo "  -P | --force-pull           pull the image before building"
    echo "  -R | --force-recreate       remove the existing container before building"
    echo ""
    echo "Query image info:"
    echo "  -I | --info                 query basic image and profile information before building (conflicts with options other than --image)"
    echo ""
    echo "Target profile config:"
    echo "  -p | --profile              specify the build profile (defaults to target's first profile if omitted)"
    echo ""
    echo "Module and package control configurations:"
    echo "  -O | --override-modules     specify a complete list of modules to build, bypassing defaults (e.g. \"base lan prefer-ipv6 extras\")"
    echo "  -a | --adjust-modules       specify adjustments to the default module set (e.g. \"statistics -extras\")"
    echo "  -e | --extra-packages       specify an explicit PACKAGES list for imagebuilder"
    echo "  -d | --disabled-services    specify DISABLED_SERVICES for imagebuilder"
    echo ""
    echo "Target image customization configurations:"
    echo "  -E | --extra-image-name     specify a custom string to append to the output image filename"
    echo "  -r | --rootfs-partsize      specify the root partition size in MB (defaults to target's default if omitted)"
    echo ""
    echo "Output, local custom modules, and mirror network configurations:"
    echo "  -o | --output-dir           specify the output directory for build artifacts (default: ./artifacts)"
    echo "  -c | --custom-modules-path  specify the path to custom modules directory (default: ./custom_modules)"
    echo "  -u | --use-mirror           enable mirror usage (defaults to mirrors.tuna.tsinghua.edu.cn if --mirror is not specified)"
    echo "  -m | --mirror               specify a custom mirror host, e.g. mirrors.ustc.edu.cn (do not include http:// or https://)"
    echo ""
    echo "Help:"
    echo "  -h | --help                 print this help message"
    exit 1
}

# Docker container and pull policies
BW_IMAGE="${BW_IMAGE:-}"
FORCE_PULL="${BW_FORCE_PULL:-0}"
FORCE_RECREATE="${BW_FORCE_RECREATE:-0}"
SHOW_INFO="${BW_SHOW_INFO:-0}"

# Target profile config
BW_PROFILE="${BW_PROFILE:-}"

# Module and package control configurations
BW_OVERRIDE_MODULES="${BW_OVERRIDE_MODULES:-}"
BW_ADJUST_MODULES="${BW_ADJUST_MODULES:-}"
BW_EXTRA_PACKAGES="${BW_EXTRA_PACKAGES:-}"
BW_DISABLED_SERVICES="${BW_DISABLED_SERVICES:-}"

# Target image customization configurations
BW_EXTRA_IMAGE_NAME="${BW_EXTRA_IMAGE_NAME:-}"
BW_ROOTFS_PARTSIZE="${BW_ROOTFS_PARTSIZE:-}"

# Output, local custom modules, and mirror network configurations
BW_OUTPUT_DIR="${BW_OUTPUT_DIR:-./artifacts}"
BW_CUSTOM_MODULES_PATH="${BW_CUSTOM_MODULES_PATH:-./custom_modules}"
BW_USE_MIRROR="${BW_USE_MIRROR:-0}"
BW_MIRROR="${BW_MIRROR:-mirrors.tuna.tsinghua.edu.cn}"

# Check for help flags first
HAS_HELP=0
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            HAS_HELP=1
            break
            ;;
    esac
done

if [ "$HAS_HELP" -eq 1 ]; then
    if [ "$#" -gt 1 ]; then
        # Find the first non-help parameter to report as wrong parameter
        for arg in "$@"; do
            case "$arg" in
                -h|--help)
                    ;;
                *)
                    echo "Wrong parameter"
                    echo ""
                    break
                    ;;
            esac
        done
    fi
    usage
fi

HAS_CONFLICTING_PARAM=0

while [ $# -gt 0 ]; do
    case "$1" in
        # Docker container and pull policies
        -i|--image)
            if [ $# -lt 2 ]; then echo "Wrong parameter"; echo ""; usage; fi
            BW_IMAGE="$2"
            shift 2
            ;;
        -i=*|--image=*)
            BW_IMAGE="${1#*=}"
            shift 1
            ;;
        -i*)
            BW_IMAGE="${1#-i}"
            shift 1
            ;;
        -P|--force-pull)
            FORCE_PULL=1
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;
        -R|--force-recreate)
            FORCE_RECREATE=1
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;
        -I|--info)
            SHOW_INFO=1
            shift 1
            ;;

        # Target profile config
        -p|--profile)
            if [ $# -lt 2 ]; then echo "Wrong parameter"; echo ""; usage; fi
            BW_PROFILE="$2"
            HAS_CONFLICTING_PARAM=1
            shift 2
            ;;
        -p=*|--profile=*)
            BW_PROFILE="${1#*=}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;
        -p*)
            BW_PROFILE="${1#-p}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;

        # Module and package control configurations
        -O|--override-modules)
            if [ $# -lt 2 ]; then echo "Wrong parameter"; echo ""; usage; fi
            BW_OVERRIDE_MODULES="$2"
            HAS_CONFLICTING_PARAM=1
            shift 2
            ;;
        -O=*|--override-modules=*)
            BW_OVERRIDE_MODULES="${1#*=}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;
        -O*)
            BW_OVERRIDE_MODULES="${1#-O}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;

        -a|--adjust-modules)
            if [ $# -lt 2 ]; then echo "Wrong parameter"; echo ""; usage; fi
            BW_ADJUST_MODULES="$2"
            HAS_CONFLICTING_PARAM=1
            shift 2
            ;;
        -a=*|--adjust-modules=*)
            BW_ADJUST_MODULES="${1#*=}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;
        -a*)
            BW_ADJUST_MODULES="${1#-a}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;

        -e|--extra-packages)
            if [ $# -lt 2 ]; then echo "Wrong parameter"; echo ""; usage; fi
            BW_EXTRA_PACKAGES="$2"
            HAS_CONFLICTING_PARAM=1
            shift 2
            ;;
        -e=*|--extra-packages=*)
            BW_EXTRA_PACKAGES="${1#*=}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;
        -e*)
            BW_EXTRA_PACKAGES="${1#-e}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;

        -d|--disabled-services)
            if [ $# -lt 2 ]; then echo "Wrong parameter"; echo ""; usage; fi
            BW_DISABLED_SERVICES="$2"
            HAS_CONFLICTING_PARAM=1
            shift 2
            ;;
        -d=*|--disabled-services=*)
            BW_DISABLED_SERVICES="${1#*=}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;
        -d*)
            BW_DISABLED_SERVICES="${1#-d}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;

        # Target image customization configurations
        -E|--extra-image-name)
            if [ $# -lt 2 ]; then echo "Wrong parameter"; echo ""; usage; fi
            BW_EXTRA_IMAGE_NAME="$2"
            HAS_CONFLICTING_PARAM=1
            shift 2
            ;;
        -E=*|--extra-image-name=*)
            BW_EXTRA_IMAGE_NAME="${1#*=}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;
        -E*)
            BW_EXTRA_IMAGE_NAME="${1#-E}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;

        -r|--rootfs-partsize)
            if [ $# -lt 2 ]; then echo "Wrong parameter"; echo ""; usage; fi
            BW_ROOTFS_PARTSIZE="$2"
            HAS_CONFLICTING_PARAM=1
            shift 2
            ;;
        -r=*|--rootfs-partsize=*)
            BW_ROOTFS_PARTSIZE="${1#*=}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;
        -r*)
            BW_ROOTFS_PARTSIZE="${1#-r}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;

        # Output, local custom modules, and mirror network configurations
        -o|--output-dir)
            if [ $# -lt 2 ]; then echo "Wrong parameter"; echo ""; usage; fi
            BW_OUTPUT_DIR="$2"
            HAS_CONFLICTING_PARAM=1
            shift 2
            ;;
        -o=*|--output-dir=*)
            BW_OUTPUT_DIR="${1#*=}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;
        -o*)
            BW_OUTPUT_DIR="${1#-o}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;

        -c|--custom-modules-path)
            if [ $# -lt 2 ]; then echo "Wrong parameter"; echo ""; usage; fi
            BW_CUSTOM_MODULES_PATH="$2"
            HAS_CONFLICTING_PARAM=1
            shift 2
            ;;
        -c=*|--custom-modules-path=*)
            BW_CUSTOM_MODULES_PATH="${1#*=}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;
        -c*)
            BW_CUSTOM_MODULES_PATH="${1#-c}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;

        -u|--use-mirror)
            BW_USE_MIRROR=1
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;

        -m|--mirror)
            if [ $# -lt 2 ]; then echo "Wrong parameter"; echo ""; usage; fi
            BW_MIRROR="$2"
            HAS_CONFLICTING_PARAM=1
            shift 2
            ;;
        -m=*|--mirror=*)
            BW_MIRROR="${1#*=}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;
        -m*)
            BW_MIRROR="${1#-m}"
            HAS_CONFLICTING_PARAM=1
            shift 1
            ;;

        # Help
        -h|--help)
            usage
            ;;
        *)
            echo "Wrong parameter"
            echo ""
            usage
            ;;
    esac
done

# Validate --override-modules does not contain negative module entries (starting with '-')
if [ -n "$BW_OVERRIDE_MODULES" ]; then
    for item in $BW_OVERRIDE_MODULES; do
        if [[ "$item" == -* ]]; then
            echo "Wrong parameter"
            echo ""
            usage
        fi
    done
fi

if [ "$SHOW_INFO" -eq 1 ]; then
    # Check for parameter conflicts when querying image info.
    # Only --image and --info are allowed.
    if [ "$HAS_CONFLICTING_PARAM" -eq 1 ]; then
        echo "Wrong parameter"
        echo ""
        usage
    fi
fi

if [ -z "${BW_IMAGE:-}" ]; then
    echo "Wrong parameter"
    echo ""
    usage
fi

if [[ "$BW_IMAGE" != openwrt/imagebuilder* ]]; then
    echo "Wrong parameter"
    echo ""
    usage
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OS_NAME=$(uname -s)
case "$OS_NAME" in
    Darwin)
        OS_LABEL="macOS"
        # Ensure the Docker CLI can be discovered on macOS.
        export PATH="/usr/local/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
        ;;
    Linux)
        OS_LABEL="Linux"
        ;;
    *)
        log_error "Unsupported host OS: $OS_NAME"
        log_error "This script only supports macOS and Linux."
        exit 1
        ;;
esac

log_info "Detected OS: $OS_LABEL"

HOST_UID=$(id -u)
HOST_GID=$(id -g)

# Reject running as root user or root primary group on any host OS.
if { [ "$HOST_UID" -eq 0 ] || [ "$HOST_GID" -eq 0 ]; }; then
    log_error "Do not run this script as root or with root primary group."
    log_error "Use a regular user account with Docker permissions instead."
    exit 1
fi

# Verify Docker is available
if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker was not found. Please make sure Docker is installed and running on $OS_LABEL."
    echo "Possible locations:"
    if [ "$OS_NAME" = "Darwin" ]; then
        echo "  - /usr/local/bin/docker (Intel Mac Homebrew)"
        echo "  - /opt/homebrew/bin/docker (Apple Silicon Homebrew)"
        echo "  - /Applications/Docker.app/Contents/Resources/bin/docker (Docker Desktop)"
    elif [ "$OS_NAME" = "Linux" ]; then
        echo "  - /usr/bin/docker"
        echo "  - /usr/local/bin/docker"
    fi
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    log_error "Docker is installed but the daemon is not running. Please start Docker manually."
    exit 1
fi

compose() {
    if docker compose version >/dev/null 2>&1; then
        docker compose "$@"
    elif command -v docker-compose >/dev/null 2>&1; then
        docker-compose "$@"
    else
        log_error "Docker Compose is not available. Install Docker Desktop or the docker-compose CLI."
        exit 1
    fi
}

log_info "Image: $BW_IMAGE"

if [ "$SHOW_INFO" -eq 1 ]; then
    log_info "Querying image info..."
    if [ "$FORCE_PULL" -eq 1 ] || ! docker image inspect "$BW_IMAGE" >/dev/null 2>&1; then
        log_info "Pulling image..."
        docker pull "$BW_IMAGE"
        echo ""
        log_info "Image pulled successfully."
        echo ""
    fi
    log_info "Showing image info:"
    echo ""
    docker run --rm "$BW_IMAGE" make info
    exit 0
fi

# Inspect image to get VERSION_PATH and TARGET for dynamic container naming
log_info "Inspecting image metadata..."
# Ensure the image is available locally before inspecting
if ! docker image inspect "$BW_IMAGE" >/dev/null 2>&1; then
    log_info "Image not found locally, pulling..."
    docker pull "$BW_IMAGE"
    echo ""
    log_info "Image pulled successfully."
    echo ""
fi

IMG_VERSION_PATH=""
IMG_TARGET=""

# Parse VERSION_PATH and TARGET using pure Bash to avoid spawning subprocesses
while IFS= read -r line; do
    case "$line" in
        VERSION_PATH=*) IMG_VERSION_PATH="${line#*=}" ;;
        TARGET=*)       IMG_TARGET="${line#*=}" ;;
    esac
done < <(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "$BW_IMAGE")

BW_VERSION="${IMG_VERSION_PATH##*/}"
BW_TARGET="${IMG_TARGET//\//-}"

if [ -n "$BW_VERSION" ] && [ -n "$BW_TARGET" ]; then
    CONTAINER_NAME="openwrt-bw-${BW_TARGET}-${BW_VERSION}"
else
    log_error "Failed to extract VERSION_PATH or TARGET from image metadata."
    exit 1
fi

log_info "Container name: $CONTAINER_NAME"
log_info "Profile: ${BW_PROFILE:-<none>}"
log_info "Output directory: $BW_OUTPUT_DIR"
log_info "Custom modules directory: $BW_CUSTOM_MODULES_PATH"
log_info "Extra packages: ${BW_EXTRA_PACKAGES:-<none>}"
log_info "Extra image name suffix: ${BW_EXTRA_IMAGE_NAME:-<none>}"
log_info "Disabled services: ${BW_DISABLED_SERVICES:-<none>}"
log_info "Rootfs partition size: ${BW_ROOTFS_PARTSIZE:-<none>}"

# Use the official imagebuilder container working directory
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# Cleanup on normal exit and on forced interruptions (Ctrl+C / SIGTERM).
# Removes the temporary compose file and force-removes the build container so
# a Ctrl+C abort never leaves a stale container behind.
cleanup() {
    # Remove the temporary compose file so we never leave anything behind.
    rm -f "$COMPOSE_FILE"
    # Force-remove the build container if one was created.
    if [ -n "${CONTAINER_NAME:-}" ]; then
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
# Re-raise as the conventional exit codes (130 = SIGINT, 143 = SIGTERM) while
# cleaning up first; the EXIT trap runs again after these, which is idempotent.
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

append_env_var() {
    local name="$1"
    local value="$2"

    if [ -n "$value" ]; then
        # Escape the value for a docker-compose YAML double-quoted scalar.
        # docker-compose performs variable interpolation on $ before YAML parses:
        #   $$ -> $, ${VAR} -> value, $name -> value (or blank). A raw $ in the
        #   value (e.g. a password "pa$$w@rd") would therefore be mangled.
        # Fixes: $ -> $$ (compose escape) and backslash / double quote -> YAML escapes.
        local escaped
        escaped=$(printf '%s' "$value" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/$$/g')
        printf '      %s: "%s"\n' "$name" "$escaped" >> "$COMPOSE_FILE"
    fi
}

cat > "$COMPOSE_FILE" <<-END
services:
  imagebuilder:
    image: "$BW_IMAGE"
    container_name: "$CONTAINER_NAME"
    user: "0:0"
    volumes:
      - $BW_OUTPUT_DIR:/builder/bin
      - ./build.sh:/builder/build.sh
      - ./.env:/builder/.env
      - ./modules:/builder/modules_in_container
END

if [ -d "$BW_CUSTOM_MODULES_PATH" ]; then
    cat >> "$COMPOSE_FILE" <<-END
      - $BW_CUSTOM_MODULES_PATH:/builder/custom_modules_in_container
END
fi

cat >> "$COMPOSE_FILE" <<-END
    command: "./build.sh"
    environment:
END

for var in BW_ADJUST_MODULES BW_DEBUG BW_DISABLED_SERVICES BW_EXTRA_IMAGE_NAME BW_EXTRA_PACKAGES \
           BW_FORCE_PULL BW_FORCE_RECREATE BW_IMAGE BW_LOG_ENABLE BW_MIRROR BW_OVERRIDE_MODULES \
           BW_PROFILE BW_ROOTFS_PARTSIZE BW_SHOW_INFO BW_USE_MIRROR HOST_GID HOST_UID; do
    append_env_var "$var" "${!var:-}"
done

# Dynamically detect and forward module-level environment variables set on the host
# We scan .env.example files to know which variables are defined by modules
if [ -d modules ]; then
    while IFS= read -r env_file; do
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip empty or comment lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line//[[:space:]]/}" ]] && continue
            
            # Extract variable name (left of first '=')
            var_name="${line%%=*}"
            # Trim whitespace
            var_name=$(echo "$var_name" | tr -d '[:space:]')
            
            if [ -n "$var_name" ] && [ -n "${!var_name:-}" ]; then
                append_env_var "$var_name" "${!var_name:-}"
            fi
        done < "$env_file"
    done < <(find modules "$BW_CUSTOM_MODULES_PATH" -name ".env.example" 2>/dev/null || true)
fi

log_info "Wrote temporary compose file to $COMPOSE_FILE"

PULL_FLAG="--pull missing"
if [ "$FORCE_PULL" -eq 1 ]; then
    PULL_FLAG="--pull always"
fi

if [ "$FORCE_RECREATE" -eq 1 ]; then
    log_info "Removing any existing container: $CONTAINER_NAME"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

mkdir -p "$BW_OUTPUT_DIR"

if [ ! -f .env ]; then
    log_warn ".env file not found; using default values."
    echo "" > .env
fi

log_info "Starting build container"
set +e
# Filter out noisy 'Aborting on container exit' and 'Stopping/Stopped' lifecycle messages.
compose up $PULL_FLAG --exit-code-from imagebuilder --remove-orphans 2> >(grep -v -E "Aborting on container exit|Stopping|Stopped|remove" >&2)
build_status=$?
set -e

compose rm -f >/dev/null 2>&1 || true

if [ $build_status -ne 0 ]; then
    log_error "Build failed with exit code $build_status."
    exit 1
fi

log_info "Build completed successfully"
log_info "Listing artifacts in $BW_OUTPUT_DIR"
ls -R "$BW_OUTPUT_DIR"
