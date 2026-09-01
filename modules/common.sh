#!/usr/bin/env bash

# Shared installer helpers.
#
# This file is sourced by install.sh. It must not execute installation
# actions merely by being sourced.

###############################################################################
# Output
###############################################################################

info() {
    printf 'INFO: %s\n' "$*"
}

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

error() {
    printf 'ERROR: %s\n' "$*" >&2
}

die() {
    error "$*"
    exit 1
}

###############################################################################
# Boolean helpers
###############################################################################

is_true() {
    case "${1:-}" in
        true|TRUE|yes|YES|1)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_false() {
    case "${1:-}" in
        false|FALSE|no|NO|0)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

require_boolean() {
    local variable_name="$1"
    local value="${!variable_name:-}"

    if ! is_true "$value" && ! is_false "$value"; then
        die "$variable_name must be true or false. Current value: '${value:-<unset>}'"
    fi
}

###############################################################################
# Command helpers
###############################################################################

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_command() {
    local command_name="$1"

    command_exists "$command_name" ||
        die "Required command not found: $command_name"
}

###############################################################################
# Retry (transient network / repository operations only)
###############################################################################

# Override in tests: RETRY_BACKOFF_SECONDS=(0 0)
RETRY_BACKOFF_SECONDS=(2 5 10)

