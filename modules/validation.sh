#!/usr/bin/env bash

# Authoritative validation.
#
# Login-stack checks may set ACTIVATION_BLOCKED.
# Workstation checks record required/deferred failures only.

validate_required_command() {
    local command_name="$1"

    if ! command_exists "$command_name"; then
        error "Missing required command: $command_name"
        return 1
    fi

    return 0
}

validate_required_file() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        error "Missing required file: $path"
        return 1
    fi

    return 0
}

validate_required_executable() {
    local path="$1"

    if [[ ! -x "$path" ]]; then
        error "Missing required executable: $path"
        return 1
    fi

    return 0
}

validate_hyprland_desktop() {
    local failed=0

    if [[ "${DESKTOP:-}" != "hyprland" ]]; then
        error "Unsupported desktop during validation: ${DESKTOP:-<unset>}"
        return 1
    fi

    info "Validating Hyprland login/session compositor."

    local command_name
    for command_name in Hyprland hyprctl; do
        validate_required_command "$command_name" || failed=1
    done

    # Fedora installs hyprpolkitagent as a libexec binary with systemd/D-Bus
    # user-service integration rather than as a command in the user's PATH.
    validate_required_executable /usr/libexec/hyprpolkitagent ||
        failed=1

    validate_required_file /usr/lib/systemd/user/hyprpolkitagent.service ||
        failed=1

    validate_required_executable /usr/libexec/xdg-desktop-portal-hyprland ||
        failed=1

    validate_required_file /usr/lib/systemd/user/xdg-desktop-portal-hyprland.service ||
        failed=1

    validate_required_file \
        "$TARGET_HOME/.config/hypr/hyprland.lua" ||
        failed=1

    validate_required_file /usr/lib64/security/pam_gnome_keyring.so ||
        failed=1

    if [[ "${DESKTOP_SHELL:-}" == "noctalia" ]] ||
        is_true "${INSTALL_NOCTALIA:-false}"; then
        validate_required_command noctalia || failed=1
    fi

    return "$failed"
}

validate_greeter_configuration() {
    local failed=0
    local greetd_config="/etc/greetd/config.toml"
    local greeter_toml="/var/lib/noctalia-greeter/greeter.toml"

    if ! is_true "${INSTALL_GREETER:-false}"; then
        return 0
    fi

    info "Validating greeter configuration."

    validate_required_command noctalia-greeter-session || failed=1

    if ! getent passwd greetd >/dev/null 2>&1; then
        error "Fedora greetd service user was not found."
        failed=1
    fi

    if ! getent group greetd >/dev/null 2>&1; then
        error "Fedora greetd service group was not found."
        failed=1
    fi

    validate_required_file "$greetd_config" || failed=1

    if [[ -f "$greetd_config" ]]; then
        grep -q 'user = "greetd"' "$greetd_config" || {
            error "greetd configuration must use user = \"greetd\"."
            failed=1
        }

        grep -q 'noctalia-greeter-session' "$greetd_config" || {
            error "greetd configuration must launch noctalia-greeter-session."
            failed=1
        }
    fi

    if [[ ! -d /var/lib/noctalia-greeter ]]; then
        error "Noctalia greeter state directory was not created."
        failed=1
    fi

    # The directory is 0750 greetd:greetd; inspect contents via sudo.
    if ! sudo test -f "$greeter_toml"; then
        error "Missing required file: $greeter_toml"
        failed=1
    elif ! sudo grep -q 'theme = "Adwaita"' "$greeter_toml"; then
        error "Greeter cursor theme is not Adwaita."
        failed=1
    fi

    if ! package_installed adwaita-cursor-theme; then
        error "adwaita-cursor-theme is not installed."
        failed=1
    fi

    systemctl list-unit-files greetd.service \
        --no-legend 2>/dev/null |
        grep -q '^greetd.service' || {
        error "greetd.service was not found."
        failed=1
    }

    return "$failed"
}

