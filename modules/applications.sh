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

configure_cursor_flags() {
    local config_dir="$TARGET_HOME/.config"
    local flags_file="$config_dir/cursor-flags.conf"
    local temp_file

    ensure_directory "$config_dir"

    temp_file="$(mktemp)"
    cat >"$temp_file" <<'EOF'
--ozone-platform=wayland
--enable-features=UseOzonePlatform
EOF

    mv "$temp_file" "$flags_file"
    info "Cursor Wayland Ozone flags configured."
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

    configure_cursor_flags

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

chatgpt_repo_file="/etc/yum.repos.d/chatgpt.repo"

chatgpt_repo_configured() {
    [[ -f "$chatgpt_repo_file" ]] &&
        grep -Fq 'baseurl=https://persistent.oaistatic.com/codex-app-prod/linux/rpm' \
            "$chatgpt_repo_file"
}

configure_chatgpt_repository() {
    if chatgpt_repo_configured; then
        info "ChatGPT repository already configured."
        return 0
    fi

    info "Configuring official ChatGPT RPM repository."

    local temp_file
    temp_file="$(mktemp)"

    cat >"$temp_file" <<'EOF'
[chatgpt]
name=ChatGPT
baseurl=https://persistent.oaistatic.com/codex-app-prod/linux/rpm/$basearch
enabled=1
gpgcheck=1
gpgkey=https://persistent.oaistatic.com/codex-app-prod/linux/rpm/RPM-GPG-KEY-chatgpt
EOF

    sudo install \
        --owner=root \
        --group=root \
        --mode=0644 \
        "$temp_file" \
        "$chatgpt_repo_file"

    rm -f "$temp_file"

    if ! chatgpt_repo_configured; then
        return 1
    fi

    info "ChatGPT repository configured."
}

install_chatgpt() {
    if ! is_true "${CHATGPT:-false}"; then
        info "ChatGPT disabled by profile."
        return 0
    fi

    if ! configure_chatgpt_repository; then
        record_deferred \
            "applications" \
            "chatgpt" \
            "ChatGPT RPM repository could not be configured."
        return 0
    fi

    if package_installed chatgpt; then
        info "ChatGPT already installed."
        record_success "chatgpt"
        return 0
    fi

    info "Installing ChatGPT desktop application."

    if ! install_dnf_packages chatgpt; then
        record_deferred \
            "applications" \
            "chatgpt" \
            "ChatGPT package could not be installed."
        return 0
    fi

    if ! package_installed chatgpt; then
        record_deferred \
            "applications" \
            "chatgpt" \
            "ChatGPT was not present after installation."
        return 0
    fi

    info "ChatGPT installation validated."
    record_success "chatgpt"
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

install_media_utilities() {
    local arch
    arch="$(uname -m)"
    if [[ "$arch" != "x86_64" && "$arch" != "amd64" ]]; then
        record_deferred "applications" "media-utilities" "Media utilities pinned packages are x86_64; unsupported architecture: $arch."
        return 0
    fi

    load_pinned_versions

    local target_dir="/usr/local/bin"

    # 1. dovi_tool
    if [[ -x "$target_dir/dovi_tool" ]] || command_exists dovi_tool; then
        info "dovi_tool already installed."
        record_success "dovi_tool"
    else
        if [[ -n "${DOVI_TOOL_URL:-}" && -n "${DOVI_TOOL_SHA512:-}" ]]; then
            info "Provisioning dovi_tool (${DOVI_TOOL_VERSION:-pinned})."
            if provision_verified_archive "$DOVI_TOOL_URL" "$DOVI_TOOL_SHA512" "$target_dir/dovi_tool" "dovi_tool" "dovi_tool" true; then
                record_success "dovi_tool"
            else
                record_deferred "applications" "dovi_tool" "Failed to download, verify, or extract dovi_tool."
            fi
        fi
    fi

    # 2. N_m3u8DL-RE
    if [[ -x "$target_dir/N_m3u8DL-RE" ]] || command_exists N_m3u8DL-RE; then
        info "N_m3u8DL-RE already installed."
        record_success "N_m3u8DL-RE"
    else
        if [[ -n "${N_M3U8DL_RE_URL:-}" && -n "${N_M3U8DL_RE_SHA512:-}" ]]; then
            info "Provisioning N_m3u8DL-RE (${N_M3U8DL_RE_VERSION:-pinned})."
            if provision_verified_archive "$N_M3U8DL_RE_URL" "$N_M3U8DL_RE_SHA512" "$target_dir/N_m3u8DL-RE" "N_m3u8DL-RE" "N_m3u8DL-RE" true; then
                record_success "N_m3u8DL-RE"
            else
                record_deferred "applications" "N_m3u8DL-RE" "Failed to download, verify, or extract N_m3u8DL-RE."
            fi
        fi
    fi

    # 3. Shaka Packager (packager)
    if [[ -x "$target_dir/packager" ]] || command_exists packager; then
        info "Shaka Packager already installed."
        record_success "packager"
    else
        if [[ -n "${SHAKA_PACKAGER_URL:-}" && -n "${SHAKA_PACKAGER_SHA512:-}" ]]; then
            info "Provisioning Shaka Packager (${SHAKA_PACKAGER_VERSION:-pinned})."
            if provision_verified_binary "$SHAKA_PACKAGER_URL" "$SHAKA_PACKAGER_SHA512" "$target_dir/packager" "Shaka Packager" true; then
                record_success "packager"
            else
                record_deferred "applications" "packager" "Failed to download, verify, or install Shaka Packager."
            fi
        fi
    fi

    # 4. CCExtractor
    if [[ -x "$target_dir/ccextractor" ]] || command_exists ccextractor; then
        info "CCExtractor already installed."
        record_success "ccextractor"
    else
        if [[ -n "${CCEXTRACTOR_URL:-}" && -n "${CCEXTRACTOR_SHA512:-}" ]]; then
            info "Provisioning CCExtractor (${CCEXTRACTOR_VERSION:-pinned})."
            if provision_verified_archive "$CCEXTRACTOR_URL" "$CCEXTRACTOR_SHA512" "$target_dir/ccextractor" "ccextractor" "CCExtractor" true; then
                record_success "ccextractor"
            else
                record_deferred "applications" "ccextractor" "Failed to download, verify, or extract CCExtractor."
            fi
        fi
    fi

    # 5. Bento4 (mp4dump, mp4info, etc.)
    if [[ -x "$target_dir/mp4dump" ]] || command_exists mp4dump; then
        info "Bento4 tools already installed."
        record_success "bento4"
    else
        if [[ -n "${BENTO4_URL:-}" && -n "${BENTO4_SHA512:-}" ]]; then
            info "Provisioning Bento4 tools (${BENTO4_VERSION:-pinned})."
            if provision_verified_archive "$BENTO4_URL" "$BENTO4_SHA512" "$target_dir" "mp4dump" "Bento4" true; then
                record_success "bento4"
            else
                record_deferred "applications" "bento4" "Failed to download, verify, or extract Bento4."
            fi
        fi
    fi
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

    local arch
    arch="$(uname -m)"
    if [[ "$arch" != "x86_64" && "$arch" != "amd64" ]]; then
        record_deferred "applications" "antigravity" "Antigravity CLI pinned package is x86_64; unsupported architecture: $arch."
        return 0
    fi

    local target_dir="$TARGET_HOME/.local/bin"
    local target_bin="$target_dir/agy"

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

    ensure_directory "$target_dir"

    info "Provisioning Antigravity CLI (${ANTIGRAVITY_VERSION:-pinned})."

    if provision_verified_archive "$ANTIGRAVITY_URL" "$ANTIGRAVITY_SHA512" "$target_bin" "agy" "Antigravity CLI" false; then
        record_success "antigravity"
    else
        record_deferred "applications" "antigravity" "Failed to download, verify, or provision Antigravity CLI."
    fi
}

install_applications() {
    info "Installing workstation applications."

    install_cursor
    install_kate
    install_chatgpt
    install_media_applications
    install_media_utilities
    install_antigravity

    info "Workstation application installation complete."
}
