#!/usr/bin/env bash

# Browser installation for Fedora Hyprland Workstation.
#
# Browser policy:
#   Chromium      Fedora repository
#   Ulaa          Official Ulaa Linux installer
#   Brave Origin  Official Brave RPM repository
#   Firefox       Fedora repository
#
# Every browser is controlled by the active installation profile.

install_chromium() {
    if ! is_true "${BROWSER_CHROMIUM:-false}"; then
        info "Chromium disabled by profile."
        return 0
    fi

    info "Installing Chromium."

    install_dnf_packages chromium

    if ! rpm -q chromium >/dev/null 2>&1; then
        die "Chromium installation could not be validated."
    fi

    info "Chromium installation validated."
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
        return 0
    fi

    local installer_url
    local installer
    local temp_dir

    installer_url="https://ulaa.com/release/linux/stable/install-ulaa-browser.sh?isDownload=true"

    temp_dir="$(mktemp -d)"
    installer="$temp_dir/install-ulaa-browser.sh"

    info "Downloading official Ulaa installer."

    if ! curl \
        --fail \
        --location \
        --show-error \
        --silent \
        --output "$installer" \
        "$installer_url"; then
        rm -rf "$temp_dir"
        die "Failed to download the Ulaa installer."
    fi

    if [[ ! -s "$installer" ]]; then
        rm -rf "$temp_dir"
        die "Downloaded Ulaa installer is empty."
    fi

    if ! head -n 1 "$installer" | grep -q '^#!'; then
        rm -rf "$temp_dir"
        die "Downloaded Ulaa installer does not appear to be a shell script."
    fi

    chmod 0700 "$installer"

    info "Running official Ulaa installer."

    if ! /bin/bash "$installer"; then
        rm -rf "$temp_dir"
        die "Ulaa installer failed."
    fi

    rm -rf "$temp_dir"

    if ! ulaa_installed; then
        die "Ulaa installation completed but the browser could not be detected."
    fi

    info "Ulaa installation validated."
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

    sudo dnf config-manager addrepo \
        --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
}

install_brave_origin() {
    if ! is_true "${BROWSER_BRAVE_ORIGIN:-false}"; then
        info "Brave Origin disabled by profile."
        return 0
    fi

    configure_brave_origin_repository

    info "Installing Brave Origin."

    install_dnf_packages brave-origin

    if ! rpm -q brave-origin >/dev/null 2>&1; then
        die "Brave Origin installation could not be validated."
    fi

    info "Brave Origin installation validated."
}

install_firefox() {
    if ! is_true "${BROWSER_FIREFOX:-false}"; then
        info "Firefox disabled by profile."
        return 0
    fi

    info "Installing Firefox."

    install_dnf_packages firefox

    if ! rpm -q firefox >/dev/null 2>&1; then
        die "Firefox installation could not be validated."
    fi

    info "Firefox installation validated."
}

configure_default_browser() {
    if ! is_true "${BROWSER_CHROMIUM:-false}"; then
        info "Chromium disabled; default browser configuration skipped."
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

validate_browser_configuration() {
    if is_true "${BROWSER_CHROMIUM:-false}"; then
        rpm -q chromium >/dev/null 2>&1 ||
            die "Chromium validation failed."
    fi

    if is_true "${BROWSER_ULAA:-false}"; then
        ulaa_installed ||
            die "Ulaa validation failed."
    fi

    if is_true "${BROWSER_BRAVE_ORIGIN:-false}"; then
        rpm -q brave-origin >/dev/null 2>&1 ||
            die "Brave Origin validation failed."
    fi

    if is_true "${BROWSER_FIREFOX:-false}"; then
        rpm -q firefox >/dev/null 2>&1 ||
            die "Firefox validation failed."
    fi

    info "Browser configuration validated."
}

install_browsers() {
    info "Configuring web browsers."

    install_chromium
    install_ulaa
    install_brave_origin
    install_firefox

    configure_default_browser
    validate_browser_configuration

    info "Browser configuration complete."
}
