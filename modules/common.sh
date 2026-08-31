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
# Package helpers
###############################################################################

package_installed() {
    rpm -q "$1" >/dev/null 2>&1
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

    sudo dnf install -y "${missing[@]}"
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
# Profile validation
###############################################################################

validate_profile() {
    [[ -n "${PROFILE_NAME:-}" ]] ||
        die "PROFILE_NAME is not defined."

    [[ -n "${GPU:-}" ]] ||
        die "GPU is not defined."

    [[ -n "${DESKTOP:-}" ]] ||
        die "DESKTOP is not defined."

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

    sudo dnf makecache --refresh

    info "System preparation complete."
}
