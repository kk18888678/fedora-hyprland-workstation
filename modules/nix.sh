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
        nix-daemon ||
        return 1

    nix_installed ||
        return 1

    load_nix_environment

    info "Fedora Nix installation validated."
}

configure_nix_features() {
    local config_dir="$TARGET_HOME/.config/nix"
    local config_file="$config_dir/nix.conf"
    local temp_file

    ensure_directory "$config_dir"

    info "Configuring Nix user features."

    temp_file="$(mktemp)"
    cat >"$temp_file" <<'EOF'
experimental-features = nix-command flakes
warn-dirty = false
EOF
    mv "$temp_file" "$config_file"

    info "Nix user configuration complete."
}

enable_nix_daemon() {
    if ! systemctl list-unit-files nix-daemon.service \
        --no-legend 2>/dev/null |
        grep -q '^nix-daemon.service'; then

        return 1
    fi

    info "Enabling Nix daemon."

    sudo systemctl enable --now nix-daemon.service

    if ! systemctl is-active --quiet nix-daemon.service; then
        return 1
    fi

    info "Nix daemon is active."
}

install_devenv() {
    load_nix_environment

    command_exists nix || return 1

    if command_exists devenv; then
        info "devenv already installed."
        return 0
    fi

    load_pinned_versions

    info "Installing devenv from pinned nixpkgs ${NIXPKGS_REV}."

    run_with_retry "nix profile install devenv" \
        nix profile install "$DEVENV_NIX_INSTALL_SPEC" ||
        return 1

    load_nix_environment

    command_exists devenv
}

install_nix() {
    if ! is_true "${NIX:-false}"; then
        info "Nix disabled by profile."
        return 0
    fi

    info "Configuring Nix development environment."

    if ! install_nix_package_manager; then
        record_critical "nix" "packages" "Fedora Nix packages could not be installed." 0
        return 0
    fi

    configure_nix_features

    if ! enable_nix_daemon; then
        record_critical "nix" "daemon" "nix-daemon.service is not active." 0
        return 0
    fi

    if ! install_devenv; then
        record_critical "nix" "devenv" "Pinned devenv install failed." 0
        return 0
    fi

    info "Nix development environment complete."
    record_success "nix"
}
