#!/usr/bin/env bash

# Nix and devenv configuration for Fedora Hyprland Workstation.
#
# Fedora owns the operating system and desktop.
# Nix/devenv own project development environments.

nix_installed() {
    [[ -x /nix/var/nix/profiles/default/bin/nix ]]
}

load_nix_environment() {
    if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        # shellcheck source=/dev/null
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi

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
    if nix_installed; then
        info "Nix already installed."
        load_nix_environment
        return 0
    fi

    local installer_url
    local installer
    local temp_dir

    installer_url="https://nixos.org/nix/install"

    temp_dir="$(mktemp -d)"
    installer="$temp_dir/install-nix.sh"

    info "Downloading official Nix installer."

    if ! curl \
        --fail \
        --location \
        --show-error \
        --silent \
        --output "$installer" \
        "$installer_url"; then
        rm -rf "$temp_dir"
        die "Failed to download the Nix installer."
    fi

    [[ -s "$installer" ]] || {
        rm -rf "$temp_dir"
        die "Downloaded Nix installer is empty."
    }

    if ! head -n 1 "$installer" | grep -q '^#!'; then
        rm -rf "$temp_dir"
        die "Downloaded Nix installer does not appear to be a shell script."
    fi

    chmod 0700 "$installer"

    info "Installing Nix in multi-user mode."

    if ! /bin/bash "$installer" --daemon --yes; then
        rm -rf "$temp_dir"
        die "Nix installation failed."
    fi

    rm -rf "$temp_dir"

    load_nix_environment

    nix_installed ||
        die "Nix installation completed but Nix could not be detected."

    info "Nix installation validated."
}

configure_nix_features() {
    local config_dir="$TARGET_HOME/.config/nix"
    local config_file="$config_dir/nix.conf"

    ensure_directory "$config_dir"

    info "Configuring Nix."

    cat > "$config_file" <<'EOF'
experimental-features = nix-command flakes
auto-optimise-store = true
warn-dirty = false
EOF

    info "Nix configuration complete."
}

enable_nix_daemon() {
    if systemctl list-unit-files nix-daemon.service \
        --no-legend 2>/dev/null |
        grep -q '^nix-daemon.service'; then

        info "Enabling Nix daemon."

        sudo systemctl enable --now nix-daemon.service
    else
        die "nix-daemon.service was not found."
    fi
}

install_devenv() {
    load_nix_environment

    if command_exists devenv; then
        info "devenv already installed."
        return 0
    fi

    require_command nix

    info "Installing devenv."

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

    nix --version >/dev/null ||
        die "Nix validation failed."

    devenv version >/dev/null ||
        die "devenv validation failed."

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
