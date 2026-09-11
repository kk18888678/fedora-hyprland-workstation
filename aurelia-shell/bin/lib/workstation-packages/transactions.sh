#!/usr/bin/env bash

# Package mutations. The TUI and CLI call these functions; they never build a
# shell command from untrusted display text and always preserve provider and
# source as separate argv elements.

wsp_is_project_owned() {
    local provider="$1"
    local identifier="$2"

    case "$provider" in
        dnf) wsp_project_owned_dnf "$identifier" ;;
        flatpak) wsp_project_owned_flatpak "$identifier" ;;
        aurelia) return 1 ;;
        *) return 1 ;;
    esac
}

wsp_require_source_available() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="$4"
    local dnf_bin
    local output
    local native_arch
    local status=0

    case "$provider" in
        dnf)
            dnf_bin="$(wsp_dnf_binary)" || {
                wsp_error "DNF is unavailable."
                return 1
            }
            native_arch="$(wsp_dnf_native_arch)" || {
                wsp_error "Unsupported host architecture for DNF package installation."
                return 1
            }
            output="$(wsp_run_timeout 90 "$dnf_bin" -q repoquery --available \
                --repoid "$source" --qf $'%{name}\t%{arch}\n' "$identifier" 2>/dev/null)" || status=$?
            if (( status != 0 )); then
                if (( status == 124 )); then
                    wsp_error "DNF package availability query timed out for '$identifier' from '$source'."
                else
                    wsp_error "DNF package availability query failed for '$identifier' from '$source' (status $status)."
                fi
                return 1
            fi
            awk -F '\t' -v p="$identifier" -v a="$native_arch" \
                '$1 == p && ($2 == a || $2 == "noarch") { found=1 } END { exit(found ? 0 : 1) }' <<< "$output" || {
                wsp_error "Package '$identifier' is not available from enabled DNF source '$source'."
                return 1
            }
            ;;
        flatpak)
            command -v flatpak >/dev/null 2>&1 || {
                wsp_error "Flatpak is unavailable."
                return 1
            }
            local flatpak_remotes
            flatpak_remotes="$(wsp_run_timeout 60 flatpak remotes "--$scope" --columns=name 2>/dev/null)" || {
                wsp_error "Could not enumerate Flatpak sources for $scope scope within the timeout."
                return 1
            }
            grep -Fxq -- "$source" <<< "$flatpak_remotes" || {
                wsp_error "Flatpak source '$source' is not configured for $scope scope."
                return 1
            }
            ;;
        aurelia)
            [[ "$scope" == user ]] || {
                wsp_error "Aurelia packages use user scope."
                return 1
            }
            wsp_aurelia_source_url_for "$source" >/dev/null 2>&1 || {
                wsp_error "Aurelia source '$source' is not tracked. Add the GitHub source before installing packages from it."
                return 1
            }
            ;;
        *)
            wsp_error "Unknown package provider: $provider"
            return 1
            ;;
    esac
}

