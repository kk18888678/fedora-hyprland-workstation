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

run_as_target_user() {
    local target_user="${TARGET_USER:-}"
    local target_home="${TARGET_HOME:-}"
    local effective_uid="${OVERRIDE_EUID:-$EUID}"

    [[ -n "$target_user" ]] || die "TARGET_USER is not defined."
    [[ -n "$target_home" ]] || die "TARGET_HOME is not defined."

    local target_uid=""
    if [[ -n "${OVERRIDE_TARGET_UID:-}" ]]; then
        target_uid="$OVERRIDE_TARGET_UID"
    elif command_exists id; then
        target_uid="$(id -u "$target_user" 2>/dev/null || true)"
    elif command_exists getent; then
        target_uid="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f3 || true)"
    fi

    # 1. If caller is already actually running as TARGET_USER (effective UID matches target UID)
    if [[ -n "$target_uid" ]] && (( effective_uid == target_uid )); then
        HOME="$target_home" USER="$target_user" "$@"
        return $?
    fi

    # If target_uid is unknown but effective user is not root and genuine login identity matches
    if [[ -z "$target_uid" && "$effective_uid" -ne 0 ]]; then
        local current_login=""
        if command_exists id; then
            current_login="$(id -un 2>/dev/null || true)"
        fi
        if [[ -n "$current_login" && "$current_login" == "$target_user" ]]; then
            HOME="$target_home" USER="$target_user" "$@"
            return $?
        fi
    fi

    # 2. If caller is root, perform genuine user switch via sudo
    if (( effective_uid == 0 )); then
        sudo -u "$target_user" env HOME="$target_home" USER="$target_user" "$@"
        return $?
    fi

    # 3. If caller is a different non-root user, perform privilege switch if sudo is available
    if command_exists sudo; then
        sudo -u "$target_user" env HOME="$target_home" USER="$target_user" "$@"
        return $?
    fi

    # 4. Fail closed: genuine user transition required but impossible
    error "Cannot execute command as target user '$target_user': process UID ($effective_uid) does not match target UID (${target_uid:-unknown}) and sudo is unavailable."
    return 1
}

###############################################################################
# Timeout & Bounded Execution
###############################################################################

TIMEOUT_METADATA_SECONDS=300       # 5 minutes: dnf makecache, repoquery, repo add
TIMEOUT_PACKAGE_SECONDS=900        # 15 minutes: dnf install transaction, copr enable
TIMEOUT_DOWNLOAD_SECONDS=300       # 5 minutes: direct curl/wget downloads
TIMEOUT_GIT_SECONDS=300            # 5 minutes: git clone / fetch
TIMEOUT_FLATPAK_SECONDS=600        # 10 minutes: Flatpak remote-add and package installs
TIMEOUT_NIX_SECONDS=600            # 10 minutes: Nix profile install and package evaluation

ACTIVE_TIMEOUT_PID=""

run_with_timeout() {
    local timeout_seconds="$1"
    local description="$2"
    shift 2

    if ! command_exists timeout; then
        error "Required safety utility 'timeout' is not available for: ${description}"
        return 127
    fi

    if (( timeout_seconds <= 0 )); then
        error "Invalid non-positive timeout (${timeout_seconds}s) for: ${description}"
        return 1
    fi

    local status=0
    timeout --kill-after=10s "${timeout_seconds}s" "$@" &
    ACTIVE_TIMEOUT_PID=$!
    wait "$ACTIVE_TIMEOUT_PID" || status=$?
    ACTIVE_TIMEOUT_PID=""

    if (( status == 124 || status == 137 )); then
        error "Operation timed out after ${timeout_seconds}s: ${description}"
        return 124
    fi

    return "$status"
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
    local status=0

    while true; do
        if "$@"; then
            return 0
        else
            status=$?
        fi

        if (( attempt >= max_attempts )); then
            error "Giving up after ${max_attempts} attempts: $description"
            return "$status"
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

# Returns 0 if package is found available in repositories.
# Returns 1 if repoquery succeeds cleanly but package does not exist.
# Returns 2 if repoquery times out or encounters a repository/metadata error.
package_available() {
    local package="$1"
    local output=""
    local status=0

    output="$(
        run_with_timeout "$TIMEOUT_METADATA_SECONDS" "repoquery $package" \
            dnf -q repoquery --available --qf '%{name}' "$package" 2>/dev/null
    )" || status=$?

    if (( status == 124 )); then
        error "Package availability query timed out for '$package'."
        return 2
    elif (( status != 0 )); then
        error "Package availability query failed for '$package' (status $status)."
        return 2
    fi

    if [[ -n "$output" ]]; then
        return 0
    fi

    output="$(
        run_with_timeout "$TIMEOUT_METADATA_SECONDS" "repoquery whatprovides $package" \
            dnf -q repoquery --available --whatprovides "$package" --qf '%{name}' 2>/dev/null
    )" || status=$?

    if (( status == 124 )); then
        error "Package provides query timed out for '$package'."
        return 2
    elif (( status != 0 )); then
        error "Package provides query failed for '$package' (status $status)."
        return 2
    fi

    if [[ -n "$output" ]]; then
        return 0
    fi

    return 1
}

dnf_makecache() {
    run_with_timeout "$TIMEOUT_METADATA_SECONDS" "dnf makecache" \
        sudo dnf makecache --refresh
}

dnf_install() {
    run_with_timeout "$TIMEOUT_PACKAGE_SECONDS" "dnf install $*" \
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
        run_with_timeout "$TIMEOUT_GIT_SECONDS" "git fetch $label" \
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
        KATE
        MEDIA_APPLICATIONS
        ANTIGRAVITY
        LOCALSEND
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
