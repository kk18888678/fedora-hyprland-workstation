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
    require_command curl
    require_command tar
    require_command stat
    require_command flock

    info "System preparation complete."
    record_success "prepare_system"
}
