#!/usr/bin/env bash

# Workstation application installation.
#
# Applications in this module are host-level desktop/development tools
# that do not belong to the base OS package manifests, browser module,
# or project-specific devenv/Nix environments.

cursor_repo_file="/etc/yum.repos.d/cursor.repo"

cursor_repo_configured() {
    [[ -f "$cursor_repo_file" ]] &&
        grep -Fq 'baseurl=https://downloads.cursor.com/yumrepo' \
            "$cursor_repo_file"
}

configure_cursor_repository() {
    if cursor_repo_configured; then
        info "Cursor repository already configured."
        return 0
    fi

    info "Configuring official Cursor RPM repository."

    local temp_file
    temp_file="$(mktemp)"

    cat >"$temp_file" <<'EOF'
[cursor]
name=Cursor
baseurl=https://downloads.cursor.com/yumrepo
enabled=1
gpgcheck=1
gpgkey=https://downloads.cursor.com/keys/anysphere.asc
EOF

    sudo install \
        --owner=root \
        --group=root \
        --mode=0644 \
        "$temp_file" \
        "$cursor_repo_file"

    rm -f "$temp_file"

    if ! cursor_repo_configured; then
        return 1
    fi

    info "Cursor repository configured."
}

install_cursor() {
    if ! is_true "${CURSOR:-false}"; then
        info "Cursor disabled by profile."
        return 0
    fi

    if ! configure_cursor_repository; then
        record_deferred \
            "applications" \
            "cursor" \
            "Cursor RPM repository could not be configured."
        return 0
    fi

    if package_installed cursor; then
        info "Cursor already installed."
        record_success "cursor"
        return 0
    fi

    info "Installing Cursor."

    if ! install_dnf_packages cursor; then
        record_deferred \
            "applications" \
            "cursor" \
            "Cursor package could not be installed."
        return 0
    fi

    if ! package_installed cursor; then
        record_deferred \
            "applications" \
            "cursor" \
            "Cursor was not present after installation."
        return 0
    fi

    info "Cursor installation validated."
    record_success "cursor"
}

install_applications() {
    info "Installing workstation applications."

    install_cursor

    info "Workstation application installation complete."
}