run_with_retry() {
    local description="$1"
    shift

    local delays=("${RETRY_BACKOFF_SECONDS[@]}")
    local max_attempts=$((${#delays[@]} + 1))
    local attempt=1
    local delay

    while true; do
        if "$@"; then
            return 0
        fi

        if (( attempt >= max_attempts )); then
            error "Giving up after ${max_attempts} attempts: $description"
            return 1
        fi

        delay="${delays[$((attempt - 1))]}"
        warn "Attempt ${attempt}/${max_attempts} failed: ${description}. Retrying in ${delay}s."
        sleep "$delay"
        attempt=$((attempt + 1))
    done
}

###############################################################################
# Sudo keepalive
###############################################################################

SUDO_KEEPALIVE_PID=""

stop_sudo_keepalive() {
    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
        kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        SUDO_KEEPALIVE_PID=""
    fi
}

require_sudo() {
    info "Validating sudo access."

    sudo -v ||
        die "sudo authentication failed."

    # Refresh the timestamp for the life of this installer. Do not
    # embed a password and do not weaken sudoers.
    (
        while true; do
            sleep 60
            sudo -n true || exit 1
        done
    ) >/dev/null 2>&1 &

    SUDO_KEEPALIVE_PID=$!
}

###############################################################################
# Atomic privileged file install
###############################################################################

install_root_file_from_stdin() {
    local destination="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"
    local temp_file

    temp_file="$(mktemp)"

    cat >"$temp_file"

    sudo install -D -m "$mode" -o "$owner" -g "$group" \
        "$temp_file" "$destination"

    rm -f "$temp_file"
}

install_root_file() {
    local source="$1"
    local destination="$2"
    local mode="$3"
    local owner="$4"
    local group="$5"

    [[ -f "$source" ]] ||
        die "Managed file is missing: $source"

    sudo install -D -m "$mode" -o "$owner" -g "$group" \
        "$source" "$destination"
}

###############################################################################
# Package helpers
###############################################################################

package_installed() {
    rpm -q "$1" >/dev/null 2>&1 || rpm -q --whatprovides "$1" >/dev/null 2>&1
}

# DNF5 repoquery can exit 0 with empty output for an unknown name.
package_available() {
    local package="$1"
    local output

    output="$(
        dnf -q repoquery --available --qf '%{name}' "$package" 2>/dev/null ||
            true
    )"

    if [[ -z "$output" ]]; then
        output="$(
            dnf -q repoquery --available --whatprovides "$package" --qf '%{name}' 2>/dev/null ||
                true
        )"
    fi

    [[ -n "$output" ]]
}

dnf_makecache() {
    sudo dnf makecache --refresh
}

dnf_install() {
    sudo dnf install -y "$@"
}

install_dnf_packages() {
    local packages=("$@")
    local missing=()
    local package

    for package in "${packages[@]}"; do
        if ! package_installed "$package"; then
            missing+=("$package")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        info "DNF packages already installed."
        return 0
    fi

    info "Installing ${#missing[@]} package(s): ${missing[*]}"

    run_with_retry "dnf install ${missing[*]}" dnf_install "${missing[@]}"
}

###############################################################################
# Directory helpers
###############################################################################

ensure_directory() {
    local directory="$1"

    if [[ ! -d "$directory" ]]; then
        mkdir -p "$directory"
    fi
}

###############################################################################
# Symlink helpers
###############################################################################

ensure_symlink() {
    local source="$1"
    local destination="$2"

    [[ -e "$source" || -L "$source" ]] ||
        die "Symlink source does not exist: $source"

    ensure_directory "$(dirname "$destination")"

    if [[ -L "$destination" ]]; then
        local current_target

        current_target="$(readlink "$destination")"

        if [[ "$current_target" == "$source" ]]; then
            return 0
        fi

        rm "$destination"

    elif [[ -e "$destination" ]]; then
        local backup

        backup="${destination}.bak.$(date +%Y%m%d-%H%M%S)"

        warn "Existing path found: $destination"
        warn "Moving it to: $backup"

        mv "$destination" "$backup"
    fi

    ln -s "$source" "$destination"
}

###############################################################################
# Pinned versions
###############################################################################

load_pinned_versions() {
    local versions_file="$SCRIPT_DIR/config/versions.conf"

    [[ -f "$versions_file" ]] ||
        die "Pinned versions file is missing: $versions_file"

    # shellcheck source=/dev/null
    source "$versions_file"
}

###############################################################################
# Pinned git clones (first install only)
###############################################################################

clone_pinned_git() {
    local url="$1"
    local destination="$2"
    local commit="$3"
    local label="$4"
    local temp_dir

    if [[ -d "$destination/.git" ]]; then
        info "$label already installed."
        return 0
    fi

    if [[ -e "$destination" ]]; then
        die "Existing non-Git path found at $destination"
    fi

    require_command git

    temp_dir="$(mktemp -d)"

    info "Cloning $label at $commit"

    mkdir -p "$temp_dir/src"
    git -C "$temp_dir/src" init -q
    git -C "$temp_dir/src" remote add origin "$url"

    if ! run_with_retry "git fetch $label" \
        git -C "$temp_dir/src" fetch --depth 1 origin "$commit"; then
        rm -rf "$temp_dir"
        return 1
    fi

    git -C "$temp_dir/src" checkout --detach FETCH_HEAD || {
        rm -rf "$temp_dir"
        return 1
    }

    ensure_directory "$(dirname "$destination")"
    mv "$temp_dir/src" "$destination"
    rm -rf "$temp_dir"
}

###############################################################################
# Profile validation
###############################################################################

validate_profile() {
    [[ -n "${PROFILE_NAME:-}" ]] ||
        die "PROFILE_NAME is not defined."

    [[ -n "${GPU:-}" ]] ||
        die "GPU is not defined."

    [[ -n "${DESKTOP:-}" ]] ||
        die "DESKTOP is not defined."

    [[ "${DESKTOP}" == "hyprland" ]] ||
        die "Unsupported desktop: ${DESKTOP}. Only hyprland is implemented."

    [[ -n "${DESKTOP_SHELL:-}" ]] ||
        die "DESKTOP_SHELL is not defined."

    [[ "${DESKTOP_SHELL}" == "noctalia" ]] ||
        die "Unsupported DESKTOP_SHELL: ${DESKTOP_SHELL}. Only noctalia is implemented (omarchy is reserved)."

    [[ -n "${SHELL:-}" ]] ||
        die "SHELL is not defined."

    [[ -n "${PROMPT:-}" ]] ||
        die "PROMPT is not defined."

    local boolean_variables=(
        OH_MY_ZSH
        BROWSER_CHROMIUM
        BROWSER_ULAA
        BROWSER_BRAVE_ORIGIN
        BROWSER_FIREFOX
        CURSOR
        BLUETOOTH
        GAMING
        FLATPAK
        NIX
        PODMAN
        NVIDIA
        ROCM
        ENABLE_GRAPHICAL_TARGET
        INSTALL_GREETER
        INSTALL_NOCTALIA
    )

    local variable

    for variable in "${boolean_variables[@]}"; do
        require_boolean "$variable"
    done
}

###############################################################################
# Fedora validation
###############################################################################

validate_fedora() {
    [[ -r /etc/os-release ]] ||
        die "/etc/os-release could not be read."

    # shellcheck source=/dev/null
    source /etc/os-release

    [[ "${ID:-}" == "fedora" ]] ||
        die "Unsupported distribution: ${ID:-unknown}. Fedora is required."

    [[ -n "${VERSION_ID:-}" ]] ||
        die "Could not determine Fedora version."

    [[ "${VERSION_ID}" == "44" ]] ||
        die "Unsupported Fedora version: ${VERSION_ID}. This installer targets Fedora 44."

    info "Detected Fedora ${VERSION_ID}."
}

###############################################################################
# User validation
###############################################################################

validate_target_user() {
    [[ -n "${TARGET_USER:-}" ]] ||
        die "TARGET_USER is not defined."

    [[ -n "${TARGET_HOME:-}" ]] ||
        die "TARGET_HOME is not defined."

    [[ "$TARGET_USER" != "root" ]] ||
        die "The workstation target user cannot be root."

    [[ -d "$TARGET_HOME" ]] ||
        die "Target home directory does not exist: $TARGET_HOME"

    [[ -w "$TARGET_HOME" ]] ||
        die "Target home directory is not writable: $TARGET_HOME"
}

###############################################################################
# System preparation
###############################################################################

prepare_system() {
    info "Running pre-flight validation."

    validate_profile
    validate_fedora
    validate_target_user

    require_command dnf
    require_command rpm
    require_command sudo
    require_command systemctl

    info "Refreshing Fedora package metadata."

    run_with_retry "dnf makecache --refresh" dnf_makecache ||
        die "Could not refresh DNF metadata."

    info "System preparation complete."
    record_success "prepare_system"
}
