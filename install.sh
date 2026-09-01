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

PROFILE_FILE="$SCRIPT_DIR/profiles/$PROFILE.conf"

[[ -f "$PROFILE_FILE" ]] || die "Profile not found: $PROFILE_FILE"

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

TARGET_USER="$USER"
TARGET_HOME="$HOME"

export SCRIPT_DIR
export PROFILE
export PROFILE_FILE
export TARGET_USER
export TARGET_HOME

# shellcheck source=/dev/null
source "$PROFILE_FILE"

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

    [[ -f "$module_file" ]] ||
        die "Required module is missing: $module_file"

    # shellcheck source=/dev/null
    source "$module_file"
done

###############################################################################
# Lifecycle
###############################################################################

on_interrupt() {
    error "Installer interrupted."
    error "Rerunning the same command is safe and will reconcile state."
    ACTIVATION_BLOCKED=1
    record_critical "installer" "interrupt" "Received SIGINT/SIGTERM." 1
    exit 1
}

on_exit() {
    local code=$?

    stop_sudo_keepalive

    if (( code != 0 )) &&
        [[ ${#INSTALL_LOGIN_FAILURES[@]} -eq 0 ]] &&
        [[ ${#INSTALL_REQUIRED_FAILURES[@]} -eq 0 ]]; then
        record_activation_failure \
            "installer" \
            "exit" \
            "Installer exited with status ${code}."
    fi

    if [[ ${SUMMARY_PRINTED:-0} -eq 0 ]]; then
        print_installer_summary
    fi

    finalize_installer_state "$(installer_exit_code)"
    exit "$(installer_exit_code)"
}

trap on_interrupt INT TERM
trap on_exit EXIT

require_sudo
init_installer_state

exec > >(tee -a "$INSTALL_LOG_FILE") 2>&1

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
run_classified_step workstation "Configuring Zsh environment" configure_shell
run_classified_step workstation "Installing browsers" install_browsers
run_classified_step optional "Installing workstation applications" install_applications
run_classified_step workstation "Configuring Flatpak" configure_flatpak
run_classified_step optional "Installing Flatpak applications" install_flatpak_applications
run_classified_step login "Installing Hyprland desktop" install_desktop
run_classified_step workstation "Installing Nix and devenv support" install_nix
run_classified_step workstation "Configuring containers" configure_containers
run_classified_step login "Validating graphical login stack" validate_login_stack
run_classified_step login "Activating graphical login" activate_graphical_session
run_classified_step workstation "Validating workstation capabilities" validate_workstation_environment
