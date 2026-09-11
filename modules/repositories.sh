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
#   errornointernet/quickshell COPR
#       Upstream-documented release package source, enabled only for the
#       Aurelia shell.  The Hyprland COPR is not used for Quickshell because
#       it may expose git-suffixed development builds.
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
    local failed=0

    fedora_version="$(rpm -E '%fedora')"

    [[ "$fedora_version" =~ ^[0-9]+$ ]] ||
        die "Could not determine Fedora version for RPM Fusion."

    if ! rpmfusion_free_installed; then
        info "Installing RPM Fusion Free repository."

        run_with_retry "RPM Fusion Free" \
            run_dnf_command "$TIMEOUT_PACKAGE_SECONDS" "install RPM Fusion Free" \
            sudo dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm" ||
            { record_required "repositories" "rpmfusion-free" "Failed to install RPM Fusion Free."; failed=1; }
    else
        info "RPM Fusion Free repository already installed."
    fi

    if ! rpmfusion_nonfree_installed; then
        info "Installing RPM Fusion Nonfree repository."

        run_with_retry "RPM Fusion Nonfree" \
            run_dnf_command "$TIMEOUT_PACKAGE_SECONDS" "install RPM Fusion Nonfree" \
            sudo dnf install -y \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm" ||
            { record_required "repositories" "rpmfusion-nonfree" "Failed to install RPM Fusion Nonfree."; failed=1; }
    else
        info "RPM Fusion Nonfree repository already installed."
    fi

    return "$failed"
}

###############################################################################
# Third-party repository key convergence (ChatGPT)
###############################################################################

CHATGPT_EXPECTED_GPG_FINGERPRINT="3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4"

is_chatgpt_configured() {
    local repo_dir="/etc/yum.repos.d"
    if installer_test_override_allowed && [[ -n "${OVERRIDE_YUM_REPOS_DIR:-}" ]]; then
        repo_dir="$OVERRIDE_YUM_REPOS_DIR"
    fi
    local f
    if [[ -d "$repo_dir" ]]; then
        for f in "$repo_dir"/*; do
            if [[ -f "$f" || -L "$f" ]] && [[ "$f" == */chatgpt* || "$f" == */openai* ]]; then
                return 0
            fi
        done
    fi
    if declare -F package_installed >/dev/null && package_installed chatgpt; then
        return 0
    fi
    return 1
}

chatgpt_repository_path_unsafe() {
    local repo_dir="/etc/yum.repos.d"
    if installer_test_override_allowed && [[ -n "${OVERRIDE_YUM_REPOS_DIR:-}" ]]; then
        repo_dir="$OVERRIDE_YUM_REPOS_DIR"
    fi

    local f
    if [[ -d "$repo_dir" ]]; then
        for f in "$repo_dir"/*; do
            if [[ -L "$f" ]] && [[ "$f" == */chatgpt* || "$f" == */openai* ]]; then
                return 0
            fi
        done
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
    local pki_dir="/etc/pki/rpm-gpg"
    if installer_test_override_allowed && [[ -n "${OVERRIDE_RPM_GPG_DIR:-}" ]]; then
        pki_dir="$OVERRIDE_RPM_GPG_DIR"
    fi

    if chatgpt_repository_path_unsafe; then
        error "ChatGPT repository configuration is a symlink; refusing to trust or modify it."
        return 1
    fi

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

converge_vendor_repository_definitions() {
    local failed=0
    local repo_path

    # These repositories can participate in every later DNF transaction, so
    # repair any existing drift (or create a selected repository) before the
    # trust gate is consulted by the first package operation.
    if declare -F configure_cursor_repository >/dev/null 2>&1; then
        repo_path="${cursor_repo_file:-/etc/yum.repos.d/cursor.repo}"
        if is_true "${CURSOR:-false}" || [[ -f "$repo_path" || -L "$repo_path" ]]; then
            if ! configure_cursor_repository; then
                record_required \
                    "repositories" \
                    "cursor-repository" \
                    "Could not converge the reviewed Cursor repository definition."
                failed=1
            fi
        fi
    fi

    if declare -F configure_brave_origin_repository >/dev/null 2>&1; then
        repo_path="${brave_repo_file:-/etc/yum.repos.d/brave-browser.repo}"
        if is_true "${BROWSER_BRAVE_ORIGIN:-false}" || [[ -f "$repo_path" || -L "$repo_path" ]]; then
            if ! configure_brave_origin_repository; then
                record_required \
                    "repositories" \
                    "brave-repository" \
                    "Could not converge the reviewed Brave repository definition."
                failed=1
            fi
        fi
    fi

    return "$failed"
}

