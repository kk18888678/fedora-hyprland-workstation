#!/usr/bin/env bash

# Package installation module.
#
# Package manifests live under:
#
#   packages/base.txt
#   packages/desktop.txt
#   packages/media.txt
#
# Additional manifests can be added later for NVIDIA, gaming, etc.

###############################################################################
# Manifest helpers
###############################################################################

read_package_manifest() {
    local manifest="$1"
    local line

    [[ -f "$manifest" ]] ||
        die "Package manifest not found: $manifest"

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Remove leading/trailing whitespace.
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Ignore blank lines and comments.
        [[ -z "$line" ]] && continue
        [[ "$line" == \#* ]] && continue

        printf '%s\n' "$line"
    done < "$manifest"
}

###############################################################################
# Package validation
###############################################################################

validate_manifest_packages() {
    local manifest="$1"
    local package

    info "Validating package manifest: $(basename "$manifest")"

    while IFS= read -r package; do
        if package_installed "$package"; then
            continue
        fi

        if ! package_available "$package"; then
            error "Required package is not available: $package"
            return 1
        fi
    done < <(read_package_manifest "$manifest")

    return 0
}

###############################################################################
# Manifest installation
###############################################################################

install_manifest() {
    local manifest="$1"
    local packages=()
    local package

    validate_manifest_packages "$manifest" || return 1

    while IFS= read -r package; do
        packages+=("$package")
    done < <(read_package_manifest "$manifest")

    if [[ ${#packages[@]} -eq 0 ]]; then
        warn "Package manifest is empty: $manifest"
        return 0
    fi

    install_dnf_packages "${packages[@]}"
}

###############################################################################
# Main entry point
###############################################################################

install_packages() {
    local base_manifest="$SCRIPT_DIR/packages/base.txt"
    local diagnostics_manifest="$SCRIPT_DIR/packages/diagnostics.txt"
    local desktop_manifest="$SCRIPT_DIR/packages/desktop.txt"
    local media_manifest="$SCRIPT_DIR/packages/media.txt"

    info "Installing base workstation packages."
    if ! install_manifest "$base_manifest"; then
        record_required "packages" "base" "Base workstation packages could not be installed."
    fi

    info "Installing system diagnostics packages."
    if ! install_manifest "$diagnostics_manifest"; then
        record_required "packages" "diagnostics" "System diagnostics packages could not be installed."
    fi

    if [[ "${DESKTOP:-}" == "hyprland" ]]; then
        info "Installing Hyprland desktop packages."
        if ! install_manifest "$desktop_manifest"; then
            record_activation_failure \
                "packages" \
                "desktop" \
                "Hyprland desktop packages could not be installed."
        fi
    else
        die "Unsupported desktop profile: ${DESKTOP:-<unset>}"
    fi

    info "Installing media packages."
    if ! install_manifest "$media_manifest"; then
        record_required "packages" "media" "Media packages could not be installed."
    fi

    info "Host package installation complete."
    record_success "install_packages"
    return 0
}
