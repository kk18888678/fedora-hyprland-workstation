#!/usr/bin/env bash

set -Eeuo pipefail

export LC_MESSAGES=C
export LANG=C

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROFILE=""

usage() {
    cat <<EOF
Fedora Hyprland Workstation Installer

Usage:
    ./install.sh --profile <profile>

Examples:
    ./install.sh --profile vm
    ./install.sh --profile workstation

Options:
    --profile <name>    Installation profile from profiles/<name>.conf
    -h, --help          Show this help
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            [[ $# -ge 2 ]] || die "--profile requires a value."
            PROFILE="$2"
            shift 2
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            die "Unknown option: $1"
            ;;
    esac
done

[[ -n "$PROFILE" ]] || die "A profile is required. Example: ./install.sh --profile vm"

case "$PROFILE" in
    vm|workstation)
        ;;
    *)
        die "Unsupported profile: $PROFILE. Choose vm or workstation."
        ;;
esac

# Keep the repository root and requested profile independent from values a
# profile file could assign while it is sourced below.
readonly INSTALLER_REPOSITORY_ROOT="$SCRIPT_DIR"
readonly INSTALLER_REQUESTED_PROFILE="$PROFILE"
PROFILE_FILE="$INSTALLER_REPOSITORY_ROOT/profiles/$INSTALLER_REQUESTED_PROFILE.conf"

[[ -f "$PROFILE_FILE" && ! -L "$PROFILE_FILE" ]] ||
    die "Profile is missing or is a symlink: $PROFILE_FILE"

# This installer must be launched as the normal desktop user.
#
# Individual privileged operations are performed through sudo.
# Running the entire installer as root would cause user-owned files,
# dotfiles and application configuration to be installed into the
# wrong home directory.
if [[ $EUID -eq 0 ]]; then
    die "Do not run this installer as root. Run it as your normal user."
fi

# Fedora only.
[[ -f /etc/fedora-release ]] ||
    die "This installer is intended for Fedora Linux."

command -v dnf >/dev/null 2>&1 ||
    die "dnf was not found."

command -v sudo >/dev/null 2>&1 ||
    die "sudo was not found."

command -v timeout >/dev/null 2>&1 ||
    die "timeout (GNU coreutils) was not found."

command -v id >/dev/null 2>&1 ||
    die "id was not found."

command -v getent >/dev/null 2>&1 ||
    die "getent was not found."

# shellcheck source=/dev/null
source "$PROFILE_FILE"

# A profile is configuration data, not authority to change the process target
# or repository location. Restore the CLI-selected values after sourcing it.
SCRIPT_DIR="$INSTALLER_REPOSITORY_ROOT"
PROFILE="$INSTALLER_REQUESTED_PROFILE"
PROFILE_FILE="$INSTALLER_REPOSITORY_ROOT/profiles/$PROFILE.conf"
TARGET_USER="$(id -un)" || die "Could not determine the current user."
TARGET_UID="$(id -u)" || die "Could not determine the current user UID."
TARGET_GID="$(id -g)" || die "Could not determine the current user primary group ID."
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

[[ -n "$TARGET_HOME" ]] || die "Could not determine the home directory for $TARGET_USER."
[[ "$TARGET_UID" =~ ^[0-9]+$ && "$TARGET_GID" =~ ^[0-9]+$ ]] ||
    die "Could not determine numeric identity for $TARGET_USER."

# The public installer entry point is always production mode. Test fixtures
# source modules directly and may opt into mock input without affecting this
# process. This marker is intentionally set after profile loading so a profile
# file cannot enable test behavior for a real installation.
readonly INSTALLER_PRODUCTION_MODE=1

export SCRIPT_DIR
export PROFILE
export PROFILE_FILE
export TARGET_USER
export TARGET_UID
export TARGET_GID
export TARGET_HOME

printf '\n'
printf 'Fedora Hyprland Workstation\n'
printf '===========================\n'
printf 'Profile : %s\n' "$PROFILE_NAME"
printf 'User    : %s\n' "$TARGET_USER"
printf 'Home    : %s\n' "$TARGET_HOME"
printf 'GPU     : %s\n' "$GPU"
printf '\n'

###############################################################################
# Modules
###############################################################################

MODULES=(
    common
    status
    state
    repositories
    packages
    shell
    browsers
    applications
    flatpak
    desktop
    nix
    containers
    validation
)

for module in "${MODULES[@]}"; do
    module_file="$SCRIPT_DIR/modules/$module.sh"

    [[ -f "$module_file" && ! -L "$module_file" ]] ||
        die "Required module is missing or is a symlink: $module_file"

    # shellcheck source=/dev/null
    source "$module_file"
done

# Setup mode and plan review are intentionally interactive.  Reject a
# redirected production launch before acquiring locks, prompting for sudo, or
# creating installer state.
if ! wizard_is_interactive; then
    printf 'ERROR: Interactive terminal required for setup mode selection. Run in an interactive terminal.\n' >&2
    exit 1
fi

###############################################################################
# Lifecycle
###############################################################################

INTERRUPTED_SIGNAL=0

cleanup_installer_children() {
    stop_sudo_keepalive

    if [[ -n "${ACTIVE_TIMEOUT_PID:-}" ]]; then
        kill -TERM "$ACTIVE_TIMEOUT_PID" 2>/dev/null || true
        wait "$ACTIVE_TIMEOUT_PID" 2>/dev/null || true
        ACTIVE_TIMEOUT_PID=""
    fi
}

on_interrupt() {
    local sig="${1:-INT}"
    error "Installer interrupted ($sig)."
    error "Rerunning the same command is safe and will reconcile state."
    cleanup_installer_children
    ACTIVATION_BLOCKED=1
    record_critical "installer" "interrupt" "Received signal $sig." 1

    case "$sig" in
        TERM) INTERRUPTED_SIGNAL=143 ;;
        HUP)  INTERRUPTED_SIGNAL=129 ;;
        QUIT) INTERRUPTED_SIGNAL=131 ;;
        *)    INTERRUPTED_SIGNAL=130 ;;
    esac
    exit "$INTERRUPTED_SIGNAL"
}