wsp_install_row() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="$4"
    local version="${5:-}"
    local asset="${6:-}"
    local checksum="${7:-}"
    local target="${8:-}"
    local artifact_url="${9:-}"
    local status=0
    local dnf_bin=""
    local install_identifier=""
    local -a command_argv=()

    wsp_validate_record "$provider" "$source" "$identifier" "$scope" all || {
        wsp_error "Invalid install record: $provider/$source/$identifier/$scope"
        return 1
    }
    if wsp_is_project_owned "$provider" "$identifier"; then
        wsp_error "Refusing to duplicate project-owned package in user-managed state: $identifier"
        return 1
    fi
    wsp_require_source_available "$provider" "$source" "$identifier" "$scope" || return 1

    case "$provider" in
        dnf)
            dnf_bin="$(wsp_dnf_binary)" || return 1
            install_identifier="$(wsp_dnf_install_identifier "$identifier")" || {
                wsp_error "Unsupported host architecture for DNF package installation."
                return 1
            }
            if [[ "$EUID" -eq 0 ]]; then
                command_argv=("$dnf_bin" install "--from-repo=$source" -y "$install_identifier")
            else
                command_argv=(sudo "$dnf_bin" install "--from-repo=$source" -y "$install_identifier")
            fi
            wsp_info "Installing DNF package $identifier from $source."
            wsp_run_timeout 1800 "${command_argv[@]}" || status=$?
            ;;
        flatpak)
            if [[ "$scope" == system ]]; then
                command_argv=(sudo flatpak install -y --system "$source" "$identifier")
            else
                command_argv=(flatpak install -y --user "$source" "$identifier")
            fi
            wsp_info "Installing Flatpak $identifier from $source ($scope)."
            wsp_run_timeout 1800 "${command_argv[@]}" || status=$?
            ;;
        aurelia)
            if ! wsp_aurelia_resolve_record "$source" "$identifier" "$version" "$asset" "$checksum" "$target" "$artifact_url"; then
                wsp_error "${WSP_AURELIA_LAST_ERROR:-Could not resolve Aurelia release metadata for $source/$identifier.}"
                return 1
            fi
            version="$WSP_AURELIA_DISCOVERY_VERSION"
            asset="$WSP_AURELIA_DISCOVERY_ASSET"
            checksum="$WSP_AURELIA_DISCOVERY_CHECKSUM"
            target="$WSP_AURELIA_DISCOVERY_TARGET"
            artifact_url="$WSP_AURELIA_DISCOVERY_ARTIFACT_URL"
            wsp_aurelia_install_record "$source" "$identifier" "$version" "$asset" "$checksum" "$target" "$artifact_url" || status=$?
            ;;
    esac
    if (( status != 0 )); then
        wsp_error "Package installation failed: $provider/$source/$identifier (status $status)."
        if [[ "$provider" == dnf ]]; then
            wsp_error "The selected DNF source may provide an older package set than the installed system; try the same package from its newer repository row (for example updates)."
        fi
        return "$status"
    fi
    if [[ "$provider" == aurelia ]]; then
        if ! wsp_aurelia_entry_installed "$source" "$identifier" "$target"; then
            wsp_error "Package was not present after installation: $provider/$source/$identifier"
            return 1
        fi
    elif ! wsp_entry_installed "$provider" "$source" "$identifier" "$scope"; then
        wsp_error "Package was not present after installation: $provider/$source/$identifier"
        return 1
    fi
}

wsp_remove_row() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="$4"
    local target="${5:-.local/bin/$identifier}"
    local status=0
    local dnf_bin=""
    local -a command_argv=()

    wsp_validate_record "$provider" "$source" "$identifier" "$scope" all || {
        wsp_error "Invalid removal record: $provider/$source/$identifier/$scope"
        return 1
    }
    if wsp_is_project_owned "$provider" "$identifier"; then
        wsp_error "Refusing to remove project-owned package from the package manager: $identifier"
        return 1
    fi
    if [[ "$provider" == aurelia ]]; then
        wsp_aurelia_remove_record "$source" "$identifier" "$target"
        return $?
    fi
    if ! wsp_entry_installed "$provider" "$source" "$identifier" "$scope"; then
        wsp_info "Package is already absent: $provider/$source/$identifier"
        return 0
    fi

    case "$provider" in
        dnf)
            dnf_bin="$(wsp_dnf_binary)" || return 1
            if [[ "$EUID" -eq 0 ]]; then
                command_argv=("$dnf_bin" remove -y "$identifier")
            else
                command_argv=(sudo "$dnf_bin" remove -y "$identifier")
            fi
            wsp_info "Removing DNF package $identifier."
            wsp_run_timeout 1800 "${command_argv[@]}" || status=$?
            ;;
        flatpak)
            if [[ "$scope" == system ]]; then
                command_argv=(sudo flatpak uninstall -y --system "$identifier")
            else
                command_argv=(flatpak uninstall -y --user "$identifier")
            fi
            wsp_info "Removing Flatpak $identifier ($scope). Personal Flatpak data is preserved."
            wsp_run_timeout 1800 "${command_argv[@]}" || status=$?
            ;;
    esac
    if (( status != 0 )); then
        wsp_error "Package removal failed: $provider/$source/$identifier (status $status)."
        return "$status"
    fi
    if wsp_entry_installed "$provider" "$source" "$identifier" "$scope"; then
        wsp_error "Package remained installed after removal: $provider/$source/$identifier"
        return 1
    fi
}

