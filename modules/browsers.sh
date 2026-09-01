#!/usr/bin/env bash

# Browser installation for Fedora Hyprland Workstation.
#
# Browser policy:
#   Chromium      Mandatory when enabled (Fedora repository)
#   Ulaa          Deferred on Fedora (official installer is Debian/apt)
#   Brave Origin  Optional
#   Firefox       Optional
#
# Every browser is controlled by the active installation profile.

install_chromium() {
    if ! is_true "${BROWSER_CHROMIUM:-false}"; then
        info "Chromium disabled by profile."
        return 0
    fi

    info "Installing Chromium."

    if ! install_dnf_packages chromium; then
        record_required "browsers" "chromium" "Chromium installation failed."
        return 0
    fi

    if ! rpm -q chromium >/dev/null 2>&1; then
        record_required "browsers" "chromium" "Chromium installation could not be validated."
        return 0
    fi

    info "Chromium installation validated."
    record_success "chromium"
}

ulaa_installed() {
    if rpm -qa | grep -qi '^ulaa'; then
        return 0
    fi

    command_exists ulaa && return 0
    command_exists ulaa-browser && return 0

    return 1
}

install_ulaa() {
    if ! is_true "${BROWSER_ULAA:-false}"; then
        info "Ulaa disabled by profile."
        return 0
    fi

    if ulaa_installed; then
        info "Ulaa already installed."
        record_success "ulaa"
        return 0
    fi

    # The official Ulaa Linux installer assumes Debian/Ubuntu/apt.
    # Do not install apt, fake dpkg layouts, or convert Debian packages.
    record_deferred \
        "browsers" \
        "ulaa" \
        "Official Ulaa installer is Debian/apt-based and is not supported on Fedora."
}

brave_origin_repo_installed() {
    [[ -f /etc/yum.repos.d/brave-browser.repo ]]
}

configure_brave_origin_repository() {
    if brave_origin_repo_installed; then
        info "Brave repository already configured."
        return 0
    fi

    info "Adding official Brave RPM repository."

    run_with_retry "Brave repository" \
        run_with_timeout "$TIMEOUT_METADATA_SECONDS" "add Brave repository" \
        sudo dnf config-manager addrepo \
        --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
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

    if ! install_dnf_packages brave-origin; then
        record_deferred \
            "browsers" \
            "brave-origin" \
            "brave-origin package could not be installed."
        return 0
    fi

    if ! rpm -q brave-origin >/dev/null 2>&1; then
        record_deferred \
            "browsers" \
            "brave-origin" \
            "brave-origin was not present after installation."
        return 0
    fi

    info "Brave Origin installation validated."
    record_success "brave-origin"
}

install_firefox() {
    if ! is_true "${BROWSER_FIREFOX:-false}"; then
        info "Firefox disabled by profile."
        return 0
    fi

    info "Installing Firefox."

    if ! install_dnf_packages firefox; then
        record_deferred \
            "browsers" \
            "firefox" \
            "Firefox package could not be installed."
        return 0
    fi

    if ! rpm -q firefox >/dev/null 2>&1; then
        record_deferred \
            "browsers" \
            "firefox" \
            "Firefox was not present after installation."
        return 0
    fi

    info "Firefox installation validated."
    record_success "firefox"
}

configure_default_browser() {
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

    xdg-mime default "$desktop_file" x-scheme-handler/http
    xdg-mime default "$desktop_file" x-scheme-handler/https
    xdg-mime default "$desktop_file" text/html

    info "Default browser configured."
}

install_browsers() {
    info "Configuring web browsers."

    install_chromium
    install_ulaa
    install_brave_origin
    install_firefox

    configure_default_browser

    info "Browser configuration complete."
}
