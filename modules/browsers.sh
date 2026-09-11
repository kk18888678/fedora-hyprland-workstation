#!/usr/bin/env bash

# Browser installation for Fedora Hyprland Workstation.
#
# Browser policy:
#   Chromium      Mandatory when enabled (Fedora repository)
#   Brave Origin  Optional
#   Firefox       Optional
#   Ulaa          Managed through Flatpak (com.ulaa.Ulaa in modules/flatpak.sh)
#
# Every browser is controlled by the active installation profile.

perform_install_chromium() {
    info "Installing Chromium."

    if ! install_dnf_packages chromium; then
        record_required "browsers" "chromium" "Chromium installation failed."
        return 1
    fi

    if ! rpm -q chromium >/dev/null 2>&1; then
        record_required "browsers" "chromium" "Chromium installation could not be validated."
        return 1
    fi

    info "Chromium installation validated."
    record_success "chromium"
    return 0
}

install_chromium() {
    if is_component_migrated "chromium"; then
        info "Chromium is owned by configuration reconciler; skipping in legacy stage."
        return 0
    fi

    if ! is_true "${BROWSER_CHROMIUM:-false}"; then
        info "Chromium disabled by profile."
        return 0
    fi

    perform_install_chromium
}

brave_repo_file="/etc/yum.repos.d/brave-browser.repo"

brave_origin_repo_installed() {
    [[ -f "$brave_repo_file" && ! -L "$brave_repo_file" ]] || return 1

    cmp -s "$brave_repo_file" <(
        printf '%s\n' \
            '[brave-browser]' \
            'name=Brave Browser' \
            'enabled=1' \
            'gpgcheck=1' \
            'gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc' \
            'baseurl=https://brave-browser-rpm-release.s3.brave.com/$basearch'
    )
}

configure_brave_origin_repository() {
    if brave_origin_repo_installed; then
        info "Brave repository already configured."
        return 0
    fi

    info "Adding official Brave RPM repository."

    # Keep the repository definition reviewed and deterministic.  The official
    # remote .repo file is intentionally not fetched and executed by dnf.
    if ! install_root_file_from_stdin_preserving_existing "$brave_repo_file" 0644 root root <<'EOF'
[brave-browser]
name=Brave Browser
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
baseurl=https://brave-browser-rpm-release.s3.brave.com/$basearch
EOF
    then
        return 1
    fi

    if ! brave_origin_repo_installed; then
        return 1
    fi

    info "Brave repository configured."
}

install_brave_origin() {
    if ! is_true "${BROWSER_BRAVE_ORIGIN:-false}"; then
        info "Brave Origin disabled by profile."
        return 0
    fi

    if ! configure_brave_origin_repository; then
        record_deferred \
            "browsers" \
            "brave-origin" \
            "Brave RPM repository could not be added."
        return 0
    fi

    info "Installing Brave Origin."

    if ! install_dnf_packages brave-browser; then
        record_deferred \
            "browsers" \
            "brave-origin" \
            "brave-browser package could not be installed."
        return 0
    fi

    if ! package_installed brave-browser; then
        record_deferred \
            "browsers" \
            "brave-origin" \
            "brave-browser was not present after installation."
        return 0
    fi

    info "Brave Origin installation validated."
    record_success "brave-origin"
}

perform_install_firefox() {
    info "Installing Firefox."

    if ! install_dnf_packages firefox; then
        record_deferred \
            "browsers" \
            "firefox" \
            "Firefox package could not be installed."
        return 1
    fi

    if ! rpm -q firefox >/dev/null 2>&1; then
        record_deferred \
            "browsers" \
            "firefox" \
            "Firefox was not present after installation."
        return 1
    fi

    info "Firefox installation validated."
    record_success "firefox"
    return 0
}

install_firefox() {
    if is_component_migrated "firefox"; then
        info "Firefox is owned by configuration reconciler; skipping in legacy stage."
        return 0
    fi

    if ! is_true "${BROWSER_FIREFOX:-false}"; then
        info "Firefox disabled by profile."
        return 0
    fi

    perform_install_firefox
}

configure_default_browser() {
    if is_role_migrated "browser"; then
        info "Default browser role is owned by configuration reconciler; skipping in legacy stage."
        return 0
    fi

    if ! is_true "${BROWSER_CHROMIUM:-false}"; then
        info "Chromium disabled; default browser configuration skipped."
        return 0
    fi

    if ! package_installed chromium; then
        return 0
    fi

    if ! command_exists xdg-mime; then
        warn "xdg-mime unavailable; default browser configuration skipped."
        return 0
    fi

    local desktop_file="chromium-browser.desktop"

    info "Setting Chromium as the default browser."

    local failed=0
    xdg-mime default "$desktop_file" x-scheme-handler/http || failed=1
    xdg-mime default "$desktop_file" x-scheme-handler/https || failed=1
    xdg-mime default "$desktop_file" text/html || failed=1

    if (( failed != 0 )); then
        record_deferred \
            "browsers" \
            "default-browser" \
            "Could not set Chromium as the default browser."
        return 0
    fi

    info "Default browser configured."
}

install_browsers() {
    info "Configuring web browsers."

    install_chromium
    install_brave_origin
    install_firefox

    configure_default_browser

    info "Browser configuration complete."
}
