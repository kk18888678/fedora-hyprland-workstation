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

# Prepare desktop files and packages. Do not enable greetd here.
install_desktop() {
    if [[ "${DESKTOP:-}" != "hyprland" ]]; then
        die "Unsupported desktop profile: ${DESKTOP:-<unset>}"
    fi

    info "Configuring Hyprland desktop."

    install_noctalia_shell
    deploy_hyprland_config
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
