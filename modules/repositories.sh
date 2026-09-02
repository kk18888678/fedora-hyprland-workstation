#!/usr/bin/env bash

# Repository configuration for Fedora Hyprland Workstation.
#
# This module deliberately keeps third-party repositories to a minimum.
#
# Current policy:
#
#   Fedora official repositories
#       Primary source for packages.
#
#   lionheartp/Hyprland COPR
#       Required because Fedora 44 does not currently provide the Hyprland
#       compositor and related desktop packages we require.
#
#   atim/starship COPR
#       Officially documented Fedora package source for Starship.
#
#   RPM Fusion Free / Nonfree
#       Used for multimedia and hardware-related packages where Fedora's
#       repositories intentionally do not provide them.
#
# The following minimaLinux repositories are intentionally NOT enabled:
#
#   leloubil/wl-clip-persist
#   tofik/nwg-shell
#
# They may be reconsidered later if an actual workstation requirement
# cannot be satisfied through Fedora repositories.

###############################################################################
# COPR helpers
###############################################################################

copr_enabled() {
    local copr="$1"
    local repo_fragment

    repo_fragment="${copr/\//:}"

    grep -Rqs \
        "$repo_fragment" \
        /etc/yum.repos.d/_copr:* 2>/dev/null
}

enable_copr() {
    local copr="$1"

    if copr_enabled "$copr"; then
        info "COPR already enabled: $copr"
        return 0
    fi

    info "Enabling COPR: $copr"

    run_with_retry "dnf copr enable $copr" \
        run_dnf_command "$TIMEOUT_PACKAGE_SECONDS" "dnf copr enable $copr" \
        sudo dnf copr enable -y "$copr"
}

###############################################################################
# RPM Fusion
###############################################################################

rpmfusion_free_installed() {
    package_installed rpmfusion-free-release
}

rpmfusion_nonfree_installed() {
    package_installed rpmfusion-nonfree-release
}

install_rpmfusion() {
    local fedora_version

    fedora_version="$(rpm -E '%fedora')"

    [[ "$fedora_version" =~ ^[0-9]+$ ]] ||
        die "Could not determine Fedora version for RPM Fusion."

    if ! rpmfusion_free_installed; then
        info "Installing RPM Fusion Free repository."

        run_with_retry "RPM Fusion Free" \
            run_dnf_command "$TIMEOUT_PACKAGE_SECONDS" "install RPM Fusion Free" \
            sudo dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm" ||
            record_required "repositories" "rpmfusion-free" "Failed to install RPM Fusion Free."
    else
        info "RPM Fusion Free repository already installed."
    fi

    if ! rpmfusion_nonfree_installed; then
        info "Installing RPM Fusion Nonfree repository."

        run_with_retry "RPM Fusion Nonfree" \
            run_dnf_command "$TIMEOUT_PACKAGE_SECONDS" "install RPM Fusion Nonfree" \
            sudo dnf install -y \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm" ||
            record_required "repositories" "rpmfusion-nonfree" "Failed to install RPM Fusion Nonfree."
    else
        info "RPM Fusion Nonfree repository already installed."
    fi
}

###############################################################################
# Third-party repository key convergence (ChatGPT)
###############################################################################

CHATGPT_EXPECTED_GPG_FINGERPRINT="3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4"

is_chatgpt_configured() {
    local repo_dir="${OVERRIDE_YUM_REPOS_DIR:-/etc/yum.repos.d}"
    local f
    if [[ -d "$repo_dir" ]]; then
        for f in "$repo_dir"/*; do
            if [[ -f "$f" ]] && [[ "$f" == */chatgpt* || "$f" == */openai* ]]; then
                return 0
            fi
        done
    fi
    if declare -F package_installed >/dev/null && package_installed chatgpt; then
        return 0
    fi
    return 1
}

is_rpm_gpg_key_imported() {
    local expected_fp="$1"
    local upper_expected_fp
    upper_expected_fp="$(printf '%s' "$expected_fp" | tr '[:lower:]' '[:upper:]')"

    # Verification of installed OpenPGP identity requires gpg capability
    if ! command -v gpg >/dev/null 2>&1; then
        return 1
    fi

    # Export installed public-key material from RPM database (%{DESCRIPTION} provides ASCII-armored OpenPGP blocks)
    local gpg_dump
    gpg_dump="$(rpm -qa "gpg-pubkey*" --qf '%{DESCRIPTION}\n' 2>/dev/null)" || gpg_dump=""
    if [[ -z "$gpg_dump" ]]; then
        return 1
    fi

    # Derive complete 40-hex OpenPGP fingerprints directly from exported key blocks
    local actual_fps
    actual_fps="$(gpg --with-colons --show-keys <<< "$gpg_dump" 2>/dev/null | awk -F: '$1=="fpr"{print toupper($10)}')" || actual_fps=""
    if [[ -z "$actual_fps" ]]; then
        return 1
    fi

    while IFS= read -r fpr; do
        if [[ "$fpr" == "$upper_expected_fp" ]]; then
            return 0
        fi
    done <<< "$actual_fps"

    return 1
}

