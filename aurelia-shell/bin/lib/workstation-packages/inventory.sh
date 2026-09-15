#!/usr/bin/env bash

# Read-only installed-package inventory and ownership classification.

wsp_project_owned_dnf() {
    local identifier="$1"
    local manifest

    for manifest in "$WSP_REPO_ROOT"/packages/*.txt; do
        [[ -f "$manifest" && ! -L "$manifest" ]] || continue
        if awk -v target="$identifier" '
            /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
            {
                value = $0
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                if (value == target) found = 1
            }
            END { exit(found ? 0 : 1) }
        ' "$manifest"; then
            return 0
        fi
    done

    # These are component-owned packages that are intentionally not duplicated
    # into the user-managed manifest.
    case "$identifier" in
        chromium|firefox|brave-origin|chatgpt|cursor|kate|noctalia|nautilus|thunar|nix|nix-daemon|htop|neovim|foot)
            return 0
            ;;
    esac
    return 1
}

wsp_project_owned_flatpak() {
    case "$1" in
        org.localsend.localsend_app|com.ulaa.Ulaa) return 0 ;;
        *) return 1 ;;
    esac
}

wsp_dnf_installed_rows() {
    local dnf_bin
    local raw
    local repo
    local identifier
    local evr

    dnf_bin="$(wsp_dnf_binary)" || return 1
    raw="$(wsp_run_timeout "${WSP_CFG_DNF_RESOLVE_TIMEOUT:-30}" "$dnf_bin" -q repoquery --userinstalled \
        --qf $'%{from_repo}\t%{name}\t%{evr}\t%{arch}\n' )" || return 1
    while IFS=$'\t' read -r repo identifier evr _ || [[ -n "$identifier" ]]; do
        [[ -n "$identifier" ]] || continue
        repo="${repo:-unknown}"
        evr="${evr:-unknown}"
        printf 'dnf\t%s\t%s\tsystem\t%s\t%s\n' \
            "$repo" "$identifier" "$identifier" "$evr"
    done <<< "$raw"
    return 0
}

wsp_dnf_all_installed_rows() {
    local raw
    local repo
    local identifier
    local evr

    if command -v rpm >/dev/null &&
       raw="$(wsp_run_timeout "${WSP_CFG_DNF_RESOLVE_TIMEOUT:-30}" rpm -qa \
           --qf $'unknown\t%{NAME}\t%{EVR}\t%{ARCH}\n' )"; then
        :
    else
        local dnf_bin
        dnf_bin="$(wsp_dnf_binary)" || return 1
        raw="$(wsp_run_timeout "${WSP_CFG_DNF_RESOLVE_TIMEOUT:-30}" "$dnf_bin" -q repoquery --installed \
            --qf $'%{from_repo}\t%{name}\t%{evr}\t%{arch}\n' )" || return 1
    fi
    while IFS=$'\t' read -r repo identifier evr _ || [[ -n "$identifier" ]]; do
        [[ -n "$identifier" ]] || continue
        repo="${repo:-unknown}"
        evr="${evr:-unknown}"
        printf 'dnf\t%s\t%s\tsystem\t%s\t%s\n' \
            "$repo" "$identifier" "$identifier" "$evr"
    done <<< "$raw"
    return 0
}

wsp_flatpak_installed_rows_for_scope() {
    local scope="$1"
    local raw
    local identifier
    local origin
    local name
    local version
    local branch

    command -v flatpak >/dev/null || return 1
    raw="$(wsp_run_timeout "${WSP_CFG_FLATPAK_METADATA_TIMEOUT:-180}" flatpak list "--$scope" --app \
        --columns=application,origin,name,version,branch )" || return 1
    while IFS=$'\t' read -r identifier origin name version branch || [[ -n "$identifier" ]]; do
        [[ -n "$identifier" ]] || continue
        wsp_valid_flatpak_id "$identifier" || continue
        origin="${origin:-unknown}"
        name="${name:-$identifier}"
        version="${version:-unknown}"
        [[ -n "$branch" && "$branch" != "-" ]] && version="${version} @ ${branch}"
        printf 'flatpak\t%s\t%s\t%s\t%s\t%s\n' \
            "$origin" "$identifier" "$scope" "$name" "$version"
    done <<< "$raw"
    return 0
}

wsp_installed_rows_for_tui() {
    local scope
    local provider
    local source
    local identifier
    local package_scope
    local name
    local version
    local profiles
    local tracked_version
    local asset
    local checksum
    local target
    local artifact_url

    if wsp_dnf_all_installed_rows; then
        :
    else
        wsp_warn 'Complete DNF installed-package inventory is unavailable for the Package Manager TUI.'
    fi
    for scope in system user; do
        if wsp_flatpak_installed_rows_for_scope "$scope"; then
            :
        else
            wsp_warn "Flatpak installed-package inventory is unavailable for $scope scope in the Package Manager TUI."
        fi
    done
    while IFS=$'\t' read -r provider source identifier package_scope profiles tracked_version asset checksum target artifact_url; do
        [[ "$provider" == aurelia && -n "$identifier" ]] || continue
        if wsp_aurelia_entry_installed "$source" "$identifier" "${target:-.local/bin/$identifier}"; then
            printf 'aurelia\t%s\t%s\t%s\t%s\t%s\n' \
                "$source" "$identifier" "$package_scope" "$identifier" "${tracked_version:-unknown}"
        fi
    done < <(wsp_manifest_rows)
    # This is a best-effort read-only enrichment. Preserve rows from healthy
    # providers while routing partial-provider warnings to the TUI diagnostic
    # channel instead of replacing a usable catalog with an empty failure.
    return 0
}

wsp_inventory_rows() {
    local status=0

    if wsp_dnf_installed_rows; then
        :
    else
        wsp_warn 'DNF installed-package inventory is unavailable; status will be partial.'
        status=1
    fi
    if wsp_flatpak_installed_rows_for_scope system; then
        :
    else
        wsp_warn 'System Flatpak installed-package inventory is unavailable; status will be partial.'
        status=1
    fi
    if wsp_flatpak_installed_rows_for_scope user; then
        :
    else
        wsp_warn 'User Flatpak installed-package inventory is unavailable; status will be partial.'
        status=1
    fi
    return "$status"
}

wsp_entry_installed() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="$4"
    local installed

    case "$provider" in
        dnf)
            command -v rpm >/dev/null || return 1
            rpm -q "$identifier" >/dev/null
            ;;
        flatpak)
            command -v flatpak >/dev/null || return 1
            installed="$(wsp_run_timeout "${WSP_CFG_FLATPAK_METADATA_TIMEOUT:-180}" flatpak list "--$scope" --app --columns=application )" || return 1
            grep -Fxq -- "$identifier" <<< "$installed"
            ;;
        aurelia)
            local target_path
            target_path="$(wsp_aurelia_target_path "$identifier" )" || return 1
            wsp_aurelia_marker_matches_target "$identifier" "$target_path"
            ;;
        *) return 1 ;;
    esac
}

wsp_entry_origin() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="$4"
    local dnf_bin
    local origin
    local installed_rows
    local status

    case "$provider" in
        flatpak)
            if installed_rows="$(wsp_flatpak_installed_rows_for_scope "$scope")"; then
                :
            else
                status=$?
                wsp_warn "Could not determine the Flatpak origin for $identifier ($scope); status is partial (status $status)."
                printf '%s\n' unknown
                return 0
            fi
            while IFS=$'\t' read -r _origin _id _scope _name _version; do
                if [[ "$_id" == "$identifier" && "$_scope" == "$scope" ]]; then
                    printf '%s\n' "${_origin:-unknown}"
                    return 0
                fi
            done <<< "$installed_rows"
            printf '%s\n' unknown
            ;;
        dnf)
            dnf_bin="$(wsp_dnf_binary)" || {
                printf '%s\n' unknown
                return 0
            }
            if origin="$(wsp_run_timeout "${WSP_CFG_DNF_RESOLVE_TIMEOUT:-30}" "$dnf_bin" -q repoquery --installed \
                --qf $'%{from_repo}\n' "$identifier" | awk 'NF { print; exit }')"; then
                :
            else
                status=$?
                wsp_warn "Could not determine the DNF origin for $identifier; status is partial (status $status)."
                origin=''
            fi
            printf '%s\n' "${origin:-unknown}"
            ;;
        aurelia)
            local target_path
            if target_path="$(wsp_aurelia_target_path "$identifier")"; then
                :
            else
                status=$?
                wsp_warn "Could not resolve the Aurelia target for $identifier; status is partial (status $status)."
                target_path=''
            fi
            if [[ -n "$target_path" ]] && wsp_aurelia_marker_matches_target "$identifier" "$target_path"; then
                printf '%s\n' "$WSP_AURELIA_MARKER_SOURCE"
            else
                printf '%s\n' unknown
            fi
            ;;
        *) printf '%s\n' unknown ;;
    esac
}

wsp_manifest_contains_identity() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="$4"

    wsp_manifest_rows | awk -F '\t' -v p="$provider" -v s="$source" -v i="$identifier" -v c="$scope" \
        '$1 == p && $2 == s && $3 == i && $4 == c { found=1 } END { exit(found ? 0 : 1) }'
}

wsp_json_escape_stream() {
    jq -Rsc 'split("\n") | map(select(length > 0))'
}

wsp_status_json() {
    local entries_file
    local inventory_file
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
    local installed
    local origin
    local state
    local tracked_json
    local unmanaged_json
    local source_json
    local flatpak_source_json
    local aurelia_source_json

    command -v jq >/dev/null || {
        wsp_error "jq is required for package status JSON."
        return 1
    }
    entries_file="$(mktemp)"
    inventory_file="$(mktemp)"
    wsp_manifest_rows > "$entries_file" || {
        rm -f -- "$entries_file" "$inventory_file"
        return 1
    }
    local inventory_status=0
    if wsp_inventory_rows > "$inventory_file"; then
        :
    else
        inventory_status=$?
        wsp_warn "Package inventory completed with partial provider status $inventory_status."
    fi

    tracked_json='[]'
    while IFS=$'\t' read -r provider source identifier scope profiles version asset checksum target artifact_url; do
        [[ -n "$provider" ]] || continue
        installed=false
        if wsp_entry_installed "$provider" "$source" "$identifier" "$scope"; then
            installed=true
        fi
        origin="$(wsp_entry_origin "$provider" "$source" "$identifier" "$scope")"
        state="missing"
        if [[ "$installed" == true ]]; then
            if [[ "$origin" == "$source" || "$provider" == "flatpak" && "$origin" == "$source" ]]; then
                state="installed"
            elif [[ "$origin" == "unknown" ]]; then
                state="installed-origin-unknown"
            else
                state="installed-source-drift"
            fi
        fi
        tracked_json="$(jq -cn \
            --arg provider "$provider" --arg source "$source" --arg identifier "$identifier" \
            --arg scope "$scope" --arg profiles "$profiles" --arg origin "$origin" \
            --arg version "${version:-}" --arg asset "${asset:-}" \
            --arg checksum "${checksum:-}" --arg target "${target:-}" \
            --arg artifact_url "${artifact_url:-}" \
            --arg state "$state" --argjson installed "$installed" \
            --argjson existing "$tracked_json" \
            '$existing + [{provider:$provider,source:$source,identifier:$identifier,scope:$scope,profiles:$profiles,installed:$installed,origin:$origin,state:$state,version:$version,asset:$asset,checksum:$checksum,target:$target,artifact_url:$artifact_url}]')"
    done < "$entries_file"

    unmanaged_json='[]'
    while IFS=$'\t' read -r provider source identifier scope name version; do
        [[ -n "$identifier" ]] || continue
        if wsp_manifest_contains_identity "$provider" "$source" "$identifier" "$scope"; then
            continue
        fi
        if [[ "$provider" == dnf ]] && wsp_project_owned_dnf "$identifier"; then
            continue
        fi
        if [[ "$provider" == flatpak ]] && wsp_project_owned_flatpak "$identifier"; then
            continue
        fi
        unmanaged_json="$(jq -cn \
            --arg provider "$provider" --arg source "$source" --arg identifier "$identifier" \
            --arg scope "$scope" --arg name "$name" --arg version "$version" \
            --argjson existing "$unmanaged_json" \
            '$existing + [{provider:$provider,source:$source,identifier:$identifier,scope:$scope,name:$name,version:$version,state:"unmanaged"}]')"
    done < "$inventory_file"

    flatpak_source_json="$(wsp_sources_rows | jq -Rsc '
        split("\n") | map(select(length > 0) | split("\t") |
            {provider: .[0], source: .[1], url: .[2], scope: .[3]})
    ')"
    aurelia_source_json="$(wsp_aurelia_sources_rows | jq -Rsc '
        split("\n") | map(select(length > 0) | split("\t") |
            {provider: "aurelia", source: .[0], url: .[1], profiles: .[2], scope: "user"})
    ')"
    source_json="$(jq -cn --argjson flatpak "$flatpak_source_json" --argjson aurelia "$aurelia_source_json" '$flatpak + $aurelia')"
    jq -cn \
        --arg manifest "$WSP_MANIFEST" \
        --arg catalog "$WSP_CATALOG_FILE" \
        --argjson inventory_status "$inventory_status" \
        --argjson tracked "$tracked_json" \
        --argjson unmanaged "$unmanaged_json" \
        --argjson sources "$source_json" \
        --argjson catalog_age "$(wsp_catalog_cache_age)" \
        '{schema:1,manifest:$manifest,catalog:$catalog,catalog_age_seconds:$catalog_age,inventory_status:$inventory_status,tracked:$tracked,unmanaged:$unmanaged,sources:$sources}'

    rm -f -- "$entries_file" "$inventory_file"
}

wsp_status_text() {
    local catalog_age

    catalog_age="$(wsp_catalog_human_age "$(wsp_catalog_cache_age)")"
    wsp_status_json | jq -r --arg age "$catalog_age" '
        "Tracked packages:",
        (if (.tracked | length) == 0 then "  (none)" else
            (.tracked[] | "  [" + .state + "] " + .provider + "/" + .source + "/" + .identifier + " (" + .scope + ")")
         end),
        "Unmanaged user-installed packages:",
        (if (.unmanaged | length) == 0 then "  (none)" else
            (.unmanaged[] | "  [unmanaged] " + .provider + "/" + .source + "/" + .identifier + " (" + .scope + ")")
         end),
        "Catalog age: " + $age
    '
}
