#!/usr/bin/env bash

# Workstation application installation.
#
# Applications in this module are host-level desktop/development tools
# that do not belong to the base OS package manifests, browser module,
# or project-specific devenv/Nix environments.

cursor_repo_file="/etc/yum.repos.d/cursor.repo"

cursor_repo_configured() {
    [[ -f "$cursor_repo_file" ]] &&
        grep -Fq 'baseurl=https://downloads.cursor.com/yumrepo' \
            "$cursor_repo_file"
}

configure_cursor_repository() {
    if cursor_repo_configured; then
        info "Cursor repository already configured."
        return 0
    fi

    info "Configuring official Cursor RPM repository."

    local temp_file
    temp_file="$(mktemp)"

    cat >"$temp_file" <<'EOF'
[cursor]
name=Cursor
baseurl=https://downloads.cursor.com/yumrepo
enabled=1
gpgcheck=1
gpgkey=https://downloads.cursor.com/keys/anysphere.asc
EOF

    sudo install \
        --owner=root \
        --group=root \
        --mode=0644 \
        "$temp_file" \
        "$cursor_repo_file"

    rm -f "$temp_file"

    if ! cursor_repo_configured; then
        return 1
    fi

    info "Cursor repository configured."
}

install_cursor() {
    if ! is_true "${CURSOR:-false}"; then
        info "Cursor disabled by profile."
        return 0
    fi

    if ! configure_cursor_repository; then
        record_deferred \
            "applications" \
            "cursor" \
            "Cursor RPM repository could not be configured."
        return 0
    fi

    if package_installed cursor; then
        info "Cursor already installed."
        record_success "cursor"
        return 0
    fi

    info "Installing Cursor."

    if ! install_dnf_packages cursor; then
        record_deferred \
            "applications" \
            "cursor" \
            "Cursor package could not be installed."
        return 0
    fi

    if ! package_installed cursor; then
        record_deferred \
            "applications" \
            "cursor" \
            "Cursor was not present after installation."
        return 0
    fi

    info "Cursor installation validated."
    record_success "cursor"
}

install_kate() {
    if ! is_true "${KATE:-false}"; then
        info "Kate editor disabled by profile."
        return 0
    fi

    if package_installed kate; then
        info "Kate already installed."
        record_success "kate"
        return 0
    fi

    info "Installing Kate graphical editor from Fedora official repositories."

    if ! install_dnf_packages kate; then
        record_deferred \
            "applications" \
            "kate" \
            "Kate package could not be installed."
        return 0
    fi

    if ! package_installed kate; then
        record_deferred \
            "applications" \
            "kate" \
            "Kate was not present after installation."
        return 0
    fi

    info "Kate installation validated."
    record_success "kate"
}

install_media_applications() {
    if ! is_true "${MEDIA_APPLICATIONS:-false}"; then
        info "Media applications disabled by profile."
        return 0
    fi

    local media_apps=(
        obs-studio
        mkvtoolnix-gui
        vlc
    )

    info "Installing graphical media applications."

    if ! install_dnf_packages "${media_apps[@]}"; then
        record_deferred \
            "applications" \
            "media-apps" \
            "One or more media applications could not be installed."
        return 0
    fi

    local app
    for app in "${media_apps[@]}"; do
        if package_installed "$app"; then
            record_success "$app"
        else
            record_deferred \
                "applications" \
                "$app" \
                "$app was not present after installation."
        fi
    done
}

install_localsend() {
    if ! is_true "${LOCALSEND:-false}"; then
        info "LocalSend disabled by profile."
        return 0
    fi

    if ! is_true "${FLATPAK:-false}"; then
        record_deferred \
            "applications" \
            "localsend" \
            "LocalSend requires Flatpak, but Flatpak is disabled by profile."
        return 0
    fi

    if ! command_exists flatpak; then
        record_deferred \
            "applications" \
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
            "applications" \
            "localsend" \
            "LocalSend Flatpak could not be installed."
        return 0
    fi

    info "LocalSend installation validated."
    record_success "localsend"
}

install_antigravity() {
    if ! is_true "${ANTIGRAVITY:-false}"; then
        info "Antigravity CLI disabled by profile."
        return 0
    fi

    ensure_directory "$TARGET_HOME/.local/bin"

    if [[ -x "$TARGET_HOME/.local/bin/agy" ]] || command_exists agy; then
        info "Antigravity CLI (agy) found."
        record_success "antigravity"
        return 0
    fi

    record_deferred \
        "applications" \
        "antigravity" \
        "Antigravity CLI (agy) executable not found in $TARGET_HOME/.local/bin/agy."
}

install_applications() {
    info "Installing workstation applications."

    install_cursor
    install_kate
    install_media_applications
    install_localsend
    install_antigravity

    info "Workstation application installation complete."
}
