#!/usr/bin/env bash

# Workstation application installation.
#
# Applications in this module are host-level desktop/development tools
# that do not belong to the base OS package manifests, browser module,
# or project-specific devenv/Nix environments.

cursor_repo_file="/etc/yum.repos.d/cursor.repo"

cursor_repo_configured() {
    [[ -f "$cursor_repo_file" && ! -L "$cursor_repo_file" ]] || return 1

    cmp -s "$cursor_repo_file" <(
        printf '%s\n' \
            '[cursor]' \
            'name=Cursor' \
            'baseurl=https://downloads.cursor.com/yumrepo' \
            'enabled=1' \
            'gpgcheck=1' \
            'gpgkey=https://downloads.cursor.com/keys/anysphere.asc'
    ) ||
        # Accept the explicitly stronger metadata-signature setting emitted
        # by some existing Cursor installations.
        cmp -s "$cursor_repo_file" <(
            printf '%s\n' \
                '[cursor]' \
                'name=Cursor' \
                'baseurl=https://downloads.cursor.com/yumrepo' \
                'enabled=1' \
                'gpgcheck=1' \
                'gpgkey=https://downloads.cursor.com/keys/anysphere.asc' \
                'repo_gpgcheck=1'
        )
}

configure_cursor_repository() {
    if cursor_repo_configured; then
        info "Cursor repository already configured."
        return 0
    fi

    info "Configuring official Cursor RPM repository."

    if ! install_root_file_from_stdin_preserving_existing "$cursor_repo_file" 0644 root root <<'EOF'
[cursor]
name=Cursor
baseurl=https://downloads.cursor.com/yumrepo
enabled=1
gpgcheck=1
gpgkey=https://downloads.cursor.com/keys/anysphere.asc
EOF
    then
        return 1
    fi

    if ! cursor_repo_configured; then
        return 1
    fi

    info "Cursor repository configured."
}