validate_graphical_activation() {
    local failed=0

    if is_true "${INSTALL_GREETER:-false}"; then
        if ! systemctl is-enabled greetd.service >/dev/null 2>&1; then
            error "greetd.service is not enabled."
            failed=1
        fi
    fi

    if is_true "${ENABLE_GRAPHICAL_TARGET:-false}"; then
        local target

        if ! target="$(systemctl get-default)"; then
            error "Could not read the default systemd target."
            failed=1
        elif [[ "$target" != "graphical.target" ]]; then
            error "Default system target is not graphical.target (got ${target})."
            failed=1
        fi
    fi

    return "$failed"
}

validate_login_stack() {
    local failed=0

    printf '\n'
    printf '%s\n' "------------------------------------------------------------"
    printf '%s\n' "Login stack validation"
    printf '%s\n' "------------------------------------------------------------"

    validate_hyprland_desktop || failed=1
    validate_greeter_configuration || failed=1

    if (( failed != 0 )); then
        record_activation_failure \
            "validation" \
            "login-stack" \
            "Hyprland/greetd login stack is unsafe to activate."
        return 0
    fi

    info "Login stack validation passed."
    record_success "validate_login_stack"
    return 0
}

validate_base_environment() {
    local failed=0

    info "Validating workstation CLI environment."

    local commands=(
        git
        curl
        wget
        zsh
        starship
        fzf
        zoxide
        nvim
        kitty
        thunar
        7z
    )

    local command_name

    for command_name in "${commands[@]}"; do
        if ! validate_required_command "$command_name"; then
            record_required "validation" "$command_name" "Required workstation command is missing."
            failed=1
        fi
    done

    return "$failed"
}

validate_shell_environment() {
    local failed=0
    local expected_shell
    local actual_shell

    info "Validating shell environment."

    expected_shell="$(command -v zsh || true)"

    if [[ -z "$expected_shell" ]]; then
        record_required "validation" "zsh" "Zsh is not installed."
        return 1
    fi

    actual_shell="$(
        getent passwd "$TARGET_USER" |
            cut -d: -f7
    )"

    if [[ "$actual_shell" != "$expected_shell" ]]; then
        record_required \
            "validation" \
            "shell" \
            "Default shell is ${actual_shell:-unknown}, expected ${expected_shell}."
        failed=1
    fi

    if ! validate_required_file "$TARGET_HOME/.zshrc"; then
        record_required "validation" "zshrc" "Zsh configuration was not deployed."
        failed=1
    fi

    if ! validate_required_file "$TARGET_HOME/.config/starship.toml"; then
        record_required "validation" "starship.toml" "Starship configuration was not deployed."
        failed=1
    fi

    if ! validate_required_file "$TARGET_HOME/.config/kitty/kitty.conf"; then
        record_required "validation" "kitty.conf" "Kitty configuration was not deployed."
        failed=1
    fi

    if [[ -f "$SCRIPT_DIR/dotfiles/kitty/themes/rose-pine-moon.conf" ]] && ! validate_required_file "$TARGET_HOME/.config/kitty/themes/rose-pine-moon.conf"; then
        record_deferred "validation" "kitty-theme" "Kitty Rosé Pine Moon theme was not deployed."
    fi

    if [[ -f "$SCRIPT_DIR/dotfiles/foot/foot.ini" ]] && ! validate_required_file "$TARGET_HOME/.config/foot/foot.ini"; then
        record_deferred "validation" "foot.ini" "Foot configuration was not deployed."
    fi

    if [[ -f "$SCRIPT_DIR/dotfiles/foot/themes/rose-pine-moon.ini" ]] && ! validate_required_file "$TARGET_HOME/.config/foot/themes/rose-pine-moon.ini"; then
        record_deferred "validation" "foot-theme" "Foot Rosé Pine Moon theme was not deployed."
    fi

    if [[ -f "$SCRIPT_DIR/dotfiles/qt6ct/colors/rose-pine-moon.conf" ]] && ! validate_required_file "$TARGET_HOME/.config/qt6ct/colors/rose-pine-moon.conf"; then
        record_deferred "validation" "qt6ct-colors" "Qt6ct Rosé Pine Moon color scheme was not deployed."
    fi

    if ! validate_required_file "$TARGET_HOME/.config/nvim/init.lua"; then
        record_required "validation" "nvim/init.lua" "Neovim configuration was not deployed."
        failed=1
    fi

    local user_dirs_file="$TARGET_HOME/.config/user-dirs.dirs"
    if [[ -f "$user_dirs_file" ]]; then
        local line
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*XDG_[A-Z]+_DIR=\"?([^\"]+)\"? ]]; then
                local dir_path="${BASH_REMATCH[1]}"
                dir_path="${dir_path/\$HOME/$TARGET_HOME}"
                if [[ -n "$dir_path" && ! -d "$dir_path" ]]; then
                    record_deferred "validation" "xdg-user-dirs" "XDG user directory is missing: $dir_path"
                fi
            fi
        done < "$user_dirs_file"
    else
        record_deferred "validation" "xdg-user-dirs" "user-dirs.dirs was not generated."
    fi

    local bookmarks_file="$TARGET_HOME/.config/gtk-3.0/bookmarks"
    if [[ ! -f "$bookmarks_file" ]]; then
        record_deferred "validation" "gtk-bookmarks" "GTK-3.0 bookmarks file was not generated: $bookmarks_file"
    fi

    if is_true "${OH_MY_ZSH:-false}"; then
        if ! validate_required_file "$TARGET_HOME/.oh-my-zsh/oh-my-zsh.sh"; then
            record_required "validation" "oh-my-zsh" "Oh My Zsh is not installed."
            failed=1
        fi
    fi

    return "$failed"
}

