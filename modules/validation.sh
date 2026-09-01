#!/usr/bin/env bash

# Final workstation validation.
#
# This module must not install packages or modify configuration.
# Its purpose is to verify that the requested workstation profile
# was successfully applied.

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

validate_desktop_environment() {
    local failed=0

    if [[ "${DESKTOP:-}" != "hyprland" ]]; then
        error "Unsupported desktop during validation: ${DESKTOP:-<unset>}"
        return 1
    fi

    info "Validating Hyprland desktop."

    local commands=(
        Hyprland
        hyprctl
        kitty
        thunar
    )

    local command_name

    for command_name in "${commands[@]}"; do
        validate_required_command "$command_name" || failed=1
    done

    # Fedora installs hyprpolkitagent as a libexec binary with systemd/D-Bus
    # user-service integration rather than as a command in the user's PATH.
    validate_required_file /usr/libexec/hyprpolkitagent ||
        failed=1

    validate_required_file /usr/lib/systemd/user/hyprpolkitagent.service ||
        failed=1

    validate_required_file \
        "$TARGET_HOME/.config/hypr/hyprland.lua" ||
        failed=1

    if is_true "${INSTALL_NOCTALIA:-false}"; then
        validate_required_command noctalia || failed=1
    fi

    if is_true "${INSTALL_GREETER:-false}"; then
        if ! systemctl is-enabled greetd.service >/dev/null 2>&1; then
            error "greetd.service is not enabled."
            failed=1
        fi

        validate_required_file /etc/greetd/config.toml ||
            failed=1

        validate_required_file /var/lib/noctalia-greeter ||
            failed=1
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

    if is_true "${BROWSER_ULAA:-false}"; then
        if ! ulaa_installed; then
            error "Ulaa is not installed."
            failed=1
        fi
    fi

    if is_true "${BROWSER_BRAVE_ORIGIN:-false}"; then
        if ! package_installed brave-origin; then
            error "Brave Origin is not installed."
            failed=1
        fi
    fi

    if is_true "${BROWSER_FIREFOX:-false}"; then
        if ! package_installed firefox; then
            error "Firefox is not installed."
            failed=1
        fi
    fi

    return "$failed"
}

validate_application_environment() {
    local failed=0

    info "Validating workstation applications."

    if is_true "${CURSOR:-false}"; then
        if ! package_installed cursor; then
            error "Cursor package is not installed."
            failed=1
        fi
    fi

    return "$failed"
}

validate_flatpak_environment() {
    if ! is_true "${FLATPAK:-false}"; then
        return 0
    fi

    info "Validating Flatpak."

    if ! command_exists flatpak; then
        error "Flatpak command is unavailable."
        return 1
    fi

    if ! flatpak remote-list \
        --system \
        --columns=name 2>/dev/null |
        grep -Fxq "flathub"; then

        error "System Flathub remote is not configured."
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
        error "Nix command is unavailable."
        return 1
    fi

    if ! command_exists devenv; then
        error "devenv command is unavailable."
        return 1
    fi

    if ! nix --version >/dev/null 2>&1; then
        error "Nix failed to execute."
        return 1
    fi

    if ! devenv version >/dev/null 2>&1; then
        error "devenv failed to execute."
        return 1
    fi

    return 0
}

validate_container_environment() {
    local failed=0

    if ! is_true "${PODMAN:-false}"; then
        return 0
    fi

    info "Validating container environment."

    local commands=(
        podman
        buildah
        skopeo
        podman-compose
    )

    local command_name

    for command_name in "${commands[@]}"; do
        validate_required_command "$command_name" || failed=1
    done

    if ! grep -qE "^${TARGET_USER}:" /etc/subuid; then
        error "No subordinate UID range exists for $TARGET_USER."
        failed=1
    fi

    if ! grep -qE "^${TARGET_USER}:" /etc/subgid; then
        error "No subordinate GID range exists for $TARGET_USER."
        failed=1
    fi

    if ! podman info >/dev/null 2>&1; then
        error "Rootless Podman validation failed."
        failed=1
    fi

    return "$failed"
}

validate_system_target() {
    if ! is_true "${ENABLE_GRAPHICAL_TARGET:-false}"; then
        return 0
    fi

    info "Validating default system target."

    local target

    target="$(
        systemctl get-default 2>/dev/null ||
            true
    )"

    if [[ "$target" != "graphical.target" ]]; then
        error "Default system target is not graphical.target."
        return 1
    fi

    return 0
}

validate_system() {
    local failed=0

    printf '\n'
    printf '%s\n' "------------------------------------------------------------"
    printf '%s\n' "Final workstation validation"
    printf '%s\n' "------------------------------------------------------------"

    validate_base_environment || failed=1
    validate_shell_environment || failed=1
    validate_desktop_environment || failed=1
    validate_browser_environment || failed=1
    validate_application_environment || failed=1
    validate_flatpak_environment || failed=1
    validate_nix_development_environment || failed=1
    validate_container_environment || failed=1
    validate_system_target || failed=1

    printf '\n'

    if (( failed != 0 )); then
        error "Workstation validation failed."
        return 1
    fi

    info "All workstation validation checks passed."

    printf '\n'
    printf 'Profile       : %s\n' "${PROFILE_NAME:-unknown}"
    printf 'Desktop       : %s\n' "${DESKTOP:-unknown}"
    printf 'Shell         : %s\n' "${SHELL:-unknown}"
    printf 'GPU profile   : %s\n' "${GPU:-unknown}"
    printf 'Cursor        : %s\n' "${CURSOR:-false}"
    printf 'Nix/devenv    : %s\n' "${NIX:-false}"
    printf 'Podman        : %s\n' "${PODMAN:-false}"
    printf 'Flatpak       : %s\n' "${FLATPAK:-false}"
    printf '\n'

    return 0
}
