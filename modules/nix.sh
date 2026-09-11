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

    # User local binaries (such as agy)
    if [[ -d "$TARGET_HOME/.local/bin" ]]; then
        case ":$PATH:" in
            *":$TARGET_HOME/.local/bin:"*)
                ;;
            *)
                export PATH="$TARGET_HOME/.local/bin:$PATH"
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

    safe_user_config_home "$config_dir" || return 1
    ensure_directory "$config_dir" || return 1

    if [[ -L "$config_file" ]]; then
        error "Refusing to modify symlinked Nix configuration: $config_file"
        return 1
    fi

    info "Configuring Nix user features."

    if [[ ! -f "$config_file" ]]; then
        local initial_temp
        initial_temp="$(mktemp "$config_file.tmp.XXXXXX")" || return 1
        if ! cat >"$initial_temp" <<'EOF'
experimental-features = nix-command flakes
warn-dirty = false
EOF
        then
            rm -f -- "$initial_temp"
            return 1
        fi
        if ! mv -T -- "$initial_temp" "$config_file"; then
            rm -f -- "$initial_temp"
            return 1
        fi
        info "Nix user configuration complete."
        return 0
    fi

    # Nix uses the last assignment for a setting.  Read that assignment as
    # inert text, preserve its existing feature tokens, and add only the
    # required tokens.  Never source or eval user configuration.
    local existing_features=""
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*experimental-features[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            existing_features="${BASH_REMATCH[1]}"
            existing_features="${existing_features%%#*}"
        fi
    done < "$config_file"

    local merged_features=()
    declare -A seen_features=()
    local feature
    local had_nix_command=0
    local had_flakes=0
    for feature in $existing_features; do
        if [[ "$feature" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] &&
            [[ -z "${seen_features[$feature]+present}" ]]; then
            merged_features+=("$feature")
            seen_features["$feature"]=1
            [[ "$feature" == "nix-command" ]] && had_nix_command=1
            [[ "$feature" == "flakes" ]] && had_flakes=1
        fi
    done

    for feature in nix-command flakes; do
        if [[ -z "${seen_features[$feature]+present}" ]]; then
            merged_features+=("$feature")
            seen_features["$feature"]=1
        fi
    done

    local additions=""
    if [[ -z "$existing_features" || "$had_nix_command" -eq 0 || "$had_flakes" -eq 0 ]]; then
        additions+=$'\nexperimental-features = '
        additions+="${merged_features[*]}"
        additions+=$'\n'
    fi

    if ! grep -Eq '^[[:space:]]*warn-dirty[[:space:]]*=' "$config_file"; then
        additions+=$'warn-dirty = false\n'
    fi

    if [[ -n "$additions" ]]; then
        [[ "${additions:0:1}" == $'\n' ]] || additions=$'\n'"$additions"
        local temp_file
        temp_file="$(mktemp "${config_file}.tmp.XXXXXX")" || return 1
        if ! cp -p -- "$config_file" "$temp_file"; then
            rm -f -- "$temp_file"
            return 1
        fi
        if ! printf '%s' "$additions" >> "$temp_file"; then
            rm -f -- "$temp_file"
            return 1
        fi
        if ! mv -- "$temp_file" "$config_file"; then
            rm -f -- "$temp_file"
            return 1
        fi
    fi

    info "Nix user configuration complete."
}

enable_nix_daemon() {
    local unit_files
    if ! unit_files="$(systemctl list-unit-files nix-daemon.service --no-legend 2>/dev/null)" ||
        ! grep -q '^nix-daemon.service' <<< "$unit_files"; then

        return 1
    fi

    info "Enabling Nix daemon."

    if ! sudo systemctl enable --now nix-daemon.service; then
        return 1
    fi

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
        run_with_timeout "$TIMEOUT_NIX_SECONDS" "nix profile install devenv" \
        nix profile install "$DEVENV_NIX_INSTALL_SPEC" ||
        return 1

    load_nix_environment

    command_exists devenv
}

perform_install_nix() {
    info "Configuring Nix package manager and service."

    if ! install_nix_package_manager; then
        record_required "nix" "packages" "Fedora Nix packages could not be installed."
        return 1
    fi

    if ! configure_nix_features; then
        record_required "nix" "configuration" "Nix user configuration could not be updated safely."
        return 1
    fi

    if ! enable_nix_daemon; then
        record_required "nix" "daemon" "nix-daemon.service is not active."
        return 1
    fi

    info "Nix package manager and daemon configured."
    record_success "nix"
    return 0
}

install_nix() {
    if is_component_migrated "nix"; then
        info "Nix and devenv are owned by configuration reconciler; skipping in legacy stage."
        return 0
    fi

    if ! is_true "${NIX:-false}"; then
        info "Nix disabled by profile."
        return 0
    fi

    info "Configuring Nix development environment."

    if ! perform_install_nix; then
        return 1
    fi

    if ! install_devenv; then
        record_required "nix" "devenv" "Pinned devenv install failed."
        return 1
    fi

    info "Nix development environment complete."
    record_success "nix"
    return 0
}
