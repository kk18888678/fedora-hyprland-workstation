#!/usr/bin/env bash

# Hyprland desktop configuration for Fedora Hyprland Workstation.
#
# Graphical login activation (greetd enable + graphical.target) is a
# separate final phase. This module prepares and validates the desktop
# without switching a live SSH session onto a greeter.

deploy_hyprland_config() {
    local source="$SCRIPT_DIR/dotfiles/hypr"
    local destination="$TARGET_HOME/.config/hypr"

    [[ -d "$source" ]] ||
        die "Hyprland configuration not found: $source"

    ensure_symlink "$source" "$destination"

    info "Hyprland configuration linked."
}

deploy_noctalia_config() {
    local source="$SCRIPT_DIR/config/noctalia"
    local destination="$TARGET_HOME/.config/noctalia"

    if [[ -d "$source" ]]; then
        ensure_directory "$destination"
        for file in "$source"/*.toml; do
            [[ -f "$file" ]] || continue
            local target="$destination/$(basename "$file")"
            ensure_symlink "$file" "$target"
        done
        info "Noctalia configuration deployed."
    fi
}

install_noctalia_shell() {
    case "${DESKTOP_SHELL:-}" in
        noctalia)
            if ! is_true "${INSTALL_NOCTALIA:-false}"; then
                die "DESKTOP_SHELL=noctalia requires INSTALL_NOCTALIA=true."
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

install_noctalia_greeter() {
    if ! is_true "${INSTALL_GREETER:-false}"; then
        info "Graphical greeter disabled by profile."
        return 0
    fi

    info "Installing Noctalia greeter."

    install_dnf_packages noctalia-greeter || {
        record_activation_failure \
            "desktop" \
            "noctalia-greeter" \
            "noctalia-greeter package could not be installed."
        return 1
    }

    command_exists noctalia-greeter-session || {
        record_activation_failure \
            "desktop" \
            "noctalia-greeter-session" \
            "noctalia-greeter-session was not found after installation."
        return 1
    }

    info "Noctalia greeter installed."
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

configure_greetd() {
    if ! is_true "${INSTALL_GREETER:-false}"; then
        return 0
    fi

    local greeter_session
    local greetd_config="/etc/greetd/config.toml"

    greeter_session="$(command -v noctalia-greeter-session)"

    [[ -n "$greeter_session" ]] || {
        record_activation_failure \
            "desktop" \
            "greetd-command" \
            "Could not determine noctalia-greeter-session path."
        return 1
    }

    validate_greetd_user

    info "Configuring greetd."

    sudo install -d -m 0755 /etc/greetd

    install_root_file_from_stdin "$greetd_config" 0644 root root <<EOF
[terminal]
vt = 1

[default_session]
command = "$greeter_session"
user = "greetd"
EOF

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

    sudo install \
        -d \
        -m 0750 \
        -o greetd \
        -g greetd \
        "$dest"

    [[ -f "$managed" ]] ||
        die "Managed greeter config is missing: $managed"

    # Login-screen cursor only. Do not change the user Hyprland cursor.
    install_root_file "$managed" "$greeter_toml" 0644 greetd greetd

    info "Noctalia greeter state directory configured."
}

enable_desktop_services() {
    info "Enabling desktop services."

    if systemctl list-unit-files NetworkManager.service \
        --no-legend 2>/dev/null |
        grep -q '^NetworkManager.service'; then
        sudo systemctl enable NetworkManager.service
    fi

    if systemctl list-unit-files power-profiles-daemon.service \
        --no-legend 2>/dev/null |
        grep -q '^power-profiles-daemon.service'; then
        sudo systemctl enable power-profiles-daemon.service
    fi

    if is_true "${BLUETOOTH:-false}"; then
        if systemctl list-unit-files bluetooth.service \
            --no-legend 2>/dev/null |
            grep -q '^bluetooth.service'; then
            sudo systemctl enable bluetooth.service
        else
            record_required \
                "desktop" \
                "bluetooth" \
                "Bluetooth is enabled by the profile but bluetooth.service was not found."
        fi
    fi

    info "Desktop services configured."
}

enable_greetd() {
    if ! is_true "${INSTALL_GREETER:-false}"; then
        return 0
    fi

    info "Enabling greetd for the next boot (not replacing the current session)."

    sudo systemctl enable greetd.service

    info "greetd enabled."
}

configure_graphical_target() {
    if ! is_true "${ENABLE_GRAPHICAL_TARGET:-false}"; then
        info "Graphical target unchanged by profile."
        return 0
    fi

    info "Setting graphical.target as the default system target."

    sudo systemctl set-default graphical.target

    info "graphical.target configured."
}

install_hack_nerd_font() {
    load_pinned_versions

    local fonts_dir="${FONTS_INSTALL_DIR:-/usr/local/share/fonts/HackNerdFont}"
    if [[ -d "$fonts_dir" && -f "$fonts_dir/HackNerdFont-Regular.ttf" ]]; then
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
    staging_dir="$(mktemp -d)"
    local staging_archive="$staging_dir/hack.tar.xz"

    if ! download_and_verify_artifact "$HACK_NERD_FONT_URL" "$HACK_NERD_FONT_SHA512" "$staging_archive" "Hack Nerd Font"; then
        rm -rf "$staging_dir"
        record_deferred "desktop" "hack-nerd-font" "Failed to download or verify Hack Nerd Font archive."
        return 0
    fi

    local extracted_dir="$staging_dir/extracted"
    mkdir -p "$extracted_dir"

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

    if [[ "$fonts_dir" == /usr/* || "$fonts_dir" == /etc/* ]]; then
        sudo mkdir -p "$fonts_dir"
        sudo cp -r "$extracted_dir"/* "$fonts_dir/"
        sudo chmod 0755 "$fonts_dir"
        sudo chmod 0644 "$fonts_dir"/* 2>/dev/null || true
    else
        mkdir -p "$fonts_dir"
        cp -r "$extracted_dir"/* "$fonts_dir/"
        chmod 0755 "$fonts_dir"
        chmod 0644 "$fonts_dir"/* 2>/dev/null || true
    fi

    rm -rf "$staging_dir"

    if command_exists fc-cache; then
        fc-cache -f >/dev/null 2>&1 || true
    fi

    info "Hack Nerd Font installed successfully."
    record_success "hack-nerd-font"
}

install_rose_pine_gtk_theme() {
    load_pinned_versions

    local theme_dest="$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk"
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
    staging_dir="$(mktemp -d)"
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
    mkdir -p "$extracted_dir"

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
    run_as_target_user mkdir -p "$TARGET_HOME/.local/share/themes"
    local staging_target
    staging_target="$(run_as_target_user mktemp -d "$TARGET_HOME/.local/share/themes/.rose-pine-moon-gtk.tmp.XXXXXX")"

    if ! run_as_target_user cp -a "$theme_src"/* "$staging_target/"; then
        run_as_target_user rm -rf "$staging_target"
        rm -rf "$staging_dir"
        record_deferred "desktop" "rose-pine-gtk" "Failed to stage Rosé Pine GTK theme files."
        return 0
    fi

    # Atomically replace destination
    run_as_target_user rm -rf "$theme_dest"
    if ! run_as_target_user mv "$staging_target" "$theme_dest"; then
        run_as_target_user rm -rf "$staging_target"
        rm -rf "$staging_dir"
        record_deferred "desktop" "rose-pine-gtk" "Failed to install Rosé Pine GTK theme to $theme_dest."
        return 0
    fi

    rm -rf "$staging_dir"

    info "Rosé Pine Moon GTK theme installed successfully."
    record_success "rose-pine-gtk"
}

install_workstation_hotkeys() {
    local bin_source="$SCRIPT_DIR/bin/workstation-hotkeys"
    local desktop_source="$SCRIPT_DIR/config/desktop-entries/workstation-hotkeys.desktop"

    local bin_target="${HOTKEYS_BIN_DIR:-/usr/local/bin}/workstation-hotkeys"
    local desktop_target="${HOTKEYS_APPS_DIR:-/usr/local/share/applications}/workstation-hotkeys.desktop"

    if [[ -f "$bin_source" ]]; then
        info "Installing workstation-hotkeys command to $bin_target."
        if [[ "$bin_target" == /usr/* || "$bin_target" == /etc/* ]]; then
            sudo mkdir -p "$(dirname "$bin_target")"
            sudo cp "$bin_source" "$bin_target"
            sudo chmod 0755 "$bin_target"
        else
            mkdir -p "$(dirname "$bin_target")"
            cp "$bin_source" "$bin_target"
            chmod 0755 "$bin_target"
        fi
    fi

    if [[ -f "$desktop_source" ]]; then
        info "Installing workstation-hotkeys desktop entry to $desktop_target."
        if [[ "$desktop_target" == /usr/* || "$desktop_target" == /etc/* ]]; then
            sudo mkdir -p "$(dirname "$desktop_target")"
            sudo cp "$desktop_source" "$desktop_target"
            sudo chmod 0644 "$desktop_target"
        else
            mkdir -p "$(dirname "$desktop_target")"
            cp "$desktop_source" "$desktop_target"
            chmod 0644 "$desktop_target"
        fi
    fi

    info "Workstation hotkeys installed."
    record_success "workstation-hotkeys"
}

converge_gtk_bookmarks_file() {
    local bookmark_file="$1"
    local home_dir="${2:-$TARGET_HOME}"

    local dir
    dir="$(dirname "$bookmark_file")"
    ensure_directory "$dir"

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
        tmp="$(mktemp)"
        for uri in "${default_uris[@]}"; do
            printf '%s\n' "$uri" >> "$tmp"
        done
        run_as_target_user mv "$tmp" "$bookmark_file"
        run_as_target_user chmod 0644 "$bookmark_file"
        return 0
    fi

    # Existing file: read lines and URIs while preserving custom labels and remote protocols
    local existing_lines=()
    local existing_uris=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        existing_lines+=("$line")
        local uri
        uri="$(awk '{print $1}' <<< "$line")"
        existing_uris+=("$uri")
    done < "$bookmark_file"

    local missing_defaults=()
    for def_uri in "${default_uris[@]}"; do
        local found=0
        for ex_uri in "${existing_uris[@]}"; do
            if [[ "$ex_uri" == "$def_uri" ]]; then
                found=1
                break
            fi
        done
        if (( found == 0 )); then
            missing_defaults+=("$def_uri")
        fi
    done

    # Fully idempotent when all defaults are satisfied
    if [[ ${#missing_defaults[@]} -eq 0 ]]; then
        return 0
    fi

    # Append missing defaults preserving existing order, custom paths, and labels
    local tmp
    tmp="$(mktemp)"
    for line in "${existing_lines[@]}"; do
        printf '%s\n' "$line" >> "$tmp"
    done
    for def_uri in "${missing_defaults[@]}"; do
        printf '%s\n' "$def_uri" >> "$tmp"
    done

    run_as_target_user mv "$tmp" "$bookmark_file"
    run_as_target_user chmod 0644 "$bookmark_file"
}

converge_gtk_bookmarks() {
    local home_dir="${1:-$TARGET_HOME}"

    info "Converging GTK Places bookmarks."
    converge_gtk_bookmarks_file "$home_dir/.config/gtk-3.0/bookmarks" "$home_dir"
    converge_gtk_bookmarks_file "$home_dir/.config/gtk-4.0/bookmarks" "$home_dir"
    record_success "gtk-bookmarks"
}

# Prepare desktop files and packages. Do not enable greetd here.
install_desktop() {
    if [[ "${DESKTOP:-}" != "hyprland" ]]; then
        die "Unsupported desktop profile: ${DESKTOP:-<unset>}"
    fi

    info "Configuring Hyprland desktop."

    install_noctalia_shell
    deploy_hyprland_config
    deploy_noctalia_config
    install_hack_nerd_font
    install_rose_pine_gtk_theme
    converge_gtk_bookmarks
    install_workstation_hotkeys
    install_noctalia_greeter
    configure_greetd
    configure_noctalia_greeter_state
    enable_desktop_services

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

    enable_greetd
    configure_graphical_target

    if ! validate_graphical_activation; then
        GRAPHICAL_ACTIVATION_STATE="skipped"
        record_activation_failure \
            "activation" \
            "systemd" \
            "Graphical activation could not be validated."
        return 0
    fi

    GRAPHICAL_ACTIVATION_STATE="completed"
    info "Graphical login activation complete."
    record_success "activate_graphical_session"
}
