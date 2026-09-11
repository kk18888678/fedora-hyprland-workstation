#!/usr/bin/env bash

# Package installation module.
#
# Package manifests live under:
#
#   packages/base.txt
#   packages/desktop.txt
#   packages/bluetooth.txt
#   packages/media.txt
#
# Additional manifests can be added later for NVIDIA, gaming, etc.

_PACKAGE_MODULE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

###############################################################################
# Manifest helpers
###############################################################################

valid_package_manifest_name() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9+._:-]{0,127}$ ]]
}

read_package_manifest() {
    local manifest="$1"
    local line
    declare -A seen_packages=()

    [[ -f "$manifest" && ! -L "$manifest" ]] || {
        error "Package manifest not found or is a symlink: $manifest"
        return 1
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Remove leading/trailing whitespace.
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Ignore blank lines and comments.
        [[ -z "$line" ]] && continue
        [[ "$line" == \#* ]] && continue

        valid_package_manifest_name "$line" || {
            error "Invalid package name in manifest $manifest: $line"
            return 1
        }

        if [[ -n "${seen_packages[$line]+present}" ]]; then
            error "Duplicate package in manifest $manifest: $line"
            return 1
        fi
        seen_packages["$line"]=1

        printf '%s\n' "$line"
    done < "$manifest"
}

###############################################################################
# User-managed desired-state manifest
###############################################################################

user_managed_manifest_path() {
    printf '%s/packages/user-managed.tsv\n' "$SCRIPT_DIR"
}

user_managed_profile_applies() {
    local profiles="$1"
    case "$profiles" in
        all) return 0 ;;
        workstation|vm) [[ "${PROFILE_NAME:-}" == "$profiles" ]] ;;
        'workstation vm'|'vm workstation') return 0 ;;
        *) return 1 ;;
    esac
}

valid_user_managed_source() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,127}$ ]]
}

valid_user_managed_package_id() {
    local provider="$1"
    local identifier="$2"

    if [[ "$provider" == dnf ]]; then
        [[ "$identifier" =~ ^[A-Za-z0-9][A-Za-z0-9+._:-]{0,127}$ ]]
    elif [[ "$provider" == flatpak ]]; then
        [[ "$identifier" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]
    elif [[ "$provider" == aurelia ]]; then
        [[ "$identifier" =~ ^[A-Za-z0-9][A-Za-z0-9+._:-]{0,127}$ ]]
    else
        return 1
    fi
}

valid_user_managed_aurelia_source() {
    [[ "${1:-}" =~ ^github\.com/[a-z0-9][a-z0-9_.-]{0,99}/[a-z0-9][a-z0-9_.-]{0,99}$ ]]
}

valid_user_managed_aurelia_version() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9+._:/-]{0,127}$ ]]
}

valid_user_managed_aurelia_asset() {
    local asset="${1:-}"
    [[ "$asset" =~ ^[A-Za-z0-9][A-Za-z0-9._+@%()-]{0,254}$ ]]
}

valid_user_managed_aurelia_checksum() {
    [[ "${1:-}" =~ ^sha256:[0-9a-fA-F]{64}$ ]]
}

