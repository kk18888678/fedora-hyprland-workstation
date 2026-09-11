#!/usr/bin/env bash

# Hyprland desktop configuration for Fedora Hyprland Workstation.
#
# Graphical login activation (greetd enable + graphical.target) is a
# separate final phase. This module prepares and validates the desktop
# without switching a live SSH session onto a greeter.

deploy_hyprland_config() {
    local source="$SCRIPT_DIR/dotfiles/hypr"
    local destination="$TARGET_HOME/.config/hypr"

    [[ -d "$source" && ! -L "$source" ]] ||
        die "Hyprland configuration is missing or is a symlink: $source"

    ensure_symlink "$source" "$destination"

    info "Hyprland configuration linked."
}

deploy_noctalia_config() {
    local source="$SCRIPT_DIR/config/noctalia"
    local destination="$TARGET_HOME/.config/noctalia"

    if [[ -L "$source" ]]; then
        die "Noctalia configuration directory is a symlink: $source"
    fi

    if [[ -d "$source" ]]; then
        ensure_directory "$destination" || return 1
        for file in "$source"/*.toml; do
            [[ -e "$file" || -L "$file" ]] || continue
            [[ -f "$file" && ! -L "$file" ]] ||
                die "Noctalia configuration file is missing or is a symlink: $file"
            local target="$destination/$(basename "$file")"
            ensure_symlink "$file" "$target"
        done
        info "Noctalia configuration deployed."
    fi
}

validate_desktop_shell_selection() {
    case "${DESKTOP_SHELL:-}" in
        noctalia)
            if ! is_true "${INSTALL_NOCTALIA:-false}"; then
                die "DESKTOP_SHELL=noctalia requires INSTALL_NOCTALIA=true."
            fi
            ;;
        aurelia)
            if is_true "${INSTALL_GREETER:-false}" &&
                ! is_true "${INSTALL_NOCTALIA:-false}"; then
                die "DESKTOP_SHELL=aurelia with INSTALL_GREETER=true requires INSTALL_NOCTALIA=true for the Noctalia greeter."
            fi
            ;;
        omarchy)
            die "The omarchy desktop shell is not implemented yet."
            ;;
        *)
            die "Unsupported DESKTOP_SHELL: ${DESKTOP_SHELL:-<unset>}"
            ;;
    esac
}

# Compatibility name retained for older callers. The function now validates
# the selected post-login shell; Noctalia greeter installation is separate.
install_noctalia_shell() {
    validate_desktop_shell_selection
}

deploy_session_shell_selection() {
    local selected_shell="${DESKTOP_SHELL:-}"
    local source="$SCRIPT_DIR/config/session-shell/$selected_shell"
    local destination

    destination="$(desktop_shell_selector_path 2>/dev/null || true)"
    if [[ -z "$destination" ]]; then
        record_required \
            "desktop" \
            "session-shell-selector" \
            "Could not determine a safe XDG configuration path for the selected desktop shell."
        return 0
    fi

    if [[ ! -f "$source" || -L "$source" ]]; then
        record_required \
            "desktop" \
            "session-shell-selector" \
            "Managed session-shell selector is missing: $source"
        return 0
    fi

    ensure_symlink "$source" "$destination"
    info "Post-login desktop shell selected: $selected_shell."
}

resolve_packaged_executable() {
    local package="$1"
    local command_name="$2"
    local package_path
    local matches=()

    package_installed "$package" || return 1

    while IFS= read -r package_path || [[ -n "$package_path" ]]; do
        if [[ "$package_path" == /* && "${package_path##*/}" == "$command_name" &&
              -x "$package_path" && ! -L "$package_path" ]]; then
            matches+=("$package_path")
        fi
    done < <(rpm -ql "$package" 2>/dev/null)

    [[ "${#matches[@]}" -eq 1 ]] || return 1
    printf '%s\n' "${matches[0]}"
}

install_noctalia_greeter() {
    if ! is_true "${INSTALL_GREETER:-false}"; then
        info "Graphical greeter disabled by profile."
        return 0
    fi

    info "Validating Noctalia greeter."

    # The desktop package group is the production mutation owner for the
    # greeter RPM.  This activation-stage function only validates that the
    # reconciler supplied it; keeping a fallback for a non-migrated caller
    # preserves compatibility with older isolated module consumers without
    # creating a second production owner.
    if is_component_migrated "packages.desktop"; then
        if ! resolve_packaged_executable noctalia-greeter noctalia-greeter-session >/dev/null; then
            record_activation_failure \
                "desktop" \
                "noctalia-greeter" \
                "The desktop package group did not provide a unique RPM-owned noctalia-greeter-session executable."
            return 1
        fi
    elif ! install_dnf_packages noctalia-greeter; then
        record_activation_failure \
            "desktop" \
            "noctalia-greeter" \
            "noctalia-greeter package could not be installed."
        return 1
    fi

    if ! resolve_packaged_executable noctalia-greeter noctalia-greeter-session >/dev/null; then
        record_activation_failure \
            "desktop" \
            "noctalia-greeter-session" \
            "RPM-owned noctalia-greeter-session was not found after installation."
        return 1
    fi

    info "Noctalia greeter validated."
}

validate_greetd_user() {
    if ! getent passwd greetd >/dev/null 2>&1; then
        record_activation_failure \
            "desktop" \
            "greetd-user" \
            "Fedora greetd service user was not found."
        return 1
    fi

    if ! getent group greetd >/dev/null 2>&1; then
        record_activation_failure \
            "desktop" \
            "greetd-group" \
            "Fedora greetd service group was not found."
        return 1
    fi

    info "greetd service account validated."
}

