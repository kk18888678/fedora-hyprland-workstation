#!/usr/bin/env bash

# Shared installer helpers aggregator.
#
# Sourced by install.sh and individual modules. Sourcing this file is
# strictly side-effect free and loads core shared libraries from modules/lib/.

_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/lib" && pwd -P)"

# shellcheck source=/dev/null
source "$_LIB_DIR/output.sh"
# shellcheck source=/dev/null
source "$_LIB_DIR/execution.sh"
# shellcheck source=/dev/null
source "$_LIB_DIR/filesystem.sh"
# shellcheck source=/dev/null
source "$_LIB_DIR/packages.sh"
# shellcheck source=/dev/null
source "$_LIB_DIR/artifacts.sh"
# shellcheck source=/dev/null
source "$_LIB_DIR/release_policy.sh"
# shellcheck source=/dev/null
source "$_LIB_DIR/components.sh"
# shellcheck source=/dev/null
source "$_LIB_DIR/desired_state.sh"
# shellcheck source=/dev/null
source "$_LIB_DIR/planner.sh"
# shellcheck source=/dev/null
source "$_LIB_DIR/reconciler.sh"
# shellcheck source=/dev/null
source "$_LIB_DIR/wizard.sh"

init_default_components

unset _LIB_DIR


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

    case "${DESKTOP_SHELL}" in
        noctalia|aurelia)
            ;;
        *)
            die "Unsupported DESKTOP_SHELL: ${DESKTOP_SHELL}. Supported shells are noctalia and aurelia."
            ;;
    esac

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
        CHATGPT
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

safe_user_config_home() {
    local config_home="$1"
    local current="/"
    local component
    local components=()
    local IFS='/'
    local ancestor
    local owner
    local expected_uid="${TARGET_UID:-$(id -u 2>/dev/null || true)}"

    [[ "$config_home" == /* && "$config_home" != "/" ]] || return 1
    read -r -a components <<< "${config_home#/}"
    for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue
        [[ "$component" != "." && "$component" != ".." ]] || return 1
        current="${current%/}/$component"
        [[ ! -L "$current" ]] || return 1
    done

    # For a not-yet-created config home, the nearest existing ancestor owns
    # the future mkdir operation.  This prevents an environment override from
    # directing the installer into an unrelated root-owned namespace.
    ancestor="$config_home"
    while [[ ! -e "$ancestor" ]]; do
        [[ "$ancestor" != "/" ]] || return 1
        ancestor="$(dirname -- "$ancestor")"
    done
    [[ -d "$ancestor" && ! -L "$ancestor" ]] || return 1

    owner="$(stat -c '%u' -- "$ancestor" 2>/dev/null || true)"
    [[ -n "$expected_uid" && "$owner" == "$expected_uid" ]]
}

# Return the project-owned selector consumed by the Hyprland Lua session
# startup module. The selector is deliberately outside ~/.config/hypr because
# that directory is a repository-owned symlink and must remain immutable at
# runtime.
desktop_shell_selector_path() {
    local config_home

    if [[ "${INSTALLER_PRODUCTION_MODE:-0}" == "1" ]]; then
        config_home="${XDG_CONFIG_HOME:-${TARGET_HOME:-$HOME}/.config}"
        safe_user_config_home "$config_home" || return 1
    else
        config_home="${XDG_CONFIG_HOME:-${TARGET_HOME:-$HOME}/.config}"
    fi

    [[ "$config_home" == /* && "$config_home" != "/" ]] ||
        return 1

    printf '%s/fedora-hyprland-workstation/session-shell\n' "$config_home"
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

    local host_arch
    host_arch="$(uname -m)"
    [[ "$host_arch" == "x86_64" || "$host_arch" == "amd64" ]] ||
        die "Unsupported host architecture: ${host_arch}. This installer targets x86_64."

    info "Detected Fedora ${VERSION_ID} (${host_arch})."
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

    local current_user
    local current_uid
    local passwd_home
    local home_owner

    current_user="$(id -un 2>/dev/null || true)"
    current_uid="$(id -u 2>/dev/null || true)"
    passwd_home="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || true)"

    [[ -n "$current_user" && "$TARGET_USER" == "$current_user" ]] ||
        die "Target user '$TARGET_USER' does not match the current login user '${current_user:-unknown}'."

    [[ -n "$current_uid" && "$current_uid" != "0" ]] ||
        die "Could not verify a non-root current user UID."

    [[ -n "$passwd_home" && "$TARGET_HOME" == "$passwd_home" ]] ||
        die "Target home '$TARGET_HOME' does not match the passwd home '$passwd_home'."

    [[ "$TARGET_HOME" == /* && "$TARGET_HOME" != "/" ]] ||
        die "Target home must be a non-root absolute path: $TARGET_HOME"

    [[ -d "$TARGET_HOME" ]] ||
        die "Target home directory does not exist: $TARGET_HOME"

    [[ -w "$TARGET_HOME" ]] ||
        die "Target home directory is not writable: $TARGET_HOME"

    home_owner="$(stat -c '%u' -- "$TARGET_HOME" 2>/dev/null || true)"
    [[ "$home_owner" == "$current_uid" ]] ||
        die "Target home '$TARGET_HOME' is owned by UID '${home_owner:-unknown}', expected '$current_uid'."
}

###############################################################################
# System preparation
###############################################################################

prepare_system() {
    info "Running pre-flight validation."

    validate_profile
    validate_fedora

    if ! validate_component_registry; then
        die "Component registry validation failed."
    fi

    require_command dnf
    require_command rpm
    require_command sudo
    require_command systemctl
    require_command stat
    require_command flock
    require_command id
    require_command getent

    # curl and tar are supplied by the reviewed base package group.  Requiring
    # them here would prevent a minimal Fedora Everything CLI install from
    # reaching the package plan that installs them.

    validate_target_user

    info "System preparation complete."
    record_success "prepare_system"
}