valid_user_managed_aurelia_metadata() {
    local source="$1"
    local identifier="$2"
    local version="$3"
    local asset="$4"
    local checksum="$5"
    local target="$6"
    local artifact_url="$7"
    local version_lower="${version,,}"
    local source_lower="${source,,}"
    local asset_lower="${asset,,}"

    valid_user_managed_aurelia_source "$source" || return 1
    valid_user_managed_package_id aurelia "$identifier" || return 1
    valid_user_managed_aurelia_version "$version" || return 1
    valid_user_managed_aurelia_asset "$asset" || return 1
    valid_user_managed_aurelia_checksum "$checksum" || return 1
    [[ "$target" == ".local/bin/$identifier" ]] || return 1
    [[ "$target" =~ ^\.local/bin/[A-Za-z0-9][A-Za-z0-9+._:-]{0,127}$ ]] || return 1
    [[ "${artifact_url,,}" == "https://${source_lower}/releases/download/${version_lower}/${asset_lower}" ]] || return 1
    [[ "$artifact_url" != *[[:space:]]* && "$artifact_url" != *\?* && "$artifact_url" != *\#* ]]
}

read_user_managed_manifest() {
    local manifest
    local line
    local provider
    local source
    local identifier
    local scope
    local profiles
    local version
    local asset
    local checksum
    local target
    local artifact_url
    local extra

    manifest="$(user_managed_manifest_path)"
    [[ -f "$manifest" && ! -L "$manifest" ]] || {
        error "User-managed package manifest is missing or is a symlink: $manifest"
        return 1
    }
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        provider=""
        source=""
        identifier=""
        scope=""
        profiles=""
        version=""
        asset=""
        checksum=""
        target=""
        artifact_url=""
        extra=""
        IFS=$'\t' read -r provider source identifier scope profiles version asset checksum target artifact_url extra <<< "$line"
        if [[ -n "$extra" || -z "$provider" || -z "$source" || -z "$identifier" ||
              -z "$scope" || -z "$profiles" ]] ||
           ! valid_user_managed_source "$source" ||
           ! valid_user_managed_package_id "$provider" "$identifier" ||
           [[ "$scope" != system && "$scope" != user ]] ||
           ! user_managed_profile_applies "$profiles"; then
            error "Malformed user-managed package row: $line"
            return 1
        fi
        if [[ "$provider" == aurelia ]]; then
            if [[ "$scope" != user ]] ||
                ! valid_user_managed_aurelia_metadata "$source" "$identifier" "$version" "$asset" "$checksum" "$target" "$artifact_url"; then
                error "Malformed Aurelia user-managed package row: $line"
                return 1
            fi
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$provider" "$source" "$identifier" "$scope" "$profiles" \
                "$version" "$asset" "$checksum" "$target" "$artifact_url"
        elif [[ -n "$version" || -n "$asset" || -n "$checksum" || -n "$target" || -n "$artifact_url" ]]; then
            error "Only Aurelia user-managed rows may contain pinned upstream metadata: $line"
            return 1
        else
            printf '%s\t%s\t%s\t%s\t%s\n' \
                "$provider" "$source" "$identifier" "$scope" "$profiles"
        fi
    done < "$manifest"
}

package_is_in_static_manifest() {
    local package="$1"
    local manifest
    local manifest_packages

    for manifest in "$SCRIPT_DIR"/packages/*.txt; do
        [[ -f "$manifest" ]] || continue
        if ! manifest_packages="$(read_package_manifest "$manifest")"; then
            return 1
        fi
        if grep -Fxq -- "$package" <<< "$manifest_packages"; then
            return 0
        fi
    done
    return 1
}

package_manifest_all_installed() {
    local manifest="$1"
    local package
    local manifest_packages

    if ! manifest_packages="$(read_package_manifest "$manifest")"; then
        return 1
    fi
    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        # Registry-owned package aliases are validated by their own
        # components and must not make the package group appear incomplete.
        is_component_migrated "$package" && continue
        package_installed "$package" || return 1
    done <<< "$manifest_packages"
}

detect_base_package_group() {
    package_manifest_all_installed "${SCRIPT_DIR:-$_PACKAGE_MODULE_ROOT}/packages/base.txt"
}

install_base_package_group() {
    install_manifest "${SCRIPT_DIR:-$_PACKAGE_MODULE_ROOT}/packages/base.txt"
}

detect_desktop_package_group() {
    package_manifest_all_installed "${SCRIPT_DIR:-$_PACKAGE_MODULE_ROOT}/packages/desktop.txt"
}

install_desktop_package_group() {
    install_manifest "${SCRIPT_DIR:-$_PACKAGE_MODULE_ROOT}/packages/desktop.txt"
}

AURELIA_QUICKSHELL_REPO_ID="copr:copr.fedorainfracloud.org:errornointernet:quickshell"

quickshell_package_is_stable() {
    local version
    local sorted_versions=()

    package_evr_is_stable quickshell || return 1
    version="$(rpm -q --qf '%{VERSION}' quickshell 2>/dev/null || true)"
    [[ -n "$version" ]] || return 1

    # Aurelia relies on the v0.3 API surface; Fedora's older 0.2.x package
    # must not silently satisfy the runtime requirement.
    mapfile -t sorted_versions < <(printf '0.3.0\n%s\n' "$version" | sort -V)
    [[ "${sorted_versions[0]:-}" == "0.3.0" ]]
}

detect_aurelia_package_group() {
    quickshell_package_is_stable || return 1
    package_installed inotify-tools
}

install_aurelia_package_group() {
    if package_installed quickshell; then
        quickshell_package_is_stable || {
            error "Installed Quickshell is prerelease, a development snapshot, or older than v0.3.0; refusing to adopt it for Aurelia."
            return 1
        }
        info "A stable supported Quickshell package is already installed."
    else
        if ! package_available_from_repo "$AURELIA_QUICKSHELL_REPO_ID" quickshell ||
            ! dnf_install_packages_from_repo "$AURELIA_QUICKSHELL_REPO_ID" quickshell; then
            return 1
        fi
    fi

    install_dnf_packages inotify-tools || return 1
    quickshell_package_is_stable && package_installed inotify-tools
}

detect_diagnostics_package_group() {
    package_manifest_all_installed "${SCRIPT_DIR:-$_PACKAGE_MODULE_ROOT}/packages/diagnostics.txt"
}

install_diagnostics_package_group() {
    install_manifest "${SCRIPT_DIR:-$_PACKAGE_MODULE_ROOT}/packages/diagnostics.txt"
}

detect_media_package_group() {
    package_manifest_all_installed "${SCRIPT_DIR:-$_PACKAGE_MODULE_ROOT}/packages/media.txt"
}

install_media_package_group() {
    install_manifest "${SCRIPT_DIR:-$_PACKAGE_MODULE_ROOT}/packages/media.txt"
}

validate_user_managed_manifest() {
    local rows_file
    local duplicate
    local provider
    local source
    local identifier
    local scope
    local profiles

    if ! rows_file="$(mktemp)"; then
        error "Could not create a secure temporary package-manifest validation file."
        return 1
    fi
    if ! read_user_managed_manifest > "$rows_file"; then
        rm -f -- "$rows_file"
        return 1
    fi
    duplicate="$(cut -f1-4 "$rows_file" | sort | uniq -d)"
    if [[ -n "$duplicate" ]]; then
        error "Duplicate user-managed package identity: $duplicate"
        rm -f -- "$rows_file"
        return 1
    fi
    while IFS=$'\t' read -r provider source identifier scope profiles; do
        if [[ "$provider" == dnf ]] &&
           { is_component_migrated "$identifier" || package_is_in_static_manifest "$identifier"; }; then
            error "User-managed package duplicates a repository-owned package: $identifier"
            rm -f -- "$rows_file"
            return 1
        fi
        if [[ "$provider" == flatpak &&
              ( "$identifier" == "org.localsend.localsend_app" || "$identifier" == "com.ulaa.Ulaa" ) ]]; then
            error "User-managed Flatpak duplicates a repository-owned application: $identifier"
            rm -f -- "$rows_file"
            return 1
        fi
    done < "$rows_file"
    rm -f -- "$rows_file"
    return 0
}

install_user_managed_dnf_packages() {
    local package_rows
    local provider
    local source
    local identifier
    local scope
    local profiles
    local available_status
    local failed=0

    validate_user_managed_manifest || {
        record_deferred "packages" "user-managed-manifest" "The user-managed package manifest is invalid."
        return 0
    }
    if ! package_rows="$(read_user_managed_manifest)"; then
        record_deferred "packages" "user-managed-manifest" "The user-managed package manifest could not be read."
        return 0
    fi
    while IFS=$'\t' read -r provider source identifier scope profiles; do
        [[ "$provider" == dnf ]] || continue
        if package_installed "$identifier"; then
            info "Tracked DNF package already installed: $identifier"
            continue
        fi
        available_status=0
        package_available_from_repo "$source" "$identifier" || available_status=$?
        if (( available_status != 0 )); then
            record_deferred "packages" "$identifier" "Tracked DNF package is unavailable from source '$source'."
            failed=1
            continue
        fi
        if ! dnf_install_packages_from_repo "$source" "$identifier"; then
            record_deferred "packages" "$identifier" "Tracked DNF package installation failed."
            failed=1
        fi
    done <<< "$package_rows"

    (( failed == 0 )) || return 0
    return 0
}

install_user_managed_aurelia_packages() {
    local backend="$SCRIPT_DIR/aurelia-shell/bin/workstation-packages"
    local rows
    local provider
    local source
    local identifier
    local scope
    local profiles
    local version
    local asset
    local checksum
    local target
    local artifact_url
    local has_aurelia=0

    validate_user_managed_manifest || {
        record_deferred "aurelia" "user-managed-manifest" "The user-managed package manifest is invalid."
        return 0
    }
    rows="$(read_user_managed_manifest)" || {
        record_deferred "aurelia" "user-managed-manifest" "The user-managed package manifest could not be read."
        return 0
    }
    while IFS=$'\t' read -r provider source identifier scope profiles version asset checksum target artifact_url; do
        if [[ "$provider" == aurelia ]]; then
            has_aurelia=1
            break
        fi
    done <<< "$rows"
    (( has_aurelia == 1 )) || return 0

    [[ -x "$backend" ]] || {
        record_deferred "aurelia" "backend" "The Aurelia package backend is unavailable."
        return 0
    }
    info "Restoring tracked Aurelia user-local binaries."
    if ! run_with_retry "restore tracked Aurelia packages" \
        run_with_timeout "$TIMEOUT_PACKAGE_SECONDS" "restore tracked Aurelia packages" \
        env WORKSTATION_PACKAGE_REPO="$SCRIPT_DIR" \
            WORKSTATION_PACKAGE_PROFILE="${PROFILE_NAME:-}" \
            "$backend" restore --aurelia; then
        record_deferred "aurelia" "restore" "One or more tracked Aurelia binaries could not be restored."
        return 0
    fi
    info "Tracked Aurelia binaries restored."
}

###############################################################################
# Package validation
###############################################################################

validate_manifest_packages() {
    local manifest="$1"
    local package
    local avail_status=0
    local manifest_packages

    info "Validating package manifest: $(basename "$manifest")"

    if ! manifest_packages="$(read_package_manifest "$manifest")"; then
        return 1
    fi

    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        if is_component_migrated "$package"; then
            continue
        fi

        if package_installed "$package"; then
            continue
        fi

        avail_status=0
        package_available "$package" || avail_status=$?

        if (( avail_status == 2 )); then
            error "Package repository query failed or timed out for: $package"
            return 1
        elif (( avail_status == 1 )); then
            error "Required package is not available in repositories: $package"
            return 1
        fi
    done <<< "$manifest_packages"

    return 0
}

###############################################################################
# Manifest installation
###############################################################################

install_manifest() {
    local manifest="$1"
    local packages=()
    local package
    local manifest_packages

    validate_manifest_packages "$manifest" || return 1

    if ! manifest_packages="$(read_package_manifest "$manifest")"; then
        return 1
    fi

    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        if is_component_migrated "$package"; then
            info "Package $package is owned by configuration reconciler; skipping in legacy manifest."
            continue
        fi
        packages+=("$package")
    done <<< "$manifest_packages"

    if [[ ${#packages[@]} -eq 0 ]]; then
        info "Package manifest contains only reconciler-owned or empty packages: $(basename "$manifest")"
        return 0
    fi

    install_dnf_packages "${packages[@]}"
}

install_bluetooth_packages() {
    local bluetooth_manifest="$SCRIPT_DIR/packages/bluetooth.txt"

    if ! is_true "${BLUETOOTH:-false}"; then
        info "Bluetooth disabled by profile; skipping Bluetooth packages."
        return 0
    fi

    info "Installing Bluetooth packages."
    if ! install_manifest "$bluetooth_manifest"; then
        record_required \
            "packages" \
            "bluetooth" \
            "Bluetooth packages could not be installed."
        return 1
    fi
}

###############################################################################
# Main entry point
###############################################################################

install_packages() {
    local base_manifest="$SCRIPT_DIR/packages/base.txt"
    local diagnostics_manifest="$SCRIPT_DIR/packages/diagnostics.txt"
    local desktop_manifest="$SCRIPT_DIR/packages/desktop.txt"
    local media_manifest="$SCRIPT_DIR/packages/media.txt"
    local failed=0

    info "Installing base workstation packages."
    if is_component_migrated "packages.base"; then
        info "Base package group is owned by configuration reconciler; skipping legacy stage."
    elif ! install_manifest "$base_manifest"; then
        record_required "packages" "base" "Base workstation packages could not be installed."
        failed=1
    fi

    info "Installing system diagnostics packages."
    if is_component_migrated "packages.diagnostics"; then
        info "Diagnostics package group is owned by configuration reconciler; skipping legacy stage."
    elif ! install_manifest "$diagnostics_manifest"; then
        record_required "packages" "diagnostics" "System diagnostics packages could not be installed."
        failed=1
    fi

    if [[ "${DESKTOP:-}" == "hyprland" ]]; then
        info "Installing Hyprland desktop packages."
        if is_component_migrated "packages.desktop"; then
            info "Desktop package group is owned by configuration reconciler; skipping legacy stage."
        elif ! install_manifest "$desktop_manifest"; then
            record_activation_failure \
                "packages" \
                "desktop" \
                "Hyprland desktop packages could not be installed."
            failed=1
        fi
    else
        die "Unsupported desktop profile: ${DESKTOP:-<unset>}"
    fi

    if ! install_bluetooth_packages; then
        failed=1
    fi

    info "Installing media packages."
    if is_component_migrated "packages.media"; then
        info "Media package group is owned by configuration reconciler; skipping legacy stage."
    elif ! install_manifest "$media_manifest"; then
        record_required "packages" "media" "Media packages could not be installed."
        failed=1
    fi

    info "Host package installation complete."
    if (( failed != 0 )); then
        return 1
    fi
    record_success "install_packages"
    return 0
}
