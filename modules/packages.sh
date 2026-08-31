#!/usr/bin/env bash

# Package installation module.
#
# Package manifests live under:
#
#   packages/base.txt
#   packages/desktop.txt
#
# Additional manifests can be added later for media, NVIDIA, gaming, etc.

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

package_available() {
    local package="$1"

    dnf -q repoquery --available "$package" >/dev/null 2>&1
}

validate_manifest_packages() {
    local manifest="$1"
    local package

    info "Validating package manifest: $(basename "$manifest")"

    while IFS= read -r package; do
        if package_installed "$package"; then
            continue
        fi

        if ! package_available "$package"; then
            die "Required package is not available: $package"
        fi
    done < <(read_package_manifest "$manifest")
}

###############################################################################
# Manifest installation
###############################################################################

install_manifest() {
    local manifest="$1"
    local packages=()
    local package

    validate_manifest_packages "$manifest"

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
    local desktop_manifest="$SCRIPT_DIR/packages/desktop.txt"

    info "Installing base workstation packages."
    install_manifest "$base_manifest"

    if [[ "${DESKTOP:-}" == "hyprland" ]]; then
        info "Installing Hyprland desktop packages."
        install_manifest "$desktop_manifest"
    else
        die "Unsupported desktop profile: ${DESKTOP:-<unset>}"
    fi

    info "Host package installation complete."
}