is_virtio_or_vm_gpu() {
    # Explicit GPU configuration overrides heuristics
    if [[ "${GPU:-}" == "virtio" ]]; then
        return 0
    elif [[ -n "${GPU:-}" && "${GPU:-}" != "generic" && "${GPU:-}" != "auto" ]]; then
        return 1
    fi

    # Only virtual machine environments require virtio-gpu cursor/scaling workarounds
    if ! command_exists systemd-detect-virt || ! systemd-detect-virt --vm &>/dev/null; then
        return 1
    fi

    # Inspect active DRM subsystem devices specifically for virtio-gpu driver
    if [[ -d /sys/bus/virtio/drivers/virtio_gpu ]]; then
        local virtio_devs
        virtio_devs=$(find /sys/bus/virtio/drivers/virtio_gpu -maxdepth 1 -name "virtio*" 2>/dev/null || true)
        if [[ -n "$virtio_devs" ]]; then
            return 0
        fi
    fi

    # Inspect PCI display controller vendor/device (1af4:1050 / 1af4:1010 for virtio-gpu)
    local drm_uevent
    for drm_uevent in /sys/class/drm/card*/device/uevent; do
        if [[ -f "$drm_uevent" ]]; then
            if grep -qi 'PCI_ID=1AF4:1050\|PCI_ID=1AF4:1010' "$drm_uevent" 2>/dev/null; then
                return 0
            fi
        fi
    done

    # Fallback to lspci if available
    if command_exists lspci; then
        local lspci_1050=""
        local lspci_1010=""
        lspci_1050="$(lspci -d 1af4:1050 2>/dev/null || true)"
        lspci_1010="$(lspci -d 1af4:1010 2>/dev/null || true)"
        if [[ -n "$lspci_1050" || -n "$lspci_1010" ]]; then
            return 0
        fi
    fi

    return 1
}

configure_greetd() {
    if ! is_true "${INSTALL_GREETER:-false}"; then
        return 0
    fi

    local greeter_session
    local greetd_config="/etc/greetd/config.toml"

    if ! greeter_session="$(resolve_packaged_executable noctalia-greeter noctalia-greeter-session)"; then
        record_activation_failure \
            "desktop" \
            "greetd-command" \
            "Could not resolve the RPM-owned noctalia-greeter-session executable."
        return 1
    fi

    [[ -n "$greeter_session" ]] || {
        record_activation_failure \
            "desktop" \
            "greetd-command" \
            "Could not determine noctalia-greeter-session path."
        return 1
    }

    if ! validate_greetd_user; then
        return 1
    fi

    if declare -F validate_mutation_path >/dev/null 2>&1 &&
        ! validate_mutation_path /etc/greetd; then
        record_activation_failure \
            "desktop" \
            "greetd-directory" \
            "Refusing to configure greetd through an unsafe symlinked path."
        return 1
    fi

    info "Configuring greetd."

    if ! sudo install -d -m 0755 /etc/greetd; then
        record_activation_failure \
            "desktop" \
            "greetd-directory" \
            "Could not create /etc/greetd."
        return 1
    fi

    local session_cmd="$greeter_session"
    if is_virtio_or_vm_gpu; then
        session_cmd="env WLR_NO_HARDWARE_CURSORS=1 $greeter_session"
    fi

    if ! install_root_file_from_stdin_preserving_existing "$greetd_config" 0644 root root <<EOF
[terminal]
vt = 1

[default_session]
command = "$session_cmd"
user = "greetd"
EOF
    then
        record_activation_failure \
            "desktop" \
            "greetd-config" \
            "Could not install /etc/greetd/config.toml."
        return 1
    fi

    info "greetd configured."
}

configure_noctalia_greeter_state() {
    if ! is_true "${INSTALL_GREETER:-false}"; then
        return 0
    fi

    local dest="/var/lib/noctalia-greeter"
    local greeter_toml="$dest/greeter.toml"
    local managed="$SCRIPT_DIR/config/noctalia-greeter/greeter.toml"

    info "Configuring Noctalia greeter state directory."

    if declare -F validate_mutation_path >/dev/null 2>&1 &&
        ! validate_mutation_path "$dest"; then
        record_activation_failure \
            "desktop" \
            "greeter-state-directory" \
            "Refusing to configure Noctalia greeter state through an unsafe symlinked path."
        return 1
    fi

    if ! sudo install \
        -d \
        -m 0750 \
        -o greetd \
        -g greetd \
        "$dest"; then
        record_activation_failure \
            "desktop" \
            "greeter-state-directory" \
            "Could not create $dest."
        return 1
    fi

    [[ -f "$managed" && ! -L "$managed" ]] ||
        die "Managed greeter config is missing or is a symlink: $managed"

    # Login-screen cursor only. Do not change the user Hyprland cursor.
    local content
    content="$(cat "$managed")"
    if is_virtio_or_vm_gpu; then
        # On virtualized GPUs (e.g. virtio-gpu), Noctalia greeter auto-scaling
        # computes fractional scale (1.04) from virtual EDID dimensions, which triggers
        # DRM atomic commit ERANGE failure. Explicit scale = 1.0 ensures clean rendering.
        if ! grep -q '^\[output\]' <<< "$content"; then
            content="${content}
[output]
scale = 1.0
"
        fi
    fi
    if ! install_root_file_from_stdin_preserving_existing "$greeter_toml" 0644 greetd greetd <<< "$content"; then
        record_activation_failure \
            "desktop" \
            "greeter-state" \
            "Could not install $greeter_toml."
        return 1
    fi

    info "Noctalia greeter state directory configured."
}

enable_desktop_services() {
    local unit_files=""
    local failed=0

    info "Enabling desktop services."

    if unit_files="$(systemctl list-unit-files NetworkManager.service --no-legend 2>/dev/null)" &&
        grep -q '^NetworkManager.service' <<< "$unit_files"; then
        if ! sudo systemctl enable NetworkManager.service; then
            record_required \
                "desktop" \
                "networkmanager" \
                "NetworkManager.service could not be enabled."
            failed=1
        fi
    fi

    if unit_files="$(systemctl list-unit-files power-profiles-daemon.service --no-legend 2>/dev/null)" &&
        grep -q '^power-profiles-daemon.service' <<< "$unit_files"; then
        if ! sudo systemctl enable power-profiles-daemon.service; then
            record_required \
                "desktop" \
                "power-profiles-daemon" \
                "power-profiles-daemon.service could not be enabled."
            failed=1
        fi
    fi

    if is_true "${BLUETOOTH:-false}"; then
        if unit_files="$(systemctl list-unit-files bluetooth.service --no-legend 2>/dev/null)" &&
            grep -q '^bluetooth.service' <<< "$unit_files"; then
            if ! sudo systemctl enable bluetooth.service; then
                record_required \
                    "desktop" \
                    "bluetooth" \
                    "bluetooth.service could not be enabled."
                failed=1
            fi
        else
            record_required \
                "desktop" \
                "bluetooth" \
                "Bluetooth is enabled by the profile but bluetooth.service was not found."
            failed=1
        fi
    fi

    info "Desktop services configured."
    return "$failed"
}

