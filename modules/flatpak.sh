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
        record_required "flatpak" "install" "Flatpak package could not be installed."
        return 0
    fi

    if ! configure_flathub; then
        record_required "flatpak" "flathub" "Flathub remote could not be configured."
        return 0
    fi

    info "Flatpak configuration complete."
    record_success "flatpak"
}

install_localsend() {
    if ! is_true "${LOCALSEND:-false}"; then
        info "LocalSend disabled by profile."
        return 0
    fi

    if ! is_true "${FLATPAK:-false}"; then
        record_deferred \
            "flatpak" \
            "localsend" \
            "LocalSend requires Flatpak, but Flatpak is disabled by profile."
        return 0
    fi

    if ! command_exists flatpak; then
        record_deferred \
            "flatpak" \
            "localsend" \
            "Flatpak command is unavailable."
        return 0
    fi

    if flatpak list --app --columns=application 2>/dev/null | grep -Fxq "org.localsend.localsend_app"; then
        info "LocalSend Flatpak already installed."
        record_success "localsend"
        return 0
    fi

    info "Installing LocalSend from Flathub."

    if ! run_with_retry "flatpak install localsend" \
        flatpak install -y flathub org.localsend.localsend_app; then
        record_deferred \
            "flatpak" \
            "localsend" \
            "LocalSend Flatpak could not be installed."
        return 0
    fi

    info "LocalSend installation validated."
    record_success "localsend"
}

install_flatpak_applications() {
    if ! is_true "${FLATPAK:-false}"; then
        info "Flatpak applications disabled (FLATPAK=false)."
        return 0
    fi

    info "Installing Flatpak applications."

    install_localsend

    info "Flatpak application installation complete."
}
