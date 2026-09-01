#!/usr/bin/env bash

# Authoritative workstation validation.
#
# This module must not install packages or modify configuration.
# Callers decide whether a failed check is fatal.

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

validate_base_environment() {
    local failed=0

    info "Validating base workstation environment."

    local commands=(
        git
        curl
        zsh
        starship
        fzf
        zoxide
        nvim
        kitty
    )

    local command_name

    for command_name in "${commands[@]}"; do
        validate_required_command "$command_name" || failed=1
    done

    return "$failed"
}

validate_shell_environment() {
    local failed=0
    local expected_shell
    local actual_shell

    info "Validating shell environment."

    expected_shell="$(command -v zsh)"

    actual_shell="$(
        getent passwd "$TARGET_USER" |
            cut -d: -f7
    )"

    if [[ "$actual_shell" != "$expected_shell" ]]; then
        error "Default shell mismatch."
        error "Expected: $expected_shell"
        error "Actual:   $actual_shell"
        failed=1
    fi

    validate_required_file "$TARGET_HOME/.zshrc" || failed=1
    validate_required_file "$TARGET_HOME/.config/starship.toml" || failed=1
    validate_required_file "$TARGET_HOME/.config/kitty/kitty.conf" || failed=1

    if is_true "${OH_MY_ZSH:-false}"; then
        validate_required_file "$TARGET_HOME/.oh-my-zsh/oh-my-zsh.sh" ||
            failed=1
    fi

    return "$failed"
}

validate_hyprland_desktop() {
    local failed=0

    if [[ "${DESKTOP:-}" != "hyprland" ]]; then
        error "Unsupported desktop during validation: ${DESKTOP:-<unset>}"
        return 1
    fi

    info "Validating Hyprland desktop."

    local command_name
    for command_name in Hyprland hyprctl kitty thunar; do
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

validate_browser_environment() {
    local failed=0

    info "Validating browser environment."

    if is_true "${BROWSER_CHROMIUM:-false}"; then
        if ! package_installed chromium; then
            error "Chromium package is not installed."
            failed=1
        fi
    fi

    return "$failed"
}

validate_application_environment() {
    if ! is_true "${CURSOR:-false}"; then
        return 0
    fi

    info "Validating workstation applications."

    if ! package_installed cursor; then
        record_deferred \
            "validation" \
            "cursor" \
            "Cursor is enabled by the profile but is not installed."
    fi

    return 0
}

validate_flatpak_environment() {
    if ! is_true "${FLATPAK:-false}"; then
        return 0
    fi

    info "Validating Flatpak."

    if ! command_exists flatpak; then
        record_critical "validation" "flatpak" "Flatpak command is unavailable." 0
        return 0
    fi

    if ! flatpak remote-list \
        --system \
        --columns=name 2>/dev/null |
        grep -Fxq "flathub"; then

        record_critical "validation" "flathub" "System Flathub remote is not configured." 0
        return 0
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
        record_critical "validation" "nix" "Nix command is unavailable." 0
        return 0
    fi

    if ! command_exists devenv; then
        record_critical "validation" "devenv" "devenv command is unavailable." 0
        return 0
    fi

    if ! nix --version >/dev/null 2>&1; then
        record_critical "validation" "nix" "Nix failed to execute." 0
        return 0
    fi

    if ! devenv version >/dev/null 2>&1; then
        record_critical "validation" "devenv" "devenv failed to execute." 0
        return 0
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
            record_critical "validation" "$command_name" "Required container command is missing." 0
            return 0
        fi
    done

    if ! grep -qE "^${TARGET_USER}:" /etc/subuid; then
        record_critical "validation" "subuid" "No subordinate UID range exists for $TARGET_USER." 0
        return 0
    fi

    if ! grep -qE "^${TARGET_USER}:" /etc/subgid; then
        record_critical "validation" "subgid" "No subordinate GID range exists for $TARGET_USER." 0
        return 0
    fi

    if ! podman info >/dev/null 2>&1; then
        record_critical "validation" "podman info" "Rootless Podman validation failed." 0
        return 0
    fi

    return 0
}

validate_system() {
    local failed=0

    printf '\n'
    printf '%s\n' "------------------------------------------------------------"
    printf '%s\n' "Workstation validation"
    printf '%s\n' "------------------------------------------------------------"

    validate_base_environment || failed=1
    validate_shell_environment || failed=1
    validate_hyprland_desktop || failed=1
    validate_greeter_configuration || failed=1
    validate_browser_environment || failed=1
    validate_application_environment
    validate_flatpak_environment
    validate_nix_development_environment
    validate_container_environment

    printf '\n'

    if (( failed != 0 )); then
        record_critical \
            "validation" \
            "desktop" \
            "Critical desktop/shell validation failed." \
            1
        return 1
    fi

    info "Critical desktop validation checks passed."
    record_success "validate_system"

    printf '\n'
    printf 'Profile       : %s\n' "${PROFILE_NAME:-unknown}"
    printf 'Desktop       : %s\n' "${DESKTOP:-unknown}"
    printf 'Desktop shell : %s\n' "${DESKTOP_SHELL:-unknown}"
    printf 'Shell         : %s\n' "${SHELL:-unknown}"
    printf 'GPU profile   : %s\n' "${GPU:-unknown}"
    printf '\n'

    return 0
}
