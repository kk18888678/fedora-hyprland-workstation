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

    install_dnf_packages flatpak

    if ! command_exists flatpak; then
        die "Flatpak was installed but the flatpak command was not found."
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

    sudo flatpak remote-add \
        --system \
        --if-not-exists \
        flathub \
        https://flathub.org/repo/flathub.flatpakrepo

    if ! flathub_configured; then
        die "Flathub configuration could not be validated."
    fi

    info "Flathub configured."
}

validate_flatpak_configuration() {
    command_exists flatpak ||
        die "Flatpak command is unavailable."

    flathub_configured ||
        die "Flathub remote is not configured."

    info "Flatpak configuration validated."
}

configure_flatpak() {
    if ! is_true "${FLATPAK:-false}"; then
        info "Flatpak disabled by profile."
        return 0
    fi

    info "Configuring Flatpak."

    install_flatpak_package
    configure_flathub
    validate_flatpak_configuration

    info "Flatpak configuration complete."
}