validate_browser_environment() {
    if is_true "${BROWSER_CHROMIUM:-false}"; then
        info "Validating Chromium."

        if ! package_installed chromium; then
            record_required "validation" "chromium" "Chromium package is not installed."
            return 1
        fi
    fi

    if is_true "${BROWSER_ULAA:-false}"; then
        info "Validating Ulaa Flatpak."

        if ! flatpak list --app --columns=application 2>/dev/null | grep -Fxq "com.ulaa.Ulaa"; then
            record_deferred "validation" "ulaa" "Ulaa Flatpak is enabled by the profile but is not installed."
        fi
    fi

    return 0
}

validate_application_environment() {
    info "Validating workstation applications."

    if is_true "${CURSOR:-false}"; then
        if ! package_installed cursor; then
            record_deferred \
                "validation" \
                "cursor" \
                "Cursor is enabled by the profile but is not installed."
        elif [[ ! -f "$TARGET_HOME/.config/cursor-flags.conf" ]]; then
            record_deferred \
                "validation" \
                "cursor-flags" \
                "Cursor flags configuration was not deployed."
        fi
    fi

    if is_true "${CHATGPT:-false}"; then
        if ! package_installed chatgpt; then
            record_deferred \
                "validation" \
                "chatgpt" \
                "ChatGPT is enabled by the profile but is not installed."
        fi
    fi

    if is_true "${KATE:-false}"; then
        if ! package_installed kate; then
            record_deferred \
                "validation" \
                "kate" \
                "Kate is enabled by the profile but is not installed."
        fi
    fi

    if is_true "${MEDIA_APPLICATIONS:-false}"; then
        local app
        for app in obs-studio mkvtoolnix-gui vlc; do
            if ! package_installed "$app"; then
                record_deferred \
                    "validation" \
                    "$app" \
                    "$app is enabled by the profile but is not installed."
            fi
        done
    fi

    local media_cmds=(
        ffmpeg
        ffprobe
        mediainfo
        mkvmerge
        MP4Box
        ccextractor
        mp4dump
        packager
        dovi_tool
        N_m3u8DL-RE
    )
    for cmd in "${media_cmds[@]}"; do
        if ! command_exists "$cmd" && [[ ! -x "/usr/local/bin/$cmd" ]]; then
            record_deferred \
                "validation" \
                "$cmd" \
                "Media utility command is missing: $cmd"
        fi
    done

    if is_true "${LOCALSEND:-false}"; then
        if ! flatpak list --app --columns=application 2>/dev/null | grep -Fxq "org.localsend.localsend_app"; then
            record_deferred \
                "validation" \
                "localsend" \
                "LocalSend Flatpak is enabled by the profile but is not installed."
        fi
    fi

    if is_true "${ANTIGRAVITY:-false}"; then
        if [[ ! -x "$TARGET_HOME/.local/bin/agy" ]] && ! command_exists agy; then
            record_deferred \
                "validation" \
                "antigravity" \
                "Antigravity CLI (agy) is enabled by profile but executable was not found."
        fi
    fi

    return 0
}

