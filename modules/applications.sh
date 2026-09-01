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

install_antigravity() {
    if ! is_true "${ANTIGRAVITY:-false}"; then
        info "Antigravity CLI disabled by profile."
        return 0
    fi

    local target_bin="$TARGET_HOME/.local/bin/agy"

    if [[ -x "$target_bin" ]] || command_exists agy; then
        info "Antigravity CLI (agy) already installed."
        record_success "antigravity"
        return 0
    fi

    load_pinned_versions

    [[ -n "${ANTIGRAVITY_URL:-}" ]] || {
        record_deferred "applications" "antigravity" "ANTIGRAVITY_URL is not defined in config/versions.conf."
        return 0
    }

    [[ -n "${ANTIGRAVITY_SHA512:-}" ]] || {
        record_deferred "applications" "antigravity" "ANTIGRAVITY_SHA512 is not defined in config/versions.conf."
        return 0
    }

    ensure_directory "$TARGET_HOME/.local/bin"

    info "Provisioning Antigravity CLI (${ANTIGRAVITY_VERSION:-pinned})."

    local staging_dir
    staging_dir="$(mktemp -d)"

    local staging_tarball="$staging_dir/agy.tar.gz"

    if ! run_with_retry "download Antigravity CLI" \
        curl -fsSL -o "$staging_tarball" "$ANTIGRAVITY_URL"; then
        rm -rf "$staging_dir"
        record_deferred "applications" "antigravity" "Failed to download Antigravity CLI package."
        return 0
    fi

    local actual_sha512
    actual_sha512="$(sha512sum "$staging_tarball" | cut -d' ' -f1 || true)"

    if [[ "$actual_sha512" != "$ANTIGRAVITY_SHA512" ]]; then
        rm -rf "$staging_dir"
        record_deferred "applications" "antigravity" "Antigravity CLI checksum mismatch: expected $ANTIGRAVITY_SHA512, got ${actual_sha512:-none}."
        return 0
    fi

    info "Antigravity CLI package checksum verified."

    if ! tar -xzf "$staging_tarball" -C "$staging_dir"; then
        rm -rf "$staging_dir"
        record_deferred "applications" "antigravity" "Failed to extract Antigravity CLI archive."
        return 0
    fi

    local extracted_binary=""
    if [[ -f "$staging_dir/antigravity" ]]; then
        extracted_binary="$staging_dir/antigravity"
    elif [[ -f "$staging_dir/agy" ]]; then
        extracted_binary="$staging_dir/agy"
    fi

    if [[ -z "$extracted_binary" || ! -f "$extracted_binary" ]]; then
        rm -rf "$staging_dir"
        record_deferred "applications" "antigravity" "Could not find executable binary in extracted Antigravity archive."
        return 0
    fi

    install -m 0755 "$extracted_binary" "$target_bin"
    rm -rf "$staging_dir"

    if [[ ! -x "$target_bin" ]]; then
        record_deferred "applications" "antigravity" "Antigravity CLI binary was not executable after installation."
        return 0
    fi

    info "Antigravity CLI (${ANTIGRAVITY_VERSION:-pinned}) provisioned successfully."
    record_success "antigravity"
}

install_applications() {
    info "Installing workstation applications."

    install_cursor
    install_kate
    install_media_applications
    install_antigravity

    info "Workstation application installation complete."
}
