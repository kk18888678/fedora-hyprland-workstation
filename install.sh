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

    if (( code != 0 )) && [[ ${#INSTALL_CRITICAL[@]} -eq 0 ]]; then
        record_critical \
            "installer" \
            "exit" \
            "Installer exited with status ${code}." \
            1
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
###############################################################################

run_step() {
    local description="$1"
    local function_name="$2"

    CURRENT_STAGE="$function_name"

    printf '\n'
    printf '==> %s\n' "$description"
    journal_stage "$function_name" "start"

    if ! declare -F "$function_name" >/dev/null; then
        die "Installer function not found: $function_name"
    fi

    "$function_name"
    journal_stage "$function_name" "done"
}

run_step "Preparing Fedora" prepare_system
run_step "Configuring repositories" configure_repositories
run_step "Installing host packages" install_packages
run_step "Configuring Zsh environment" configure_shell
run_step "Installing browsers" install_browsers
run_step "Installing workstation applications" install_applications
run_step "Configuring Flatpak" configure_flatpak
run_step "Installing Hyprland desktop" install_desktop
run_step "Installing Nix and devenv support" install_nix
run_step "Configuring containers" configure_containers
run_step "Validating workstation" validate_system
run_step "Activating graphical login" activate_graphical_session