wsp_adopt_row() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="$4"
    local version="${5:-}"
    local asset="${6:-}"
    local checksum="${7:-}"
    local target="${8:-}"
    local artifact_url="${9:-}"

    wsp_validate_record "$provider" "$source" "$identifier" "$scope" all || {
        wsp_error "Invalid adoption record: $provider/$source/$identifier/$scope"
        return 1
    }
    if wsp_is_project_owned "$provider" "$identifier"; then
        wsp_error "Package is already project-owned and must not be duplicated: $identifier"
        return 1
    fi
    if [[ "$provider" == aurelia ]]; then
        wsp_require_source_available "$provider" "$source" "$identifier" "$scope" || return 1
        if ! wsp_aurelia_resolve_record "$source" "$identifier" "$version" "$asset" "$checksum" "$target" "$artifact_url"; then
            wsp_error "${WSP_AURELIA_LAST_ERROR:-Could not resolve Aurelia release metadata for $source/$identifier.}"
            return 1
        fi
        version="$WSP_AURELIA_DISCOVERY_VERSION"
        asset="$WSP_AURELIA_DISCOVERY_ASSET"
        checksum="$WSP_AURELIA_DISCOVERY_CHECKSUM"
        target="$WSP_AURELIA_DISCOVERY_TARGET"
        artifact_url="$WSP_AURELIA_DISCOVERY_ARTIFACT_URL"
        wsp_aurelia_adopt_record "$source" "$identifier" "$version" "$asset" "$checksum" "$target" "$artifact_url" || return 1
        wsp_manifest_add "$provider" "$source" "$identifier" "$scope" all \
            "$version" "$asset" "$checksum" "$target" "$artifact_url"
        return $?
    fi
    wsp_entry_installed "$provider" "$source" "$identifier" "$scope" || {
        wsp_error "Cannot adopt a package that is not installed: $provider/$source/$identifier"
        return 1
    }
    wsp_manifest_add "$provider" "$source" "$identifier" "$scope" all
}

wsp_install_and_track_row() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="$4"
    local version="${5:-}"
    local asset="${6:-}"
    local checksum="${7:-}"
    local target="${8:-}"
    local artifact_url="${9:-}"

    if [[ "$provider" == aurelia ]]; then
        if ! wsp_aurelia_resolve_record "$source" "$identifier" "$version" "$asset" "$checksum" "$target" "$artifact_url"; then
            wsp_error "${WSP_AURELIA_LAST_ERROR:-Could not resolve Aurelia release metadata for $source/$identifier.}"
            return 1
        fi
        version="$WSP_AURELIA_DISCOVERY_VERSION"
        asset="$WSP_AURELIA_DISCOVERY_ASSET"
        checksum="$WSP_AURELIA_DISCOVERY_CHECKSUM"
        target="$WSP_AURELIA_DISCOVERY_TARGET"
        artifact_url="$WSP_AURELIA_DISCOVERY_ARTIFACT_URL"
    fi
    wsp_install_row "$provider" "$source" "$identifier" "$scope" \
        "$version" "$asset" "$checksum" "$target" "$artifact_url" || return 1
    if ! wsp_manifest_add "$provider" "$source" "$identifier" "$scope" all \
        "$version" "$asset" "$checksum" "$target" "$artifact_url"; then
        wsp_error "Package is installed but could not be added to user-managed.tsv: $identifier"
        return 1
    fi
}

wsp_remove_and_forget_row() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="$4"
    local profiles="${5:-all}"

    wsp_remove_row "$provider" "$source" "$identifier" "$scope" || return 1
    wsp_manifest_remove "$provider" "$source" "$identifier" "$scope" "$profiles"
}