on_exit() {
    local code=$?

    cleanup_installer_children

    local final_code=0
    resolve_installer_exit_code "$code" "$INTERRUPTED_SIGNAL" final_code

    if [[ ${SUMMARY_PRINTED:-0} -eq 0 ]]; then
        print_installer_summary
    fi

    finalize_installer_state "$final_code"
    stop_installer_logging || true
    # Keep the exclusive lock until summary and final state writes complete.
    release_installer_lock
    exit "$final_code"
}

trap 'on_interrupt INT' INT
trap 'on_interrupt TERM' TERM
trap 'on_interrupt HUP' HUP
trap 'on_interrupt QUIT' QUIT
trap on_exit EXIT

acquire_installer_lock
require_sudo
init_installer_state

# Capture setup selection and plan review as well as mutation stages. The
# logging helper drains tee before the EXIT trap releases installer state.
start_installer_logging || die "Could not start installer logging."

# Setup mode selection, configuration planning, and user review
INSTALLER_PLAN="MAIN_INSTALLER_PLAN"
setup_rc=0
run_setup_mode "$PROFILE" "$INSTALLER_PLAN" || setup_rc=$?

if [[ "$setup_rc" -eq 2 ]]; then
    # User cancelled setup in wizard or review
    INSTALLER_CANCELLED=1
    exit 2
elif [[ "$setup_rc" -ne 0 ]]; then
    die "Setup mode initialization failed."
fi

###############################################################################
# Installation
#
# abort        : preconditions; a failure stops the installer
# login        : unsafe login stack must not activate greetd
# workstation  : required profile features; cannot skip safe activation
# optional     : deferred; exit code 2
###############################################################################

run_classified_step abort "Preparing Fedora" prepare_system
run_classified_step workstation "Configuring repositories" configure_repositories
run_classified_step workstation "Installing host packages" install_packages
run_classified_step optional "Installing tracked user Fedora packages" install_user_managed_dnf_packages
run_classified_step optional "Restoring tracked Aurelia binaries" install_user_managed_aurelia_packages
run_classified_step workstation "Reconciling configured components" execute_plan "$INSTALLER_PLAN"
run_classified_step workstation "Configuring Zsh environment" configure_shell
run_classified_step workstation "Installing browsers" install_browsers
run_classified_step optional "Installing workstation applications" install_applications
run_classified_step workstation "Configuring Flatpak" configure_flatpak
run_classified_step optional "Installing Flatpak applications" install_flatpak_applications
run_classified_step login "Installing Hyprland desktop" install_desktop
run_classified_step workstation "Installing Aurelia network DNS authorization" install_aurelia_network_dns_authorization
run_classified_step workstation "Installing Nix and devenv support" install_nix
run_classified_step workstation "Configuring containers" configure_containers
run_classified_step login "Validating graphical login stack" validate_login_stack
run_classified_step login "Activating graphical login" activate_graphical_session
run_classified_step workstation "Validating workstation capabilities" validate_workstation_environment