check_repository_trust() {
    if chatgpt_repository_path_unsafe; then
        error "Repository trust check failed: ChatGPT repository configuration is symlinked."
        return 1
    fi

    if is_chatgpt_configured; then
        if ! is_rpm_gpg_key_imported "$CHATGPT_EXPECTED_GPG_FINGERPRINT"; then
            error "Repository trust check failed: ChatGPT repository is configured but official OpenPGP key ($CHATGPT_EXPECTED_GPG_FINGERPRINT) is not trusted in RPM keyring."
            return 1
        fi
    fi

    # Vendor repository definitions are project-owned trust anchors.  If a
    # known file exists but no longer matches the reviewed HTTPS endpoint,
    # refuse every subsequent DNF operation until it is repaired.
    local cursor_path="${cursor_repo_file:-/etc/yum.repos.d/cursor.repo}"
    if declare -F cursor_repo_configured >/dev/null 2>&1 &&
        [[ -f "$cursor_path" || -L "$cursor_path" ]] &&
        ! cursor_repo_configured; then
        error "Repository trust check failed: Cursor repository definition is missing, altered, or unsafe."
        return 1
    fi

    local brave_path="${brave_repo_file:-/etc/yum.repos.d/brave-browser.repo}"
    if declare -F brave_origin_repo_installed >/dev/null 2>&1 &&
        [[ -f "$brave_path" || -L "$brave_path" ]] &&
        ! brave_origin_repo_installed; then
        error "Repository trust check failed: Brave repository definition is missing, altered, or unsafe."
        return 1
    fi

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
    local failed=0

    info "Configuring Fedora package repositories."

    # 1. Establish third-party repository GPG key trust FIRST before any DNF package operations or metadata refresh
    if ! converge_chatgpt_gpg_key; then
        record_required "repositories" "chatgpt-gpg" "Failed to converge official ChatGPT repository GPG key."
        warn "Skipping repository metadata refresh because unverified repository key failed to converge."
        return 1
    fi

    if ! converge_vendor_repository_definitions; then
        warn "Skipping DNF operations because a vendor repository definition could not be converged safely."
        return 1
    fi

    # `dnf copr` is provided by dnf-plugins-core.
    if ! install_dnf_packages dnf-plugins-core; then
        record_activation_failure \
            "repositories" \
            "dnf-plugins-core" \
            "dnf-plugins-core is required to enable COPR repositories."
        failed=1
    fi

    # Hyprland package source.
    if ! enable_copr "lionheartp/Hyprland"; then
        record_activation_failure \
            "repositories" \
            "lionheartp/Hyprland" \
            "Required Hyprland COPR could not be enabled."
        failed=1
    fi

    # Upstream Quickshell documents this release COPR.  Aurelia needs the
    # released v0.3 API, while the Hyprland COPR may expose git snapshots.
    # Keep this repository conditional so Noctalia installations do not add
    # an unnecessary third-party source.
    if [[ "${DESKTOP_SHELL:-}" == "aurelia" ]] &&
        ! enable_copr "errornointernet/quickshell"; then
        record_required \
            "repositories" \
            "errornointernet/quickshell" \
            "The documented stable Quickshell release COPR could not be enabled for Aurelia."
        failed=1
    fi

    # Starship package source.
    if ! enable_copr "atim/starship"; then
        record_required \
            "repositories" \
            "atim/starship" \
            "Starship COPR could not be enabled."
        failed=1
    fi

    # Multimedia and hardware ecosystem.
    if ! install_rpmfusion; then
        failed=1
    fi

    # Refresh metadata after repository changes.
    info "Refreshing repository metadata."

    if ! run_with_retry "dnf makecache after repositories" dnf_makecache; then
        record_required "repositories" "makecache" "Could not refresh DNF metadata after enabling repositories."
        failed=1
    fi

    if ! validate_repository_configuration; then
        failed=1
    fi

    if (( failed != 0 )); then
        return 1
    fi
    info "Repository configuration complete."
    record_success "configure_repositories"
}
