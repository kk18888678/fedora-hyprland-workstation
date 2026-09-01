#!/usr/bin/env bash

# Repository configuration for Fedora Hyprland Workstation.
#
# This module deliberately keeps third-party repositories to a minimum.
#
# Current policy:
#
#   Fedora official repositories
#       Primary source for packages.
#
#   lionheartp/Hyprland COPR
#       Required because Fedora 44 does not currently provide the Hyprland
#       compositor and related desktop packages we require.
#
#   atim/starship COPR
#       Officially documented Fedora package source for Starship.
#
#   RPM Fusion Free / Nonfree
#       Used for multimedia and hardware-related packages where Fedora's
#       repositories intentionally do not provide them.
#
# The following minimaLinux repositories are intentionally NOT enabled:
#
#   leloubil/wl-clip-persist
#   tofik/nwg-shell
#
# They may be reconsidered later if an actual workstation requirement
# cannot be satisfied through Fedora repositories.

###############################################################################
# COPR helpers
###############################################################################

copr_enabled() {
    local copr="$1"
    local repo_fragment

    repo_fragment="${copr/\//:}"

    grep -Rqs \
        "$repo_fragment" \
        /etc/yum.repos.d/_copr:* 2>/dev/null
}

enable_copr() {
    local copr="$1"

    if copr_enabled "$copr"; then
        info "COPR already enabled: $copr"
        return 0
    fi

    info "Enabling COPR: $copr"

    run_with_retry "dnf copr enable $copr" \
        sudo dnf copr enable -y "$copr"
}

###############################################################################
# RPM Fusion
###############################################################################

rpmfusion_free_installed() {
    package_installed rpmfusion-free-release
}

rpmfusion_nonfree_installed() {
    package_installed rpmfusion-nonfree-release
}

install_rpmfusion() {
    local fedora_version

    fedora_version="$(rpm -E '%fedora')"

    [[ "$fedora_version" =~ ^[0-9]+$ ]] ||
        die "Could not determine Fedora version for RPM Fusion."

    if ! rpmfusion_free_installed; then
        info "Installing RPM Fusion Free repository."

        run_with_retry "RPM Fusion Free" \
            sudo dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm" ||
            die "Failed to install RPM Fusion Free."
    else
        info "RPM Fusion Free repository already installed."
    fi

    if ! rpmfusion_nonfree_installed; then
        info "Installing RPM Fusion Nonfree repository."

        run_with_retry "RPM Fusion Nonfree" \
            sudo dnf install -y \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm" ||
            die "Failed to install RPM Fusion Nonfree."
    else
        info "RPM Fusion Nonfree repository already installed."
    fi
}

###############################################################################
# Repository validation
###############################################################################

validate_repository_configuration() {
    dnf repolist --enabled >/dev/null ||
        die "DNF repository validation failed."

    info "Repository configuration validated."
}

###############################################################################
# Main entry point
###############################################################################

configure_repositories() {
    info "Configuring Fedora package repositories."

    # `dnf copr` is provided by dnf-plugins-core.
    install_dnf_packages dnf-plugins-core ||
        die "dnf-plugins-core is required to enable COPR repositories."

    # Hyprland package source.
    enable_copr "lionheartp/Hyprland" ||
        die "Required COPR could not be enabled: lionheartp/Hyprland"

    # Starship package source.
    enable_copr "atim/starship" ||
        die "Required COPR could not be enabled: atim/starship"

    # Multimedia and hardware ecosystem.
    install_rpmfusion

    # Refresh metadata after repository changes.
    info "Refreshing repository metadata."

    run_with_retry "dnf makecache after repositories" dnf_makecache ||
        die "Could not refresh DNF metadata after enabling repositories."

    validate_repository_configuration

    info "Repository configuration complete."
    record_success "configure_repositories"
}