converge_chatgpt_gpg_key() {
    local expected_fp="$CHATGPT_EXPECTED_GPG_FINGERPRINT"
    local pki_dir="${OVERRIDE_RPM_GPG_DIR:-/etc/pki/rpm-gpg}"

    # 1. If ChatGPT repository is not configured on this host, absence of key is a safe no-op
    if ! is_chatgpt_configured; then
        return 0
    fi

    # 2. Once repository is configured, expected key file MUST exist on disk
    local key_file=""
    local candidate
    for candidate in \
        "$pki_dir/RPM-GPG-KEY-chatgpt-${expected_fp}.asc" \
        "$pki_dir/RPM-GPG-KEY-chatgpt"*; do
        if [[ -f "$candidate" ]]; then
            key_file="$candidate"
            break
        fi
    done

    if [[ -z "$key_file" || ! -f "$key_file" ]]; then
        error "ChatGPT repository is configured but official GPG key file is missing in $pki_dir."
        return 1
    fi

    # 3. GPG verification capability MUST be available to inspect fingerprint
    if ! command -v gpg >/dev/null 2>&1; then
        error "gpg command unavailable to verify official ChatGPT repository GPG key."
        return 1
    fi

    # 4. Extract and strictly verify OpenPGP fingerprint
    local actual_fp
    actual_fp="$(
        gpg --with-colons --show-keys "$key_file" 2>/dev/null |
        awk -F: '$1=="fpr"{print toupper($10); exit}'
    )"

    if [[ -z "$actual_fp" ]]; then
        error "Could not read OpenPGP fingerprint from ChatGPT key file: $key_file"
        return 1
    fi

    if [[ "$actual_fp" != "$expected_fp" ]]; then
        error "ChatGPT repository GPG key fingerprint mismatch!"
        error "Expected : $expected_fp"
        error "Found    : $actual_fp (in $key_file)"
        error "Refusing to import untrusted repository key."
        return 1
    fi

    # 5. Meaningful Idempotency: inspect if the verified key is already trusted in RPM keyring
    if is_rpm_gpg_key_imported "$expected_fp"; then
        info "Official ChatGPT repository GPG key ($expected_fp) is already trusted in RPM keyring."
        return 0
    fi

    # 6. Import verified key into RPM keyring
    if ! sudo rpm --import "$key_file"; then
        error "Failed to import verified ChatGPT GPG key ($expected_fp) into RPM keyring."
        return 1
    fi

    info "Verified and imported official ChatGPT repository OpenPGP key ($expected_fp)."
    return 0
}

###############################################################################
# Repository validation
###############################################################################

validate_repository_configuration() {
    if ! run_dnf_command "$TIMEOUT_METADATA_SECONDS" "dnf repolist" dnf repolist --enabled >/dev/null; then
        record_required "repositories" "repolist" "DNF repository validation failed."
        return 1
    fi

    info "Repository configuration validated."
}

###############################################################################
# Main entry point
###############################################################################

configure_repositories() {
    info "Configuring Fedora package repositories."

    # 1. Establish third-party repository GPG key trust FIRST before any DNF package operations or metadata refresh
    if ! converge_chatgpt_gpg_key; then
        record_required "repositories" "chatgpt-gpg" "Failed to converge official ChatGPT repository GPG key."
        warn "Skipping repository metadata refresh because unverified repository key failed to converge."
        return 0
    fi

    # `dnf copr` is provided by dnf-plugins-core.
    install_dnf_packages dnf-plugins-core ||
        record_activation_failure \
            "repositories" \
            "dnf-plugins-core" \
            "dnf-plugins-core is required to enable COPR repositories."

    # Hyprland package source.
    if ! enable_copr "lionheartp/Hyprland"; then
        record_activation_failure \
            "repositories" \
            "lionheartp/Hyprland" \
            "Required Hyprland COPR could not be enabled."
    fi

    # Starship package source.
    if ! enable_copr "atim/starship"; then
        record_required \
            "repositories" \
            "atim/starship" \
            "Starship COPR could not be enabled."
    fi

    # Multimedia and hardware ecosystem.
    install_rpmfusion

    # Refresh metadata after repository changes.
    info "Refreshing repository metadata."

    run_with_retry "dnf makecache after repositories" dnf_makecache ||
        record_required "repositories" "makecache" "Could not refresh DNF metadata after enabling repositories."

    validate_repository_configuration

    info "Repository configuration complete."
    record_success "configure_repositories"
}