configure_cursor_flags() {
    local config_dir="$TARGET_HOME/.config"
    local flags_file="$config_dir/cursor-flags.conf"
    local temp_file

    safe_user_config_home "$config_dir" || return 1
    ensure_directory "$config_dir" || return 1

    temp_file="$(mktemp)" || return 1
    if ! cat >"$temp_file" <<'EOF'
--ozone-platform=wayland
--enable-features=UseOzonePlatform
EOF
    then
        rm -f -- "$temp_file"
        return 1
    fi

    if [[ -L "$flags_file" ]]; then
        rm -f -- "$temp_file"
        return 1
    fi

    if [[ -f "$flags_file" ]] && cmp -s "$temp_file" "$flags_file"; then
        rm -f -- "$temp_file"
        info "Cursor Wayland Ozone flags already converged."
        return 0
    fi

    local backup=""
    if [[ -e "$flags_file" ]]; then
        local backup_stamp
        backup_stamp="$(date +%Y%m%d-%H%M%S)" || {
            rm -f -- "$temp_file"
            return 1
        }
        backup="${flags_file}.bak.${backup_stamp}"
        local backup_counter=1
        while [[ -e "$backup" || -L "$backup" ]]; do
            backup="${flags_file}.bak.${backup_stamp}.${backup_counter}"
            backup_counter=$((backup_counter + 1))
        done

        if ! mv -T -- "$flags_file" "$backup"; then
            rm -f -- "$temp_file"
            return 1
        fi
        warn "Existing Cursor flags preserved at: $backup"
    fi

    if ! mv -T -- "$temp_file" "$flags_file"; then
        if [[ -n "$backup" && ! -e "$flags_file" && ! -L "$flags_file" ]]; then
            mv -T -- "$backup" "$flags_file" || true
        fi
        rm -f -- "$temp_file"
        return 1
    fi

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

    if ! configure_cursor_flags; then
        record_deferred \
            "applications" \
            "cursor-flags" \
            "Cursor Wayland flags could not be written."
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

install_chatgpt() {
    if ! is_true "${CHATGPT:-false}"; then
        info "ChatGPT disabled by profile."
        return 0
    fi

    if package_installed chatgpt; then
        info "ChatGPT already installed."
        record_success "chatgpt"
        return 0
    fi

    load_pinned_versions

    local arch
    arch="$(uname -m)"
    local bootstrap_url=""
    local expected_sha512=""
    local rpm_arch=""

    case "$arch" in
        x86_64|amd64)
            rpm_arch="x86_64"
            bootstrap_url="${CHATGPT_X86_64_URL:-}"
            expected_sha512="${CHATGPT_X86_64_SHA512:-}"
            ;;
        aarch64|arm64)
            rpm_arch="aarch64"
            bootstrap_url="${CHATGPT_AARCH64_URL:-}"
            expected_sha512="${CHATGPT_AARCH64_SHA512:-}"
            ;;
        *)
            record_deferred "applications" "chatgpt" "ChatGPT official RPM unsupported architecture: $arch."
            return 0
            ;;
    esac

    if [[ -z "$bootstrap_url" || -z "$expected_sha512" ]]; then
        record_deferred "applications" "chatgpt" "ChatGPT pinned version metadata missing for architecture: $rpm_arch."
        return 0
    fi

    info "Installing official OpenAI ChatGPT desktop application (${CHATGPT_VERSION:-pinned}, $rpm_arch)."

    local staging_dir
    if ! staging_dir="$(mktemp -d)"; then
        record_deferred "applications" "chatgpt" "Could not create a secure temporary staging directory."
        return 0
    fi
    local staging_rpm="$staging_dir/chatgpt.rpm"

    # 1. Download and verify cryptographic checksum before invoking package manager
    if ! download_and_verify_artifact "$bootstrap_url" "$expected_sha512" "$staging_rpm" "ChatGPT"; then
        rm -rf "$staging_dir"
        record_deferred "applications" "chatgpt" "Failed to download or verify official OpenAI ChatGPT RPM checksum."
        return 0
    fi

    # 2. Only after cryptographic checksum verification succeeds, invoke DNF to install the verified RPM
    # Installing the official RPM establishes OpenAI's signed package repository for future DNF upgrades
    if ! run_with_retry "install ChatGPT RPM" \
        run_dnf_command "$TIMEOUT_PACKAGE_SECONDS" "install ChatGPT RPM" \
        sudo dnf install -y "$staging_rpm"; then
        rm -rf "$staging_dir"
        record_deferred "applications" "chatgpt" "Failed to install verified OpenAI ChatGPT RPM package."
        return 0
    fi

    rm -rf "$staging_dir"

    # 3. Converge and import the official repository GPG key after fingerprint verification
    if ! converge_chatgpt_gpg_key; then
        record_required "repositories" "chatgpt-gpg" "Failed to converge official ChatGPT repository GPG key after bootstrap installation."
        return 1
    fi

    # 4. Validate package installation
    if ! package_installed chatgpt; then
        record_deferred "applications" "chatgpt" "ChatGPT was not detected after installation."
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
    if installer_test_override_allowed && [[ -n "${MEDIA_TOOLS_DIR:-}" ]]; then
        target_dir="$MEDIA_TOOLS_DIR"
    fi

    # 1. dovi_tool
    if [[ -n "${DOVI_TOOL_SHA512:-}" && -x "$target_dir/dovi_tool" ]] &&
        artifact_provenance_matches "dovi_tool" "$DOVI_TOOL_SHA512" "$target_dir/dovi_tool"; then
        info "dovi_tool already installed."
        record_success "dovi_tool"
    else
        if [[ -n "${DOVI_TOOL_URL:-}" && -n "${DOVI_TOOL_SHA512:-}" ]]; then
            info "Provisioning dovi_tool (${DOVI_TOOL_VERSION:-pinned})."
            if provision_verified_archive "$DOVI_TOOL_URL" "$DOVI_TOOL_SHA512" "$target_dir/dovi_tool" "dovi_tool" "dovi_tool" true dovi_tool; then
                record_success "dovi_tool"
            else
                record_deferred "applications" "dovi_tool" "Failed to download, verify, or extract dovi_tool."
            fi
        else
            record_deferred "applications" "dovi_tool" "Missing pinned URL or checksum for dovi_tool."
        fi
    fi

    # 2. N_m3u8DL-RE (evaluated via declarative release policy)
    local n_m3u8dl_version="${N_M3U8DL_RE_VERSION:-}"
    local n_m3u8dl_url="${N_M3U8DL_RE_URL:-}"
    local n_m3u8dl_sha512="${N_M3U8DL_RE_SHA512:-}"
    local eligibility_err=""
    if ! evaluate_release_eligibility "n_m3u8dl_re" "$n_m3u8dl_version" eligibility_err; then
        record_deferred \
            "applications" \
            "N_m3u8DL-RE" \
            "Skipping N_m3u8DL-RE: $eligibility_err"
    elif [[ -n "$n_m3u8dl_sha512" && -x "$target_dir/N_m3u8DL-RE" ]] &&
        artifact_provenance_matches "n_m3u8dl_re" "$n_m3u8dl_sha512" "$target_dir/N_m3u8DL-RE"; then
        info "N_m3u8DL-RE already installed."
        record_success "N_m3u8DL-RE"
    else
        if [[ -n "$n_m3u8dl_url" && -n "$n_m3u8dl_sha512" ]]; then
            info "Provisioning N_m3u8DL-RE (${n_m3u8dl_version})."
            if provision_verified_archive "$n_m3u8dl_url" "$n_m3u8dl_sha512" "$target_dir/N_m3u8DL-RE" "N_m3u8DL-RE" "N_m3u8DL-RE" true n_m3u8dl_re; then
                record_success "N_m3u8DL-RE"
            else
                record_deferred "applications" "N_m3u8DL-RE" "Failed to download, verify, or extract N_m3u8DL-RE."
            fi
        else
            record_deferred "applications" "N_m3u8DL-RE" "Missing pinned URL or checksum for N_m3u8DL-RE."
        fi
    fi


    # 3. Shaka Packager (packager)
    if [[ -n "${SHAKA_PACKAGER_SHA512:-}" && -x "$target_dir/packager" ]] &&
        artifact_provenance_matches "shaka_packager" "$SHAKA_PACKAGER_SHA512" "$target_dir/packager"; then
        info "Shaka Packager already installed."
        record_success "packager"
    else
        if [[ -n "${SHAKA_PACKAGER_URL:-}" && -n "${SHAKA_PACKAGER_SHA512:-}" ]]; then
            info "Provisioning Shaka Packager (${SHAKA_PACKAGER_VERSION:-pinned})."
            if provision_verified_binary "$SHAKA_PACKAGER_URL" "$SHAKA_PACKAGER_SHA512" "$target_dir/packager" "Shaka Packager" true shaka_packager; then
                record_success "packager"
            else
                record_deferred "applications" "packager" "Failed to download, verify, or install Shaka Packager."
            fi
        else
            record_deferred "applications" "packager" "Missing pinned URL or checksum for Shaka Packager."
        fi
    fi

    # 4. CCExtractor
    if [[ -n "${CCEXTRACTOR_SHA512:-}" && -x "$target_dir/ccextractor" ]] &&
        artifact_provenance_matches "ccextractor" "$CCEXTRACTOR_SHA512" "$target_dir/ccextractor"; then
        info "CCExtractor already installed."
        record_success "ccextractor"
    else
        if [[ -n "${CCEXTRACTOR_URL:-}" && -n "${CCEXTRACTOR_SHA512:-}" ]]; then
            info "Provisioning CCExtractor (${CCEXTRACTOR_VERSION:-pinned})."
            if provision_verified_archive "$CCEXTRACTOR_URL" "$CCEXTRACTOR_SHA512" "$target_dir/ccextractor" "ccextractor" "CCExtractor" true ccextractor; then
                record_success "ccextractor"
            else
                record_deferred "applications" "ccextractor" "Failed to download, verify, or extract CCExtractor."
            fi
        else
            record_deferred "applications" "ccextractor" "Missing pinned URL or checksum for CCExtractor."
        fi
    fi

    # 5. Bento4 (mp4dump, mp4info, etc.)
    local bento4_tools="bin/mp4dump bin/mp4info bin/mp4edit bin/mp4extract bin/mp4encrypt bin/mp4decrypt bin/mp4fragment bin/mp4split bin/mp4tag"
    local bento4_paths=(
        "$target_dir/mp4dump"
        "$target_dir/mp4info"
        "$target_dir/mp4edit"
        "$target_dir/mp4extract"
        "$target_dir/mp4encrypt"
        "$target_dir/mp4decrypt"
        "$target_dir/mp4fragment"
        "$target_dir/mp4split"
        "$target_dir/mp4tag"
    )
    if [[ -n "${BENTO4_SHA512:-}" && -x "$target_dir/mp4dump" ]] &&
        artifact_provenance_matches "bento4" "$BENTO4_SHA512" "${bento4_paths[@]}"; then
        info "Bento4 tools already installed."
        record_success "bento4"
    else
        if [[ -n "${BENTO4_URL:-}" && -n "${BENTO4_SHA512:-}" ]]; then
            info "Provisioning Bento4 tools (${BENTO4_VERSION:-pinned})."
            if provision_verified_archive "$BENTO4_URL" "$BENTO4_SHA512" "$target_dir" "$bento4_tools" "Bento4" true bento4; then
                record_success "bento4"
            else
                record_deferred "applications" "bento4" "Failed to download, verify, or extract Bento4."
            fi
        else
            record_deferred "applications" "bento4" "Missing pinned URL or checksum for Bento4."
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

    load_pinned_versions

    if [[ -n "${ANTIGRAVITY_SHA512:-}" && -x "$target_bin" ]] &&
        artifact_provenance_matches "antigravity" "$ANTIGRAVITY_SHA512" "$target_bin"; then
        info "Antigravity CLI (agy) already installed."
        record_success "antigravity"
        return 0
    fi

    [[ -n "${ANTIGRAVITY_URL:-}" ]] || {
        record_deferred "applications" "antigravity" "ANTIGRAVITY_URL is not defined in config/versions.conf."
        return 0
    }

    [[ -n "${ANTIGRAVITY_SHA512:-}" ]] || {
        record_deferred "applications" "antigravity" "ANTIGRAVITY_SHA512 is not defined in config/versions.conf."
        return 0
    }

    ensure_directory "$target_dir" || {
        record_deferred "applications" "antigravity" "The Antigravity target directory could not be prepared safely."
        return 0
    }

    info "Provisioning Antigravity CLI (${ANTIGRAVITY_VERSION:-pinned})."

    if provision_verified_archive "$ANTIGRAVITY_URL" "$ANTIGRAVITY_SHA512" "$target_bin" "agy" "Antigravity CLI" false antigravity; then
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