# Install the root-owned helper and the narrowly scoped sudoers policy used by
# the Aurelia Network widget. This mirrors Omarchy's deployment model: the
# graphical widget never receives root privileges, and only the three stock
# providers are allowed to run without an authentication prompt. Custom DNS
# remains an interactive operation.
install_aurelia_network_dns_authorization() {
    if [[ "${DESKTOP_SHELL:-}" != "aurelia" ]]; then
        info "Aurelia Network DNS authorization is not needed for the selected desktop shell; skipping."
        return 0
    fi

    local helper_source="$SCRIPT_DIR/aurelia-shell/bin/aurelia-network-dns"
    local terminal_source="$SCRIPT_DIR/aurelia-shell/bin/aurelia-network-dns-terminal"
    local sudoers_source="$SCRIPT_DIR/config/sudoers.d/aurelia-network-dns"
    local helper_target="/usr/local/bin/aurelia-network-dns"
    local terminal_target="/usr/local/bin/aurelia-network-dns-terminal"
    local sudoers_target="/etc/sudoers.d/aurelia-network-dns"
    local visudo_bin

    if [[ ! -f "$helper_source" || -L "$helper_source" || ! -x "$helper_source" ]]; then
        record_required \
            "desktop" \
            "aurelia-network-dns-authorization" \
            "Managed DNS helper is missing or not executable: $helper_source"
        return 0
    fi

    if [[ ! -f "$terminal_source" || -L "$terminal_source" || ! -x "$terminal_source" ]]; then
        record_required \
            "desktop" \
            "aurelia-network-dns-authorization" \
            "Managed DNS terminal fallback is missing or not executable: $terminal_source"
        return 0
    fi

    if [[ ! -f "$sudoers_source" || -L "$sudoers_source" ]]; then
        record_required \
            "desktop" \
            "aurelia-network-dns-authorization" \
            "Managed DNS sudoers policy is missing: $sudoers_source"
        return 0
    fi

    visudo_bin="$(command -v visudo 2>/dev/null || true)"
    if [[ -z "$visudo_bin" ]]; then
        record_required \
            "desktop" \
            "aurelia-network-dns-authorization" \
            "visudo is required to validate the managed DNS sudoers policy."
        return 0
    fi

    if ! "$visudo_bin" -cf "$sudoers_source" >/dev/null 2>&1; then
        record_required \
            "desktop" \
            "aurelia-network-dns-authorization" \
            "Managed DNS sudoers policy failed visudo validation."
        return 0
    fi

    if declare -F validate_mutation_path >/dev/null 2>&1 &&
        { ! validate_mutation_path /usr/local/bin ||
          ! validate_mutation_path /etc/sudoers.d; }; then
        record_required \
            "desktop" \
            "aurelia-network-dns-authorization" \
            "A managed DNS authorization directory contains an unsafe symlinked path component."
        return 0
    fi

    if ! sudo install -d -m 0755 /usr/local/bin ||
        ! sudo install -d -m 0750 /etc/sudoers.d ||
        ! install_root_file_atomically \
            "$helper_source" "$helper_target" 0755 root root ||
        ! install_root_file_atomically \
            "$terminal_source" "$terminal_target" 0755 root root ||
        ! install_root_file_atomically \
            "$sudoers_source" "$sudoers_target" 0440 root root; then
        record_required \
            "desktop" \
            "aurelia-network-dns-authorization" \
            "Could not install the root-owned DNS helpers or sudoers policy."
        return 0
    fi

    if ! sudo "$visudo_bin" -cf "$sudoers_target" >/dev/null 2>&1; then
        record_required \
            "desktop" \
            "aurelia-network-dns-authorization" \
            "Installed DNS sudoers policy failed final visudo validation."
        return 0
    fi

    info "Aurelia Network DNS authorization installed."
    record_success "aurelia-network-dns-authorization"
}

enable_greetd() {
    if ! is_true "${INSTALL_GREETER:-false}"; then
        return 0
    fi

    info "Enabling greetd for the next boot (not replacing the current session)."

    if ! sudo systemctl enable greetd.service; then
        return 1
    fi

    info "greetd enabled."
}

configure_graphical_target() {
    if ! is_true "${ENABLE_GRAPHICAL_TARGET:-false}"; then
        info "Graphical target unchanged by profile."
        return 0
    fi

    info "Setting graphical.target as the default system target."

    if ! sudo systemctl set-default graphical.target; then
        return 1
    fi

    info "graphical.target configured."
}

