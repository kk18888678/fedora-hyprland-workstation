#!/usr/bin/env bash

# Nix and devenv configuration for Fedora Hyprland Workstation.
#
# Fedora owns the Nix installation and daemon.
# Nix/devenv own project development environments.
#
# Fedora 44 provides native nix and nix-daemon packages, so we deliberately
# avoid the upstream curl-based Nix installer.

nix_installed() {
    package_installed nix &&
        command_exists nix
}

load_nix_environment() {
    # Fedora's nix-daemon package provides this profile script.
    if [[ -e /etc/profile.d/nix-daemon.sh ]]; then
        # shellcheck source=/dev/null
        source /etc/profile.d/nix-daemon.sh
    fi

    # Keep compatibility with upstream Nix installations if this repository
    # is ever used on a system that already has one.
    if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        # shellcheck source=/dev/null
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi

    # Applications installed with `nix profile install` live here.
    if [[ -d "$TARGET_HOME/.nix-profile/bin" ]]; then
        case ":$PATH:" in
            *":$TARGET_HOME/.nix-profile/bin:"*)
                ;;
            *)
                export PATH="$TARGET_HOME/.nix-profile/bin:$PATH"
                ;;
        esac
    fi
}

install_nix_package_manager() {
    info "Installing Fedora Nix packages."

    install_dnf_packages \
        nix \
        nix-daemon

    nix_installed ||
        die "Fedora Nix installation could not be validated."

    load_nix_environment

    info "Fedora Nix installation validated."
}

configure_nix_features() {
    local config_dir="$TARGET_HOME/.config/nix"
    local config_file="$config_dir/nix.conf"

    ensure_directory "$config_dir"

    info "Configuring Nix user features."

    cat > "$config_file" <<'EOF'
experimental-features = nix-command flakes
warn-dirty = false
EOF

    info "Nix user configuration complete."
}

enable_nix_daemon() {
    if ! systemctl list-unit-files nix-daemon.service \
        --no-legend 2>/dev/null |
        grep -q '^nix-daemon.service'; then

        die "nix-daemon.service was not found."
    fi

    info "Enabling Nix daemon."

    sudo systemctl enable --now nix-daemon.service

    if ! systemctl is-active --quiet nix-daemon.service; then
        die "nix-daemon.service is not active."
    fi

    info "Nix daemon is active."
}

install_devenv() {
    load_nix_environment

    require_command nix

    if command_exists devenv; then
        info "devenv already installed."
        return 0
    fi

    info "Installing devenv through the Nix user profile."

    nix profile install nixpkgs#devenv

    load_nix_environment

    if ! command_exists devenv; then
        die "devenv installation could not be validated."
    fi

    info "devenv installation validated."
}

validate_nix_environment() {
    load_nix_environment

    command_exists nix ||
        die "Nix command is unavailable."

    command_exists devenv ||
        die "devenv command is unavailable."

    nix --version >/dev/null 2>&1 ||
        die "Nix failed to execute."

    devenv version >/dev/null 2>&1 ||
        die "devenv failed to execute."

    systemctl is-active --quiet nix-daemon.service ||
        die "Nix daemon is not active."

    info "Nix development environment validated."
}

install_nix() {
    if ! is_true "${NIX:-false}"; then
        info "Nix disabled by profile."
        return 0
    fi

    info "Configuring Nix development environment."

    install_nix_package_manager
    configure_nix_features
    enable_nix_daemon
    install_devenv
    validate_nix_environment

    info "Nix development environment complete."
}
