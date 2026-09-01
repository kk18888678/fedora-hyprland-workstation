#!/usr/bin/env bash

# Flatpak configuration for Fedora Hyprland Workstation.
#
# Responsibilities:
#   - Respect FLATPAK=true/false from the active profile.
#   - Install Flatpak through Fedora if required.
#   - Configure Flathub idempotently.
#   - Do not install arbitrary GUI applications here.
#
# Application selection should remain explicit and separate.

install_flatpak_package() {
    if package_installed flatpak; then
        info "Flatpak already installed."
        return 0
    fi

    info "Installing Flatpak."

    install_dnf_packages flatpak || return 1

    if ! command_exists flatpak; then
        return 1
    fi

    info "Flatpak installation validated."
}

flathub_configured() {
    flatpak remote-list --system --columns=name 2>/dev/null |
        grep -Fxq "flathub"
}

configure_flathub() {
    if flathub_configured; then
        info "Flathub already configured."
        return 0
    fi

    info "Adding Flathub remote."

    run_with_retry "flatpak remote-add flathub" \
        sudo flatpak remote-add \
        --system \
        --if-not-exists \
        flathub \
        https://flathub.org/repo/flathub.flatpakrepo ||
        return 1

    if ! flathub_configured; then
        return 1
    fi

    info "Flathub configured."
}

configure_flatpak() {
    if ! is_true "${FLATPAK:-false}"; then
        info "Flatpak disabled by profile."
        return 0
    fi

    info "Configuring Flatpak."

    if ! install_flatpak_package; then
        record_critical "flatpak" "install" "Flatpak package could not be installed." 0
        return 0
    fi

    if ! configure_flathub; then
        record_critical "flatpak" "flathub" "Flathub remote could not be configured." 0
        return 0
    fi

    info "Flatpak configuration complete."
    record_success "flatpak"
}