install_hack_nerd_font() {
    load_pinned_versions

    local fonts_dir="/usr/local/share/fonts/HackNerdFont"
    if installer_test_override_allowed && [[ -n "${FONTS_INSTALL_DIR:-}" ]]; then
        fonts_dir="$FONTS_INSTALL_DIR"
    fi
    if declare -F validate_mutation_path >/dev/null 2>&1 &&
        ! validate_mutation_path "$fonts_dir"; then
        record_deferred "desktop" "hack-nerd-font" "Hack Nerd Font destination path is unsafe."
        return 0
    fi
    if [[ -d "$fonts_dir" && ! -L "$fonts_dir" &&
          -f "$fonts_dir/HackNerdFont-Regular.ttf" &&
          ! -L "$fonts_dir/HackNerdFont-Regular.ttf" ]]; then
        info "Hack Nerd Font already installed."
        record_success "hack-nerd-font"
        return 0
    fi

    if [[ -z "${HACK_NERD_FONT_URL:-}" || -z "${HACK_NERD_FONT_SHA512:-}" ]]; then
        record_deferred "desktop" "hack-nerd-font" "Hack Nerd Font version metadata missing."
        return 0
    fi

    info "Installing Hack Nerd Font (${HACK_NERD_FONT_VERSION:-pinned})."

    local staging_dir
    if ! staging_dir="$(mktemp -d)"; then
        record_deferred "desktop" "hack-nerd-font" "Could not create a secure temporary staging directory."
        return 0
    fi
    local staging_archive="$staging_dir/hack.tar.xz"

    if ! download_and_verify_artifact "$HACK_NERD_FONT_URL" "$HACK_NERD_FONT_SHA512" "$staging_archive" "Hack Nerd Font"; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "hack-nerd-font" "Failed to download or verify Hack Nerd Font archive."
        return 0
    fi

    local extracted_dir="$staging_dir/extracted"
    if ! mkdir -p -- "$extracted_dir"; then
        rm -rf -- "$staging_dir"
        record_deferred "desktop" "hack-nerd-font" "Could not create the temporary extraction directory."
        return 0
    fi

    # Pre-extraction structural validation
    local verbose_listing
    if ! verbose_listing="$(tar --warning=no-unknown-keyword -tvf "$staging_archive" 2>/dev/null)"; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "hack-nerd-font" "Hack Nerd Font archive inspection failed."
        return 0
    fi

    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        local type_char="${line:0:1}"
        case "$type_char" in
            -|d) ;;
            *)
                rm -rf "$staging_dir"
                record_deferred "desktop" "hack-nerd-font" "Hack Nerd Font archive contains unsupported entry type '$type_char'."
                return 0
                ;;
        esac
    done <<< "$verbose_listing"

    local members_listing
    if ! members_listing="$(tar -tf "$staging_archive" 2>/dev/null)"; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "hack-nerd-font" "Hack Nerd Font archive member listing failed."
        return 0
    fi

    local member
    while IFS= read -r member; do
        [[ -n "$member" ]] || continue
        if ! validate_path_components "$member" || ! normalize_archive_path "" "$member" >/dev/null; then
            rm -rf "$staging_dir"
            record_deferred "desktop" "hack-nerd-font" "Hack Nerd Font archive contains forbidden member path: $member"
            return 0
        fi
    done <<< "$members_listing"

    if ! tar -xf "$staging_archive" -C "$extracted_dir"; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "hack-nerd-font" "Failed to extract Hack Nerd Font archive."
        return 0
    fi

    if [[ ! -f "$extracted_dir/HackNerdFont-Regular.ttf" ||
          -L "$extracted_dir/HackNerdFont-Regular.ttf" ]]; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "hack-nerd-font" "Hack Nerd Font archive is missing the expected HackNerdFont-Regular.ttf member."
        return 0
    fi

    local font_install_failed=0
    if [[ "$fonts_dir" == /usr/* || "$fonts_dir" == /etc/* ]]; then
        if ! sudo mkdir -p "$fonts_dir"; then
            font_install_failed=1
        elif ! sudo cp -r "$extracted_dir"/* "$fonts_dir/"; then
            font_install_failed=1
        elif ! sudo chmod 0755 "$fonts_dir"; then
            font_install_failed=1
        else
            sudo chmod 0644 "$fonts_dir"/* 2>/dev/null || true
        fi
    else
        if ! mkdir -p "$fonts_dir"; then
            font_install_failed=1
        elif ! cp -r "$extracted_dir"/* "$fonts_dir/"; then
            font_install_failed=1
        elif ! chmod 0755 "$fonts_dir"; then
            font_install_failed=1
        else
            chmod 0644 "$fonts_dir"/* 2>/dev/null || true
        fi
    fi

    if (( font_install_failed != 0 )) ||
        [[ ! -f "$fonts_dir/HackNerdFont-Regular.ttf" || -L "$fonts_dir/HackNerdFont-Regular.ttf" ]]; then
        rm -rf -- "$staging_dir"
        record_deferred "desktop" "hack-nerd-font" "Failed to install Hack Nerd Font files."
        return 0
    fi

    rm -rf "$staging_dir"

    if command_exists fc-cache; then
        fc-cache -f >/dev/null 2>&1 || true
    fi

    info "Hack Nerd Font installed successfully."
    record_success "hack-nerd-font"
}

install_jetbrains_mono_nerd_font() {
    load_pinned_versions

    local fonts_dir="/usr/local/share/fonts/JetBrainsMonoNerdFont"
    if installer_test_override_allowed && [[ -n "${JETBRAINS_FONTS_INSTALL_DIR:-}" ]]; then
        fonts_dir="$JETBRAINS_FONTS_INSTALL_DIR"
    fi
    if declare -F validate_mutation_path >/dev/null 2>&1 &&
        ! validate_mutation_path "$fonts_dir"; then
        record_deferred "desktop" "jetbrains-mono-nerd-font" "JetBrainsMono Nerd Font destination path is unsafe."
        return 0
    fi
    if [[ -d "$fonts_dir" && ! -L "$fonts_dir" &&
          -f "$fonts_dir/JetBrainsMonoNerdFont-Regular.ttf" &&
          ! -L "$fonts_dir/JetBrainsMonoNerdFont-Regular.ttf" ]]; then
        info "JetBrainsMono Nerd Font already installed."
        record_success "jetbrains-mono-nerd-font"
        return 0
    fi

    if [[ -z "${JETBRAINS_MONO_NERD_FONT_URL:-}" || -z "${JETBRAINS_MONO_NERD_FONT_SHA512:-}" ]]; then
        record_deferred "desktop" "jetbrains-mono-nerd-font" "JetBrainsMono Nerd Font version metadata missing."
        return 0
    fi

    info "Installing JetBrainsMono Nerd Font (${JETBRAINS_MONO_NERD_FONT_VERSION:-pinned})."

    local staging_dir
    if ! staging_dir="$(mktemp -d)"; then
        record_deferred "desktop" "jetbrains-mono-nerd-font" "Could not create a secure temporary staging directory."
        return 0
    fi
    local staging_archive="$staging_dir/jetbrains-mono.tar.xz"

    if ! download_and_verify_artifact "$JETBRAINS_MONO_NERD_FONT_URL" "$JETBRAINS_MONO_NERD_FONT_SHA512" "$staging_archive" "JetBrainsMono Nerd Font"; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "jetbrains-mono-nerd-font" "Failed to download or verify JetBrainsMono Nerd Font archive."
        return 0
    fi

    local extracted_dir="$staging_dir/extracted"
    if ! mkdir -p -- "$extracted_dir"; then
        rm -rf -- "$staging_dir"
        record_deferred "desktop" "jetbrains-mono-nerd-font" "Could not create the temporary extraction directory."
        return 0
    fi

    # Pre-extraction structural validation
    local verbose_listing
    if ! verbose_listing="$(tar --warning=no-unknown-keyword -tvf "$staging_archive" 2>/dev/null)"; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "jetbrains-mono-nerd-font" "JetBrainsMono Nerd Font archive inspection failed."
        return 0
    fi

    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        local type_char="${line:0:1}"
        case "$type_char" in
            -|d) ;;
            *)
                rm -rf "$staging_dir"
                record_deferred "desktop" "jetbrains-mono-nerd-font" "JetBrainsMono Nerd Font archive contains unsupported entry type '$type_char'."
                return 0
                ;;
        esac
    done <<< "$verbose_listing"

    local members_listing
    if ! members_listing="$(tar -tf "$staging_archive" 2>/dev/null)"; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "jetbrains-mono-nerd-font" "JetBrainsMono Nerd Font archive member listing failed."
        return 0
    fi

    local member
    while IFS= read -r member; do
        [[ -n "$member" ]] || continue
        if ! validate_path_components "$member" || ! normalize_archive_path "" "$member" >/dev/null; then
            rm -rf "$staging_dir"
            record_deferred "desktop" "jetbrains-mono-nerd-font" "JetBrainsMono Nerd Font archive contains forbidden member path: $member"
            return 0
        fi
    done <<< "$members_listing"

    if ! tar -xf "$staging_archive" -C "$extracted_dir"; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "jetbrains-mono-nerd-font" "Failed to extract JetBrainsMono Nerd Font archive."
        return 0
    fi

    if [[ ! -f "$extracted_dir/JetBrainsMonoNerdFont-Regular.ttf" ||
          -L "$extracted_dir/JetBrainsMonoNerdFont-Regular.ttf" ]]; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "jetbrains-mono-nerd-font" "JetBrainsMono Nerd Font archive is missing the expected JetBrainsMonoNerdFont-Regular.ttf member."
        return 0
    fi

    local font_install_failed=0
    if [[ "$fonts_dir" == /usr/* || "$fonts_dir" == /etc/* ]]; then
        if ! sudo mkdir -p "$fonts_dir"; then
            font_install_failed=1
        elif ! sudo cp -r "$extracted_dir"/* "$fonts_dir/"; then
            font_install_failed=1
        elif ! sudo chmod 0755 "$fonts_dir"; then
            font_install_failed=1
        else
            sudo chmod 0644 "$fonts_dir"/* 2>/dev/null || true
        fi
    else
        if ! mkdir -p "$fonts_dir"; then
            font_install_failed=1
        elif ! cp -r "$extracted_dir"/* "$fonts_dir/"; then
            font_install_failed=1
        elif ! chmod 0755 "$fonts_dir"; then
            font_install_failed=1
        else
            chmod 0644 "$fonts_dir"/* 2>/dev/null || true
        fi
    fi

    if (( font_install_failed != 0 )) ||
        [[ ! -f "$fonts_dir/JetBrainsMonoNerdFont-Regular.ttf" || -L "$fonts_dir/JetBrainsMonoNerdFont-Regular.ttf" ]]; then
        rm -rf -- "$staging_dir"
        record_deferred "desktop" "jetbrains-mono-nerd-font" "Failed to install JetBrainsMono Nerd Font files."
        return 0
    fi

    rm -rf "$staging_dir"

    if command_exists fc-cache; then
        fc-cache -f >/dev/null 2>&1 || true
    fi

    info "JetBrainsMono Nerd Font installed successfully."
    record_success "jetbrains-mono-nerd-font"
}

install_rose_pine_gtk_theme() {
    load_pinned_versions

    local theme_dest="$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk"
    local themes_dir="$TARGET_HOME/.local/share/themes"
    if ! safe_user_config_home "$themes_dir"; then
        record_deferred "desktop" "rose-pine-gtk" "Rosé Pine GTK destination directory is unsafe or symlinked."
        return 0
    fi
    if [[ -d "$theme_dest" && -f "$theme_dest/index.theme" && -f "$theme_dest/gtk-3.0/gtk.css" ]]; then
        info "Rosé Pine Moon GTK theme already installed."
        record_success "rose-pine-gtk"
        return 0
    fi

    if [[ -z "${ROSE_PINE_GTK_URL:-}" || -z "${ROSE_PINE_GTK_SHA512:-}" ]]; then
        record_deferred "desktop" "rose-pine-gtk" "Rosé Pine GTK theme version metadata missing."
        return 0
    fi

    info "Installing Rosé Pine Moon GTK theme (${ROSE_PINE_GTK_VERSION:-pinned})."

    local staging_dir
    if ! staging_dir="$(mktemp -d)"; then
        record_deferred "desktop" "rose-pine-gtk" "Could not create a secure temporary staging directory."
        return 0
    fi
    local staging_archive="$staging_dir/theme.tar.gz"

    if ! download_and_verify_artifact "$ROSE_PINE_GTK_URL" "$ROSE_PINE_GTK_SHA512" "$staging_archive" "Rosé Pine GTK theme"; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "rose-pine-gtk" "Failed to download or verify Rosé Pine GTK theme archive."
        return 0
    fi

    # Pre-extraction safety validation: enumerate archive members and inspect entry types
    local verbose_listing
    if ! verbose_listing="$(tar --warning=no-unknown-keyword -tvf "$staging_archive" 2>/dev/null)"; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "rose-pine-gtk" "Rosé Pine GTK theme archive inspection failed."
        return 0
    fi

    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        local type_char="${line:0:1}"
        case "$type_char" in
            -|d)
                ;;
            l)
                # Parse symlink path and target: '... path -> target'
                if [[ "$line" =~ [[:space:]]([^[:space:]]+)[[:space:]]-\>[[:space:]]([^[:space:]]+) ]]; then
                    local sym_path="${BASH_REMATCH[1]}"
                    local sym_target="${BASH_REMATCH[2]}"

                    # Reject absolute paths or targets
                    if [[ "$sym_path" == /* || "$sym_target" == /* ]]; then
                        rm -rf "$staging_dir"
                        record_deferred "desktop" "rose-pine-gtk" "Rosé Pine GTK archive contains absolute symlink target: $sym_path -> $sym_target"
                        return 0
                    fi

                    # Reject link targets attempting traversal outside archive root
                    local sym_dir
                    sym_dir="$(dirname "$sym_path")"
                    local target_combined
                    if [[ "$sym_dir" == "." ]]; then
                        target_combined="$sym_target"
                    else
                        target_combined="$sym_dir/$sym_target"
                    fi

                    if ! normalize_archive_path "" "$target_combined" >/dev/null 2>&1; then
                        rm -rf "$staging_dir"
                        record_deferred "desktop" "rose-pine-gtk" "Rosé Pine GTK archive contains escaping symlink target: $sym_path -> $sym_target"
                        return 0
                    fi
                fi
                ;;
            *)
                rm -rf "$staging_dir"
                record_deferred "desktop" "rose-pine-gtk" "Rosé Pine GTK archive contains forbidden entry type '$type_char'."
                return 0
                ;;
        esac
    done <<< "$verbose_listing"

    local members_listing
    if ! members_listing="$(tar -tf "$staging_archive" 2>/dev/null)"; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "rose-pine-gtk" "Rosé Pine GTK theme archive member listing failed."
        return 0
    fi

    local has_moon_index=0
    local has_moon_gtk3=0
    local member
    while IFS= read -r member; do
        [[ -n "$member" ]] || continue
        if [[ "$member" == /* ]] || ! validate_path_components "$member" || ! normalize_archive_path "" "$member" >/dev/null 2>&1; then
            rm -rf "$staging_dir"
            record_deferred "desktop" "rose-pine-gtk" "Rosé Pine GTK theme archive contains forbidden member path: $member"
            return 0
        fi

        local clean_member="${member#./}"
        if [[ "$clean_member" == "gtk3/rose-pine-moon-gtk/index.theme" ]]; then
            has_moon_index=1
        elif [[ "$clean_member" == "gtk3/rose-pine-moon-gtk/gtk-3.0/gtk.css" || "$clean_member" == "gtk3/rose-pine-moon-gtk/gtk-3.20/gtk.css" ]]; then
            has_moon_gtk3=1
        fi
    done <<< "$members_listing"

    if (( has_moon_index == 0 || has_moon_gtk3 == 0 )); then
        rm -rf "$staging_dir"
        record_deferred "desktop" "rose-pine-gtk" "Rosé Pine Moon GTK theme payload missing expected members in archive."
        return 0
    fi

    local extracted_dir="$staging_dir/extracted"
    if ! mkdir -p -- "$extracted_dir"; then
        rm -rf -- "$staging_dir"
        record_deferred "desktop" "rose-pine-gtk" "Could not create the temporary extraction directory."
        return 0
    fi

    # Extract only the required rose-pine-moon-gtk subtree
    if ! tar --warning=no-unknown-keyword -xzf "$staging_archive" -C "$extracted_dir" 2>/dev/null; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "rose-pine-gtk" "Failed to extract Rosé Pine GTK theme archive subtree."
        return 0
    fi

    local theme_src
    theme_src="$(find "$extracted_dir" -maxdepth 3 -type d -name "rose-pine-moon-gtk" 2>/dev/null | awk 'NR==1{print}' || true)"
    if [[ -z "$theme_src" || ! -d "$theme_src" || ! -f "$theme_src/index.theme" ]]; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "rose-pine-gtk" "Rosé Pine Moon GTK theme directory not found after extraction."
        return 0
    fi

    # Post-extraction verification: ensure no symlinks in the extracted tree resolve outside theme_src
    local symlink_escape=0
    local symlink_file target_resolved
    while IFS= read -r -d '' symlink_file; do
        target_resolved="$(readlink -f "$symlink_file" 2>/dev/null || true)"
        if [[ "$target_resolved" != "$theme_src"* && "$target_resolved" != "$extracted_dir"* ]]; then
            symlink_escape=1
            break
        fi
    done < <(find "$theme_src" -type l -print0)

    if (( symlink_escape != 0 )); then
        rm -rf "$staging_dir"
        record_deferred "desktop" "rose-pine-gtk" "Rosé Pine GTK theme archive contains escaping symbolic link."
        return 0
    fi

    # Stage safely and atomically as TARGET_USER
    if ! run_as_target_user mkdir -p "$themes_dir"; then
        rm -rf -- "$staging_dir"
        record_deferred "desktop" "rose-pine-gtk" "Failed to create the user theme directory."
        return 0
    fi
    local staging_target
    if ! staging_target="$(run_as_target_user mktemp -d "$TARGET_HOME/.local/share/themes/.rose-pine-moon-gtk.tmp.XXXXXX")" ||
       [[ -z "$staging_target" || ! -d "$staging_target" ]]; then
        rm -rf -- "$staging_dir"
        record_deferred "desktop" "rose-pine-gtk" "Failed to create the temporary user theme directory."
        return 0
    fi

    if ! run_as_target_user cp -a "$theme_src"/* "$staging_target/"; then
        run_as_target_user rm -rf "$staging_target"
        rm -rf "$staging_dir"
        record_deferred "desktop" "rose-pine-gtk" "Failed to stage Rosé Pine GTK theme files."
        return 0
    fi

    # Preserve any existing destination before the final rename.  This covers
    # user-created customizations and symlinks as well as an earlier partial
    # installation; normal replacement must never recursively delete it.
    local theme_backup=""
    if [[ -e "$theme_dest" || -L "$theme_dest" ]]; then
        local backup_stamp
        if ! backup_stamp="$(date +%Y%m%d-%H%M%S)"; then
            run_as_target_user rm -rf -- "$staging_target" || true
            rm -rf -- "$staging_dir"
            record_deferred "desktop" "rose-pine-gtk" "Could not create a safe backup name for the existing Rosé Pine GTK theme."
            return 0
        fi
        theme_backup="${theme_dest}.bak.${backup_stamp}"
        local backup_counter=1
        while [[ -e "$theme_backup" || -L "$theme_backup" ]]; do
            theme_backup="${theme_dest}.bak.${backup_stamp}.${backup_counter}"
            backup_counter=$((backup_counter + 1))
        done

        if ! run_as_target_user mv -T -- "$theme_dest" "$theme_backup"; then
            run_as_target_user rm -rf -- "$staging_target" || true
            rm -rf -- "$staging_dir"
            record_deferred "desktop" "rose-pine-gtk" "Failed to preserve the existing Rosé Pine GTK theme before replacement."
            return 0
        fi
    fi
    if ! run_as_target_user mv -T -- "$staging_target" "$theme_dest"; then
        if [[ -n "$theme_backup" && ! -e "$theme_dest" && ! -L "$theme_dest" ]]; then
            run_as_target_user mv -T -- "$theme_backup" "$theme_dest" || true
        fi
        run_as_target_user rm -rf -- "$staging_target" || true
        rm -rf "$staging_dir"
        record_deferred "desktop" "rose-pine-gtk" "Failed to install Rosé Pine GTK theme to $theme_dest."
        return 0
    fi

    rm -rf "$staging_dir"

    info "Rosé Pine Moon GTK theme installed successfully."
    record_success "rose-pine-gtk"
}

# Converge GTK Bookmarks file (shared across Thunar/GTK3 and GTK4 applications).
#
# Policy:
# 1. Fresh/empty file: writes the canonical managed standard block
#    (Documents, Downloads, Pictures, Music, Videos).
# 2. Existing file containing only personal bookmarks: preserves all personal
#    bookmarks in their existing relative order at the top and appends the managed block.
# 3. Existing file containing mixed/managed bookmarks: preserves personal bookmarks
#    situated prior to the first managed bookmark, de-duplicates and converges the
#    managed block at that position, and preserves subsequent personal bookmarks.
# 4. Preserves custom labels (e.g. 'file:///path Label') and non-file schemes (e.g. 'smb://').
# 5. Strict idempotency: returns immediately without modifying file mtime if already converged.
converge_gtk_bookmarks_file() {
    local bookmark_file="$1"
    local home_dir="${2:-$TARGET_HOME}"

    local dir
    dir="$(dirname "$bookmark_file")"
    [[ ! -L "$bookmark_file" && ! -L "$dir" ]] || return 1
    ensure_directory "$dir" || return 1

    local default_uris=(
        "file://${home_dir}/Documents"
        "file://${home_dir}/Downloads"
        "file://${home_dir}/Pictures"
        "file://${home_dir}/Music"
        "file://${home_dir}/Videos"
    )

    # Fresh/empty file: write default baseline in exact desired order
    if [[ ! -f "$bookmark_file" || ! -s "$bookmark_file" ]]; then
        local tmp
        if ! tmp="$(mktemp)"; then
            return 1
        fi
        for uri in "${default_uris[@]}"; do
            if ! printf '%s\n' "$uri" >> "$tmp"; then
                rm -f -- "$tmp"
                return 1
            fi
        done
        if ! run_as_target_user mv -- "$tmp" "$bookmark_file"; then
            rm -f -- "$tmp"
            return 1
        fi
        if ! run_as_target_user chmod 0644 "$bookmark_file"; then
            return 1
        fi
        return 0
    fi

    # Existing file: read lines and partition into personal vs managed
    local existing_lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        existing_lines+=("$line")
    done < "$bookmark_file"

    local personal_before=()
    local personal_after=()
    local found_first_managed=0

    for line in "${existing_lines[@]}"; do
        local uri="${line%% *}"
        local is_managed=0
        for def_uri in "${default_uris[@]}"; do
            if [[ "$uri" == "$def_uri" ]]; then
                is_managed=1
                break
            fi
        done

        if (( is_managed == 1 )); then
            found_first_managed=1
        else
            if (( found_first_managed == 0 )); then
                personal_before+=("$line")
            else
                personal_after+=("$line")
            fi
        fi
    done

    # Assemble converged lines:
    # 1. Personal bookmarks situated prior to standard managed block
    # 2. Standard managed bookmarks in exact desired order
    # 3. Personal bookmarks situated after standard managed block
    local target_lines=()
    for line in "${personal_before[@]}"; do
        target_lines+=("$line")
    done
    for uri in "${default_uris[@]}"; do
        target_lines+=("$uri")
    done
    for line in "${personal_after[@]}"; do
        target_lines+=("$line")
    done

    # Fully idempotent when already in converged desired state
    if [[ ${#existing_lines[@]} -eq ${#target_lines[@]} ]]; then
        local matches=1
        local i
        for (( i=0; i<${#target_lines[@]}; i++ )); do
            if [[ "${existing_lines[i]}" != "${target_lines[i]}" ]]; then
                matches=0
                break
            fi
        done
        if (( matches == 1 )); then
            return 0
        fi
    fi

    local tmp
    if ! tmp="$(mktemp)"; then
        return 1
    fi
    for line in "${target_lines[@]}"; do
        if ! printf '%s\n' "$line" >> "$tmp"; then
            rm -f -- "$tmp"
            return 1
        fi
    done

    if ! run_as_target_user mv -- "$tmp" "$bookmark_file"; then
        rm -f -- "$tmp"
        return 1
    fi
    if ! run_as_target_user chmod 0644 "$bookmark_file"; then
        return 1
    fi
}

converge_gtk_bookmarks() {
    local home_dir="${1:-$TARGET_HOME}"

    info "Converging GTK Places bookmarks."
    if declare -F safe_user_config_home >/dev/null 2>&1 &&
        ! safe_user_config_home "$home_dir/.config"; then
        record_deferred \
            "desktop" \
            "gtk-bookmarks" \
            "Refusing to follow a symlinked or unsafe GTK configuration path."
        return 0
    fi
    if ! converge_gtk_bookmarks_file "$home_dir/.config/gtk-3.0/bookmarks" "$home_dir" ||
       ! converge_gtk_bookmarks_file "$home_dir/.config/gtk-4.0/bookmarks" "$home_dir"; then
        record_deferred "desktop" "gtk-bookmarks" "Failed to converge GTK Places bookmarks."
        return 0
    fi
    record_success "gtk-bookmarks"
}

# Prepare desktop files and packages. Do not enable greetd here.
install_desktop() {
    if [[ "${DESKTOP:-}" != "hyprland" ]]; then
        die "Unsupported desktop profile: ${DESKTOP:-<unset>}"
    fi

    info "Configuring Hyprland desktop."

    validate_desktop_shell_selection
    deploy_hyprland_config
    deploy_session_shell_selection
    if [[ "${DESKTOP_SHELL:-}" == "noctalia" ]]; then
        deploy_noctalia_config
    else
        info "Noctalia user session configuration skipped; it remains installed only for the greeter."
    fi
    install_hack_nerd_font
    install_jetbrains_mono_nerd_font
    install_rose_pine_gtk_theme
    if ! install_noctalia_greeter; then
        return 1
    fi
    if ! configure_greetd; then
        return 1
    fi
    if ! configure_noctalia_greeter_state; then
        return 1
    fi
    if ! enable_desktop_services; then
        return 1
    fi

    validate_hyprland_desktop || {
        record_activation_failure \
            "desktop" \
            "hyprland" \
            "Hyprland desktop validation failed before activation."
        return 1
    }

    validate_greeter_configuration || {
        record_activation_failure \
            "desktop" \
            "greeter" \
            "Greeter validation failed before activation."
        return 1
    }

    info "Hyprland desktop configuration complete (activation deferred)."
    record_success "install_desktop"
}

# Final controlled activation. Never use enable --now on greetd.
GRAPHICAL_ACTIVATION_SNAPSHOT_VALID=0
GRAPHICAL_PREVIOUS_GREETD_STATE=""
GRAPHICAL_PREVIOUS_DEFAULT_TARGET=""

capture_graphical_activation_state() {
    local greetd_state
    local default_target

    greetd_state="$(systemctl is-enabled greetd.service 2>/dev/null || true)"
    default_target="$(systemctl get-default 2>/dev/null || true)"

    if [[ -z "$greetd_state" || ! "$default_target" =~ ^[A-Za-z0-9_.@:-]+\.target$ ]]; then
        return 1
    fi

    GRAPHICAL_PREVIOUS_GREETD_STATE="$greetd_state"
    GRAPHICAL_PREVIOUS_DEFAULT_TARGET="$default_target"
    GRAPHICAL_ACTIVATION_SNAPSHOT_VALID=1
}

restore_graphical_activation_state() {
    (( GRAPHICAL_ACTIVATION_SNAPSHOT_VALID == 1 )) || return 0

    local failed=0
    case "$GRAPHICAL_PREVIOUS_GREETD_STATE" in
        enabled*)
            sudo systemctl enable greetd.service || failed=1
            ;;
        *)
            sudo systemctl disable greetd.service || failed=1
            ;;
    esac

    sudo systemctl set-default "$GRAPHICAL_PREVIOUS_DEFAULT_TARGET" || failed=1
    GRAPHICAL_ACTIVATION_SNAPSHOT_VALID=0
    return "$failed"
}

rollback_graphical_activation() {
    if ! restore_graphical_activation_state; then
        error "Could not fully restore the previous graphical activation state."
    fi
}

activate_graphical_session() {
    if (( ACTIVATION_BLOCKED != 0 )); then
        GRAPHICAL_ACTIVATION_STATE="skipped"
        info "Skipping graphical activation; the login stack is unsafe."
        return 0
    fi

    info "Validating desktop stack before graphical activation."

    if ! validate_hyprland_desktop; then
        GRAPHICAL_ACTIVATION_STATE="skipped"
        record_activation_failure \
            "activation" \
            "hyprland" \
            "Refusing to activate graphical login: Hyprland validation failed."
        return 0
    fi

    if ! validate_greeter_configuration; then
        GRAPHICAL_ACTIVATION_STATE="skipped"
        record_activation_failure \
            "activation" \
            "greeter" \
            "Refusing to activate graphical login: greeter validation failed."
        return 0
    fi

    if ! capture_graphical_activation_state; then
        GRAPHICAL_ACTIVATION_STATE="skipped"
        record_activation_failure \
            "activation" \
            "snapshot" \
            "Could not capture the current greetd and system-target state before activation."
        return 0
    fi

    if ! enable_greetd; then
        GRAPHICAL_ACTIVATION_STATE="skipped"
        rollback_graphical_activation
        record_activation_failure \
            "activation" \
            "greetd" \
            "Refusing to activate graphical login: greetd could not be enabled."
        return 0
    fi

    if ! configure_graphical_target; then
        GRAPHICAL_ACTIVATION_STATE="skipped"
        rollback_graphical_activation
        record_activation_failure \
            "activation" \
            "systemd-target" \
            "Refusing to activate graphical login: graphical.target could not be configured."
        return 0
    fi

    if ! validate_graphical_activation; then
        GRAPHICAL_ACTIVATION_STATE="skipped"
        rollback_graphical_activation
        record_activation_failure \
            "activation" \
            "systemd" \
            "Graphical activation could not be validated."
        return 0
    fi

    GRAPHICAL_ACTIVATION_SNAPSHOT_VALID=0
    GRAPHICAL_ACTIVATION_STATE="completed"
    info "Graphical login activation complete."
    record_success "activate_graphical_session"
}
