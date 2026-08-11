#!/bin/bash

set -euo pipefail

# Ensure we have a large directory for temporary files inside the container's workspace
# to avoid running out of space on tmpfs /tmp when constructing large images.
mkdir -p /builder/tmp
export TMPDIR=/builder/tmp

# Ensure ownership of the generated artifacts (the host-mounted ./bin) matches the host user upon container exit
cleanup() {
    local exit_code=$?
    if [ -d bin ] && [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
        chown -R "$HOST_UID:$HOST_GID" bin
    fi
    exit $exit_code
}
trap cleanup EXIT

log_error() {
    if [ "${BW_LOG_ENABLE:-1}" == "1" ]; then
        echo -e "\033[31m[ERROR]\033[0m $1"
    fi
}

log_info() {
    # Print informational messages when logging is enabled
    if [ "${BW_LOG_ENABLE:-1}" == "1" ]; then
        echo -e "\033[32m[INFO]\033[0m $1"
    fi
}

log_debug() {
    if [ "${BW_LOG_ENABLE:-1}" == "1" ] && [ "${BW_DEBUG:-0}" == "1" ]; then
        echo -e "\033[33m[DEBUG]\033[0m $1"
    fi
}

# Initialize variables from BW_ prefix environment variables
PROFILE="${BW_PROFILE:-}"

# Module and package control configurations
OVERRIDE_MODULES="${BW_OVERRIDE_MODULES:-}"
ADJUST_MODULES="${BW_ADJUST_MODULES:-}"
EXTRA_PACKAGES="${BW_EXTRA_PACKAGES:-}"
DISABLED_SERVICES="${BW_DISABLED_SERVICES:-}"

# Target image customization configurations
EXTRA_IMAGE_NAME="${BW_EXTRA_IMAGE_NAME:-}"
ROOTFS_PARTSIZE="${BW_ROOTFS_PARTSIZE:-}"

# Network mirror and package download acceleration configurations
SETUP_USE_MIRROR="${BW_SETUP_USE_MIRROR:-0}"
BUILD_USE_MIRROR="${BW_USE_MIRROR:-0}"
MIRROR="${BW_MIRROR:-}"

# Initialize and setup the ImageBuilder environment if core directories or Makefile are missing.
if [ ! -f ./Makefile ] || \
   [ ! -d ./scripts ] || \
   [ ! -d ./target ] || \
   [ ! -d ./include ] || \
   { [ ! -f ./repositories ] && [ ! -f ./repositories.conf ]; }; then
    log_info "ImageBuilder environment missing or incomplete; running setup process"
    
    # Define and export custom wget function: remove -nv, -q, etc. to force progress bar display
    wget() {
        local clean_args=()
        for arg in "$@"; do
            if [[ "$arg" != "-nv" && "$arg" != "--no-verbose" && "$arg" != "-q" && "$arg" != "--quiet" ]]; then
                clean_args+=("$arg")
            fi
        done
        command wget --progress=bar:force:noscroll --show-progress "${clean_args[@]}"
    }
    export -f wget

    # Save the original VERSION_PATH
    ORIGINAL_VERSION_PATH="${VERSION_PATH:-}"

    # If VERSION_PATH points to a SNAPSHOT release (e.g. releases/25.12-SNAPSHOT),
    # temporarily rewrite it to "snapshots" so setup.sh downloads from the correct directory.
    if [[ "$VERSION_PATH" == *SNAPSHOT* ]]; then
        log_info "Detected SNAPSHOT version path '$VERSION_PATH', temporarily rewriting to 'snapshots' for setup.sh"
        export VERSION_PATH="snapshots"
    fi

    setup_success=0

    # Decide whether setup.sh's lazy tool-package download should use a mirror.
    # Only when VERSION_PATH is "snapshots" and SETUP_USE_MIRROR is enabled do we
    # fetch tool-packages from the USTC mirror; otherwise skip the mirror attempt.
    if [[ "$VERSION_PATH" == "snapshots" && "$SETUP_USE_MIRROR" == "1" ]]; then
        export UPSTREAM_URL="https://mirrors.ustc.edu.cn/openwrt"
        log_info "Attempting to setup ImageBuilder using USTC mirror: $UPSTREAM_URL"
        
        # Run setup.sh in a subshell or temporarily disable set -e to handle failures gracefully
        set +e
        ( . ./setup.sh )
        setup_status=$?
        set -e

        if [ $setup_status -eq 0 ]; then
            setup_success=1
            log_info "Successfully setup ImageBuilder using USTC mirror."
        else
            log_error "Failed to setup ImageBuilder using USTC mirror. Falling back to official OpenWrt source..."
        fi
    fi

    # 2. Second Attempt: Official Source (if USTC mirror failed or was not requested)
    if [ "$setup_success" -eq 0 ]; then
        # Unset UPSTREAM_URL so setup.sh defaults to official downloads.openwrt.org
        unset UPSTREAM_URL
        log_info "Attempting to setup ImageBuilder using official OpenWrt source..."
        . ./setup.sh
        log_info "Successfully setup ImageBuilder using official source."
    fi

    # Restore the original VERSION_PATH if it was temporarily rewritten
    if [ -n "$ORIGINAL_VERSION_PATH" ]; then
        export VERSION_PATH="$ORIGINAL_VERSION_PATH"
    fi
fi

# Apply mirror replacement to repositories/repositories.conf if BUILD_USE_MIRROR is enabled
if [ "$BUILD_USE_MIRROR" == "1" ] && [ -n "${MIRROR:-}" ]; then
    repo_file=""
    if [ -f ./repositories.conf ]; then
        repo_file="./repositories.conf"
    elif [ -f ./repositories ]; then
        repo_file="./repositories"
    fi

    if [ -n "$repo_file" ]; then
        log_info "Replacing package mirror in $repo_file with $MIRROR"
        sed -i -E "s|https?://downloads.openwrt.org|https://${MIRROR}|g" "$repo_file"
    fi
fi

DEFAULT_MODULES="base system root-password pppoe main-router disable-ipv6 extras"

log_info "Detected OpenWrt version: ${VERSION_PATH##*/}"
export VERSION_PATH
log_info "Default modules: $DEFAULT_MODULES"
log_info "ADJUST_MODULES: ${ADJUST_MODULES:-<none>}"
log_info "OVERRIDE_MODULES: ${OVERRIDE_MODULES:-<none>}"

# Copy modules from container storage to active build locations
cp -r modules_in_container modules
if [ -d custom_modules_in_container ]; then
    cp -r custom_modules_in_container custom_modules
fi

module_exists() {
    local mod="$1"
    [ -d "modules/$mod" ] || { [ -d "custom_modules" ] && [ -d "custom_modules/$mod" ]; }
}

is_in_default_modules() {
    local mod="$1"
    local m
    for m in $DEFAULT_MODULES; do
        if [ "$m" == "$mod" ]; then
            return 0
        fi
    done
    return 1
}

ACTIVE_MODULES=""
if [ -n "${OVERRIDE_MODULES:-}" ]; then
    # Validate each module in OVERRIDE_MODULES exists
    for module in $OVERRIDE_MODULES; do
        if ! module_exists "$module"; then
            log_error "Module '$module' specified in OVERRIDE_MODULES does not exist"
            exit 1
        fi
    done
    ACTIVE_MODULES="$OVERRIDE_MODULES"
    log_info "Using OVERRIDE_MODULES: $ACTIVE_MODULES"
else
    # Fallback to default modules and apply ADJUST_MODULES additions/removals
    ACTIVE_MODULES="$DEFAULT_MODULES"
    for module in ${ADJUST_MODULES:-}; do
        # Check if module starts with "-" (exclusion prefix)
        if [ "${module:0:1}" == "-" ]; then
            module_to_remove="${module:1}"
            # Check if the module to remove is in DEFAULT_MODULES
            if ! is_in_default_modules "$module_to_remove"; then
                log_info "Module '$module_to_remove' marked for removal is not in DEFAULT_MODULES, ignoring"
                continue
            fi
            new_list=""
            for active_module in $ACTIVE_MODULES; do
                if [ "$active_module" != "$module_to_remove" ]; then
                    if [ -z "$new_list" ]; then
                        new_list="$active_module"
                    else
                        new_list="$new_list $active_module"
                    fi
                fi
            done
            ACTIVE_MODULES="$new_list"
        else
            # Verify module exists
            if ! module_exists "$module"; then
                log_error "Module '$module' specified in ADJUST_MODULES does not exist"
                exit 1
            fi
            # Avoid duplicate module addition
            is_duplicate=0
            for active_module in $ACTIVE_MODULES; do
                if [ "$active_module" == "$module" ]; then
                    is_duplicate=1
                    break
                fi
            done
            if [ "$is_duplicate" -eq 0 ]; then
                ACTIVE_MODULES="$ACTIVE_MODULES $module"
            fi
        fi
    done
fi

log_info "Resolved active modules: $ACTIVE_MODULES"

FINAL_PACKAGES=

collect_packages() {
    local dir="$1"
    local mod="$2"
    if [ -f "$dir/$mod/packages" ]; then
        local res
        res=$(. "$dir/$mod/packages" 2>/dev/null || cat "$dir/$mod/packages")
        if [ -n "$res" ]; then
            FINAL_PACKAGES="$FINAL_PACKAGES $res"
        fi
    fi
}

merge_extra_packages() {
    [ -z "${EXTRA_PACKAGES:-}" ] && return 0
    log_info "Merging EXTRA_PACKAGES: $EXTRA_PACKAGES"
    FINAL_PACKAGES="$FINAL_PACKAGES $EXTRA_PACKAGES"
}

deduplicate_packages() {
    local list="$1"
    local unique=""
    for pkg in $list; do
        local found=0
        for u in $unique; do
            if [ "$u" = "$pkg" ]; then
                found=1
                break
            fi
        done
        if [ "$found" -eq 0 ]; then
            unique="$unique $pkg"
        fi
    done
    echo "$unique"
}

check_package_conflicts() {
    local list="$1"
    for pkg in $list; do
        # If the package starts with '-', it's a negative package
        if [ "${pkg:0:1}" = "-" ]; then
            local pos_pkg="${pkg:1}"
            # Check if positive package is also in the list
            for p in $list; do
                if [ "$p" = "$pos_pkg" ]; then
                    log_error "Package conflict detected: '$pos_pkg' and '$pkg' cannot both be specified"
                    exit 1
                fi
            done
        fi
    done
}

clean_value() {
    local val="$1"
    # Remove leading/trailing whitespace
    val="${val##[[:space:]]}"
    val="${val%%[[:space:]]}"
    # Strip leading/trailing double quotes
    val="${val#\"}"
    val="${val%\"}"
    # Strip leading/trailing single quotes
    val="${val#\'}"
    val="${val%\'}"
    echo -n "$val"
}

is_text_file() {
    local file="$1"
    # Use file utility if available, or fallback to checking with grep/head
    if command -v file >/dev/null 2>&1; then
        file "$file" | grep -qE 'text|empty|XML|JSON'
    else
        # Fallback check: check for any non-printable and non-whitespace characters
        ! LC_ALL=C grep -q '[^[:print:][:space:]]' "$file" < /dev/null 2>/dev/null
    fi
}

# Global associative array to store the resolved variables for the current module
declare -A CURRENT_MODULE_ENV

collect_module_env() {
    local dir="$1"
    local mod="$2"

    # Reset the associative array
    CURRENT_MODULE_ENV=()

    local module_env_file="$dir/$mod/.env"

    # Get a list of all variable names the module declares. We scan BOTH the
    # module's .env and .env.example files so that variables that are passed
    # solely through environment variables (e.g. BW_MAIN_LAN_IP=... ./run.sh) are
    # still discovered and substituted, even when no '.env' file exists.
    local var_names=""
    local env_desc_file
    for env_desc_file in "$dir/$mod/.env" "$dir/$mod/.env.example"; do
        if [ -f "$env_desc_file" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                # Skip empty or comment lines
                [[ "$line" =~ ^[[:space:]]*# ]] && continue
                [[ -z "${line//[[:space:]]/}" ]] && continue
                local var_name="${line%%=*}"
                var_name="${var_name##[[:space:]]}"
                var_name="${var_name%%[[:space:]]}"
                if [ -n "$var_name" ]; then
                    var_names="$var_names $var_name"
                fi
            done < "$env_desc_file"
        fi
    done

    # Deduplicate variable names
    var_names=$(echo "$var_names" | tr ' ' '\n' | sort -u | tr '\n' ' ')

    for var_name in $var_names; do
        local env_val="${!var_name:-}"

        # Parse value from global .env if it exists
        local global_val=""
        if [ -f .env ]; then
            local global_line
            global_line=$(grep -E "^[[:space:]]*$var_name[[:space:]]*=" .env | tail -n 1 || true)
            if [ -n "$global_line" ]; then
                global_val=$(clean_value "${global_line#*=}")
            fi
        fi

        # Parse value from module .env if it exists
        local mod_val=""
        if [ -f "$module_env_file" ]; then
            local mod_line
            mod_line=$(grep -E "^[[:space:]]*$var_name[[:space:]]*=" "$module_env_file" | tail -n 1 || true)
            if [ -n "$mod_line" ]; then
                mod_val=$(clean_value "${mod_line#*=}")
            fi
        fi

        local final_val=""
        # Priority resolution logic:
        # 1. Environment variable (passed from run.sh / compose) takes highest priority
        if [ -n "$env_val" ]; then
            final_val="$env_val"
        fi

        # 2. Module's own .env value
        if [ -z "$final_val" ] && [ -n "$mod_val" ]; then
            final_val="$mod_val"
        fi

        # 3. Global .env value
        if [ -z "$final_val" ] && [ -n "$global_val" ]; then
            final_val="$global_val"
        fi

        CURRENT_MODULE_ENV["$var_name"]="$final_val"
    done
}

is_shell_script() {
    local file="$1"

    # 1. Check if extension is .sh
    if [[ "$file" == *.sh ]]; then
        return 0
    fi

    # 2. Check if located under etc/uci-defaults/ (OpenWrt boot scripts)
    if [[ "$file" == */etc/uci-defaults/* ]]; then
        return 0
    fi

    return 1
}

apply_env() {
    local dir="$1"
    local mod="$2"
    [ -d "$dir/$mod/files" ] || return 0

    collect_module_env "$dir" "$mod"

    # Now substitute all text files in files/ directory
    for f in $(find "$dir/$mod/files" -type f); do
        if is_text_file "$f"; then
            local is_shell=0
            if is_shell_script "$f"; then
                is_shell=1
            fi
            for var_name in "${!CURRENT_MODULE_ENV[@]}"; do
                local val="${CURRENT_MODULE_ENV[$var_name]}"
                log_debug "Substituting variable '$var_name' with '$val' in $f"
                local final_val="$val"
                # If target is a shell script, escape shell metacharacters (\, $, `, ")
                # so the value stays literal when evaluated at runtime.
                if [ "$is_shell" -eq 1 ]; then
                    final_val=$(printf '%s' "$final_val" | sed -e 's/[\\$`"]/\\&/g')
                fi
                # Perform robust literal string substitution using awk split
                export AWK_VAR_NAME="$var_name"
                export AWK_VAR_VAL="$final_val"
                awk '
                BEGIN {
                    target = "\\$" ENVIRON["AWK_VAR_NAME"]
                    repl = ENVIRON["AWK_VAR_VAL"]
                }
                {
                    n = split($0, parts, target)
                    out = parts[1]
                    for (i = 2; i <= n; i++) {
                        out = out repl parts[i]
                    }
                    print out
                }
                ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
                unset AWK_VAR_NAME
                unset AWK_VAR_VAL
            done
        fi
    done
}

copy_files() {
    local dir="$1"
    local mod="$2"
    [ -d "$dir/$mod/files" ] || return 0

    mkdir -p files
    # Copy files while avoiding duplicates
    # Skip possible .DS_Store files
    while IFS= read -r source_file; do
        local target_file="files/${source_file#$dir/$mod/files/}"
        if [ -f "$target_file" ]; then
            log_error "Duplicate file detected: $target_file"
            exit 1
        fi
        mkdir -p "$(dirname "$target_file")"
        cp "$source_file" "$target_file"
    done < <(find "$dir/$mod/files" -type f | grep -v .DS_Store || true)
}

run_post_scripts() {
    local dir="$1"
    local mod="$2"
    if [ -f "$dir/$mod/post-script.sh" ]; then
        log_info "Running post-processing script for module '$mod'"
        . "$dir/$mod/post-script.sh"
    fi
}

process_dir() {
    local dir=$1
    local mod

    for mod in $ACTIVE_MODULES; do
        [ -d "$dir/$mod" ] || continue
        log_info "Processing module '$mod' from '$dir'"

        collect_packages "$dir" "$mod"
        apply_env "$dir" "$mod"
        copy_files "$dir" "$mod"
        run_post_scripts "$dir" "$mod"
    done
}

log_info "Validating active modules..."
for mod in $ACTIVE_MODULES; do
    if [ ! -d "modules/$mod" ] && [ ! -d "custom_modules/$mod" ]; then
        log_error "Module not found: '$mod'"
        exit 1
    fi
done

process_dir modules
process_dir custom_modules

merge_extra_packages
FINAL_PACKAGES=$(deduplicate_packages "$FINAL_PACKAGES")
check_package_conflicts "$FINAL_PACKAGES"

log_info "Collected packages: ${FINAL_PACKAGES:-<none>}"

log_info "Contents of custom files overlay:"
ls files -R
log_info ""

MAKE_ARGS="PACKAGES=\"$FINAL_PACKAGES\" FILES=\"files\""
if [ ! -z "${EXTRA_IMAGE_NAME:-}" ]; then
    MAKE_ARGS="$MAKE_ARGS EXTRA_IMAGE_NAME=\"$EXTRA_IMAGE_NAME\""
fi
if [ ! -z "${DISABLED_SERVICES:-}" ]; then
    MAKE_ARGS="$MAKE_ARGS DISABLED_SERVICES=\"$DISABLED_SERVICES\""
fi
if [ ! -z "${ROOTFS_PARTSIZE:-}" ]; then
    MAKE_ARGS="$MAKE_ARGS ROOTFS_PARTSIZE=\"$ROOTFS_PARTSIZE\""
fi

make info
if [ -z "$PROFILE" ]; then
    eval make image $MAKE_ARGS -S
else
    eval make PROFILE=\"$PROFILE\" image $MAKE_ARGS -S
fi