validate_diagnostics_environment() {
    local failed=0

    info "Validating system diagnostics utilities."

    local commands=(
        smartctl
        nvme
        inxi
        sensors
        htop
        btop
        iotop
        iostat
        lsof
        strace
        duf
        ncdu
    )

    local command_name

    for command_name in "${commands[@]}"; do
        if ! validate_required_command "$command_name"; then
            record_required "validation" "$command_name" "Diagnostic command is missing: $command_name"
            failed=1
        fi
    done

    return "$failed"
}

validate_flatpak_environment() {
    if ! is_true "${FLATPAK:-false}"; then
        return 0
    fi

    info "Validating Flatpak."

    if ! command_exists flatpak; then
        record_required "validation" "flatpak" "Flatpak command is unavailable."
        return 1
    fi

    if ! flatpak remote-list \
        --system \
        --columns=name 2>/dev/null |
        grep -Fxq "flathub"; then

        record_required "validation" "flathub" "System Flathub remote is not configured."
        return 1
    fi

    return 0
}

validate_nix_development_environment() {
    if ! is_true "${NIX:-false}"; then
        return 0
    fi

    info "Validating Nix development environment."

    load_nix_environment

    if ! command_exists nix; then
        record_required "validation" "nix" "Nix command is unavailable."
        return 1
    fi

    if ! command_exists devenv; then
        record_required "validation" "devenv" "devenv command is unavailable."
        return 1
    fi

    if ! nix --version >/dev/null 2>&1; then
        record_required "validation" "nix" "Nix failed to execute."
        return 1
    fi

    if ! devenv version >/dev/null 2>&1; then
        record_required "validation" "devenv" "devenv failed to execute."
        return 1
    fi

    return 0
}

validate_container_environment() {
    if ! is_true "${PODMAN:-false}"; then
        return 0
    fi

    info "Validating container environment."

    local command_name
    for command_name in podman buildah skopeo podman-compose; do
        if ! command_exists "$command_name"; then
            record_required "validation" "$command_name" "Required container command is missing."
            return 1
        fi
    done

    if ! grep -qE "^${TARGET_USER}:" /etc/subuid; then
        record_required "validation" "subuid" "No subordinate UID range exists for $TARGET_USER."
        return 1
    fi

    if ! grep -qE "^${TARGET_USER}:" /etc/subgid; then
        record_required "validation" "subgid" "No subordinate GID range exists for $TARGET_USER."
        return 1
    fi

    if ! podman info >/dev/null 2>&1; then
        record_required "validation" "podman info" "Rootless Podman validation failed."
        return 1
    fi

    return 0
}

validate_workstation_environment() {
    printf '\n'
    printf '%s\n' "------------------------------------------------------------"
    printf '%s\n' "Workstation capability validation"
    printf '%s\n' "------------------------------------------------------------"

    validate_base_environment || true
    validate_diagnostics_environment || true
    validate_shell_environment || true
    validate_browser_environment || true
    validate_application_environment || true
    validate_flatpak_environment || true
    validate_nix_development_environment || true
    validate_container_environment || true

    info "Workstation capability validation complete."

    printf '\n'
    printf 'Profile       : %s\n' "${PROFILE_NAME:-unknown}"
    printf 'Desktop       : %s\n' "${DESKTOP:-unknown}"
    printf 'Desktop shell : %s\n' "${DESKTOP_SHELL:-unknown}"
    printf 'Shell         : %s\n' "${SHELL:-unknown}"
    printf 'GPU profile   : %s\n' "${GPU:-unknown}"
    printf '\n'

    return 0
}

# Kept for callers/tests that still use the old name.
validate_system() {
    validate_login_stack
    validate_workstation_environment
}
