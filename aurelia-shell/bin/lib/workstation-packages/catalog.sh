#!/usr/bin/env bash

# Read-only package catalog refresh and search.
#
# Catalog rows are cache data, not desired state. A refresh never installs or
# removes packages; it replaces one generated cache atomically and records
# partial-source failures separately.

wsp_catalog_cache_age() {
    local now
    local modified

    [[ -f "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" ]] || {
        printf '%s\n' 999999999
        return 0
    }
    now="$(date +%s)"
    modified="$(stat -c '%Y' "$WSP_CATALOG_FILE" 2>/dev/null || printf '%s' 0)"
    if [[ "$modified" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ && "$now" -ge "$modified" ]]; then
        printf '%s\n' "$((now - modified))"
    else
        printf '%s\n' 999999999
    fi
}

wsp_catalog_paths_safe() {
    wsp_path_components_safe "$WSP_CACHE_DIR" || {
        wsp_error "Refusing an unsafe package catalog cache path: $WSP_CACHE_DIR"
        return 1
    }
    if [[ -e "$WSP_CACHE_DIR" && ! -d "$WSP_CACHE_DIR" ]]; then
        wsp_error "Package catalog cache path is not a directory: $WSP_CACHE_DIR"
        return 1
    fi
    if [[ ! -d "$WSP_CACHE_DIR" ]]; then
        mkdir -p -- "$WSP_CACHE_DIR" || return 1
    fi
    [[ ! -L "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_META" && ! -L "$WSP_CATALOG_ERRORS" ]] || {
        wsp_error "Refusing symlinked package catalog cache file."
        return 1
    }
}

wsp_catalog_stale() {
    local age
    age="$(wsp_catalog_cache_age)"
    [[ "$age" =~ ^[0-9]+$ && "$age" -ge 86400 ]]
}

wsp_catalog_has_provider() {
    local provider="$1"
    [[ -f "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" ]] &&
        awk -F '\t' -v p="$provider" '$1 == p { found=1 } END { exit(found ? 0 : 1) }' \
            "$WSP_CATALOG_FILE"
}

wsp_catalog_needs_refresh() {
    wsp_catalog_paths_safe || return 2
    [[ ! -s "$WSP_CATALOG_FILE" ]] && return 0
    wsp_catalog_stale && return 0

    # Version 1 of the catalog could silently drop DNF rows because DNF5's
    # query format did not include an explicit record newline. Invalidate such
    # a cache instead of presenting a Flatpak-only search surface.
    if command -v dnf5 >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
        wsp_catalog_has_provider dnf || return 0
    fi
    if declare -F wsp_aurelia_sources_rows >/dev/null 2>&1; then
        local aurelia_sources_file
        local aurelia_sources
        local catalog_mtime
        local sources_mtime

        aurelia_sources_file="$(wsp_aurelia_sources_path 2>/dev/null || true)"
        aurelia_sources="$(wsp_aurelia_sources_rows 2>/dev/null || true)"
        if [[ -n "$aurelia_sources" ]]; then
            wsp_catalog_has_provider aurelia || return 0
            while IFS=$'\t' read -r source _url _profiles; do
                [[ -n "$source" ]] || continue
                if ! awk -F '\t' -v s="$source" '$1 == "aurelia" && $2 == s { found=1 } END { exit(found ? 0 : 1) }' \
                    "$WSP_CATALOG_FILE"; then
                    return 0
                fi
            done <<< "$aurelia_sources"
            catalog_mtime="$(stat -c '%Y' "$WSP_CATALOG_FILE" 2>/dev/null || printf '%s' 0)"
            sources_mtime="$(stat -c '%Y' "$aurelia_sources_file" 2>/dev/null || printf '%s' 0)"
            if [[ "$sources_mtime" =~ ^[0-9]+$ && "$catalog_mtime" =~ ^[0-9]+$ &&
                  "$sources_mtime" -gt "$catalog_mtime" ]]; then
                return 0
            fi
        fi
    fi
    return 1
}

wsp_dnf_binary() {
    if command -v dnf5 >/dev/null 2>&1; then
        command -v dnf5
    elif command -v dnf >/dev/null 2>&1; then
        command -v dnf
    else
        return 1
    fi
}

wsp_catalog_refresh_dnf() {
    local dnf_bin
    local raw_file
    local err_file
    local line
    local name
    local summary
    local evr
    local source
    local arch
    local native_arch
    local status=0

    dnf_bin="$(wsp_dnf_binary)" || {
        printf '%s\n' 'DNF is unavailable.' >> "$WSP_REFRESH_ERRORS"
        return 1
    }
    native_arch="$(wsp_dnf_native_arch)" || {
        printf 'Unsupported host architecture for DNF catalog.\n' >> "$WSP_REFRESH_ERRORS"
        return 1
    }
    raw_file="$(mktemp 2>/dev/null)" || return 1
    err_file="$(mktemp 2>/dev/null)" || {
        rm -f -- "$raw_file"
        return 1
    }

    # Refresh metadata first, but keep the catalog useful if only this step
    # fails because another package-manager transaction owns the lock.
    if ! wsp_run_timeout 180 "$dnf_bin" -q makecache --refresh > /dev/null 2> "$err_file"; then
        printf 'dnf makecache: %s\n' "$(tr '\r\n' ' ' < "$err_file" | cut -c1-240)" >> "$WSP_REFRESH_ERRORS"
        status=1
    fi
    if ! wsp_run_timeout 180 "$dnf_bin" -q repoquery --available \
        --qf $'%{name}\t%{summary}\t%{evr}\t%{repoid}\t%{arch}\n' \
        > "$raw_file" 2> "$err_file"; then
        printf 'dnf repoquery: %s\n' "$(tr '\r\n' ' ' < "$err_file" | cut -c1-240)" >> "$WSP_REFRESH_ERRORS"
        rm -f -- "$raw_file" "$err_file"
        return 1
    fi

    while IFS=$'\t' read -r name summary evr source arch || [[ -n "$name" ]]; do
        [[ -n "$name" ]] || continue
        source="${source:-dnf}"
        arch="${arch:-unknown}"
        summary="${summary//$'\t'/ }"
        summary="${summary//$'\r'/ }"
        evr="${evr//$'\t'/ }"
        evr="${evr//$'\r'/ }"
        source="${source//$'\t'/ }"
        source="${source//$'\r'/ }"
        arch="${arch//$'\t'/ }"
        arch="${arch//$'\r'/ }"
        if [[ "$arch" == "$native_arch" || "$arch" == noarch ]] &&
            wsp_valid_source "$source" && wsp_valid_dnf_id "$name"; then
            printf 'dnf\t%s\t%s\t%s\t%s\t%s\tsystem\n' \
                "$source" "$name" "$name" "$summary" "$evr" >> "$WSP_CATALOG_ROWS"
        fi
    done < "$raw_file"

    rm -f -- "$raw_file" "$err_file"
    return "$status"
}

wsp_flatpak_remote_names() {
    local scope="$1"
    local output

    command -v flatpak >/dev/null 2>&1 || return 1
    output="$(wsp_run_timeout 45 flatpak remotes "--$scope" --columns=name 2>/dev/null)" || return 1
    while IFS= read -r source; do
        source="$(wsp_trim_line "$source")"
        [[ -n "$source" ]] || continue
        wsp_valid_source "$source" || continue
        printf '%s\n' "$source"
    done <<< "$output"
}

wsp_catalog_refresh_flatpak_scope() {
    local scope="$1"
    local source
    local raw_file
    local err_file
    local line
    local identifier
    local name
    local summary
    local version
    local branch
    local status=0

    command -v flatpak >/dev/null 2>&1 || {
        printf '%s\n' 'Flatpak is unavailable.' >> "$WSP_REFRESH_ERRORS"
        return 1
    }
    while IFS= read -r source; do
        [[ -n "$source" ]] || continue
        raw_file="$(mktemp 2>/dev/null)" || return 1
        err_file="$(mktemp 2>/dev/null)" || {
            rm -f -- "$raw_file"
            return 1
        }
        if ! wsp_run_timeout 120 flatpak remote-ls "--$scope" --app \
            --columns=application,name,description,version,branch "$source" \
            > "$raw_file" 2> "$err_file"; then
            printf 'flatpak/%s/%s: %s\n' "$scope" "$source" \
                "$(tr '\r\n' ' ' < "$err_file" | cut -c1-240)" >> "$WSP_REFRESH_ERRORS"
            status=1
            rm -f -- "$raw_file" "$err_file"
            continue
        fi

        while IFS=$'\t' read -r identifier name summary version branch || [[ -n "$identifier" ]]; do
            [[ -n "$identifier" ]] || continue
            wsp_valid_flatpak_id "$identifier" || continue
            name="${name:-$identifier}"
            name="${name//$'\t'/ }"
            name="${name//$'\r'/ }"
            summary="${summary//$'\t'/ }"
            summary="${summary//$'\r'/ }"
            version="${version//$'\t'/ }"
            version="${version//$'\r'/ }"
            branch="${branch//$'\t'/ }"
            branch="${branch//$'\r'/ }"
            if [[ -n "$branch" && "$branch" != "-" ]]; then
                version="${version:-unknown} @ ${branch}"
            fi
            printf 'flatpak\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$source" "$identifier" "$name" "$summary" "$version" "$scope" >> "$WSP_CATALOG_ROWS"
        done < "$raw_file"
        rm -f -- "$raw_file" "$err_file"
    done < <(wsp_flatpak_remote_names "$scope" || true)

    return "$status"
}

wsp_catalog_refresh() {
    local cache_dir="$WSP_CACHE_DIR"
    local temporary
    local status=0
    local dnf_status=0
    local flatpak_system_status=0
    local flatpak_user_status=0
    local aurelia_status=0

    wsp_catalog_paths_safe || return 1
    temporary="$(mktemp "$cache_dir/.catalog.XXXXXX" 2>/dev/null)" || return 1
    WSP_CATALOG_ROWS="$temporary"
    WSP_REFRESH_ERRORS="$(mktemp 2>/dev/null)" || {
        rm -f -- "$temporary"
        return 1
    }
    : > "$WSP_REFRESH_ERRORS"

    if [[ "${WSP_QUIET_REFRESH:-0}" != 1 ]]; then
        wsp_info "Refreshing Fedora package sources..."
    fi
    wsp_catalog_refresh_dnf || dnf_status=$?
    if [[ "${WSP_QUIET_REFRESH:-0}" != 1 ]]; then
        wsp_info "Refreshing Flatpak remotes..."
    fi
    wsp_catalog_refresh_flatpak_scope system || flatpak_system_status=$?
    wsp_catalog_refresh_flatpak_scope user || flatpak_user_status=$?
    if [[ "${WSP_QUIET_REFRESH:-0}" != 1 ]]; then
        wsp_info "Refreshing Aurelia GitHub release sources..."
    fi
    if declare -F wsp_aurelia_catalog_rows >/dev/null 2>&1; then
        wsp_aurelia_catalog_rows >> "$temporary" || aurelia_status=$?
    fi

    if (( dnf_status != 0 || flatpak_system_status != 0 || flatpak_user_status != 0 || aurelia_status != 0 )); then
        status=2
    fi
    if [[ ! -s "$temporary" ]]; then
        wsp_error "No package catalog entries were returned by any source."
        rm -f -- "$temporary" "$WSP_REFRESH_ERRORS"
        WSP_CATALOG_ROWS=""
        WSP_REFRESH_ERRORS=""
        return 1
    fi

    sort -u "$temporary" > "$temporary.sorted"
    if ! mv -f -- "$temporary.sorted" "$temporary"; then
        rm -f -- "$temporary" "$temporary.sorted" "$WSP_REFRESH_ERRORS"
        WSP_CATALOG_ROWS=""
        WSP_REFRESH_ERRORS=""
        return 1
    fi
    if ! wsp_atomic_replace "$WSP_CATALOG_FILE" "$temporary"; then
        rm -f -- "$temporary" "$WSP_REFRESH_ERRORS"
        WSP_CATALOG_ROWS=""
        WSP_REFRESH_ERRORS=""
        return 1
    fi
    rm -f -- "$temporary"

    [[ ! -L "$WSP_CATALOG_META.tmp" && ! -L "$WSP_CATALOG_META" ]] || {
        rm -f -- "$WSP_CATALOG_META.tmp" "$WSP_REFRESH_ERRORS"
        WSP_CATALOG_ROWS=""
        WSP_REFRESH_ERRORS=""
        wsp_error "Refusing symlinked package catalog metadata file."
        return 1
    }
    {
        printf 'schema=3\n'
        printf 'refreshed_at=%s\n' "$(date --iso-8601=seconds)"
        printf 'dnf_status=%s\n' "$dnf_status"
        printf 'flatpak_system_status=%s\n' "$flatpak_system_status"
        printf 'flatpak_user_status=%s\n' "$flatpak_user_status"
        printf 'aurelia_status=%s\n' "$aurelia_status"
        if [[ -s "$WSP_REFRESH_ERRORS" ]]; then
            printf 'errors=partial\n'
        else
            printf 'errors=none\n'
        fi
    } > "$WSP_CATALOG_META.tmp"
    if ! mv -f -- "$WSP_CATALOG_META.tmp" "$WSP_CATALOG_META"; then
        rm -f -- "$WSP_CATALOG_META.tmp" "$WSP_REFRESH_ERRORS"
        WSP_CATALOG_ROWS=""
        WSP_REFRESH_ERRORS=""
        return 1
    fi
    if [[ -s "$WSP_REFRESH_ERRORS" ]]; then
        mv -f -- "$WSP_REFRESH_ERRORS" "$WSP_CATALOG_ERRORS"
    else
        rm -f -- "$WSP_REFRESH_ERRORS" "$WSP_CATALOG_ERRORS"
    fi
    WSP_CATALOG_ROWS=""
    WSP_REFRESH_ERRORS=""

    if [[ "${WSP_QUIET_REFRESH:-0}" != 1 ]]; then
        if (( status == 2 )); then
            wsp_warn "Package catalog refresh completed with one or more source errors."
        else
            wsp_info "Package catalog refresh completed."
        fi
    fi
    return "$status"
}

wsp_catalog_ensure() {
    local acquired_lock=0
    local previous_quiet="${WSP_QUIET_REFRESH:-0}"

    wsp_catalog_paths_safe || return 1
    if wsp_catalog_needs_refresh; then
        if [[ -z "${WSP_LOCK_FD:-}" ]]; then
            wsp_lock_start || return 1
            acquired_lock=1
        fi
        if ! wsp_catalog_refresh; then
            if [[ ! -s "$WSP_CATALOG_FILE" ]]; then
                [[ "$acquired_lock" -eq 1 ]] && wsp_lock_stop
                return 1
            fi
            [[ "$previous_quiet" == 1 ]] || wsp_warn "Using the previous package catalog because refresh failed."
        fi
        [[ "$acquired_lock" -eq 1 ]] && wsp_lock_stop
    fi
}

wsp_catalog_rows() {
    wsp_catalog_paths_safe || return 1
    [[ -f "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" ]] || return 1
    cat -- "$WSP_CATALOG_FILE"
}

wsp_catalog_search() {
    local query="${1:-}"
    wsp_catalog_paths_safe || return 1
    [[ -f "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" ]] || return 0
    awk -F '\t' -v q="${query,,}" '
        BEGIN { OFS = "\t" }
        {
            hay = tolower($0)
            if (q == "" || index(hay, q) > 0) print
        }
    ' "$WSP_CATALOG_FILE"
}

wsp_catalog_info() {
    local provider="$1"
    local source="$2"
    local identifier="$3"

    wsp_catalog_paths_safe || return 1
    [[ -f "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" ]] || return 1
    awk -F '\t' -v p="$provider" -v s="$source" -v i="$identifier" '
        $1 == p && $2 == s && $3 == i {
            printf "Provider : %s\nSource   : %s\nID       : %s\nName     : %s\nSummary  : %s\nVersion  : %s\nScope    : %s\n", $1, $2, $3, $4, ($5 == "" ? "(none)" : $5), $6, $7
            if ($1 == "aurelia") {
                printf "Asset    : %s\nChecksum : %s\nTarget   : ~/%s\nURL      : %s\n", $8, $9, $10, $11
            }
            found = 1
        }
        END { exit(found ? 0 : 1) }
    ' "$WSP_CATALOG_FILE"
}

wsp_catalog_live_dnf_rows() {
    local dnf_bin
    local raw_file
    local native_arch

    dnf_bin="$(wsp_dnf_binary)" || return 1
    native_arch="$(wsp_dnf_native_arch)" || return 1
    raw_file="$(mktemp 2>/dev/null)" || return 1
    if ! wsp_run_timeout 90 "$dnf_bin" -C -q repoquery --available \
        --qf $'%{name}\t%{summary}\t%{evr}\t%{repoid}\t%{arch}\n' \
        > "$raw_file" 2>/dev/null; then
        rm -f -- "$raw_file"
        return 1
    fi
    awk -F '\t' -v native_arch="$native_arch" '
        function valid_source(value) {
            return value ~ /^[A-Za-z0-9][A-Za-z0-9_.:\/-]{0,127}$/
        }
        function valid_id(value) {
            return value ~ /^[A-Za-z0-9][A-Za-z0-9+._:-]{0,127}$/
        }
        NF >= 1 {
            name = $1
            summary = $2
            evr = $3
            source = ($4 == "" ? "dnf" : $4)
            arch = $5
            gsub(/\r/, " ", summary)
            gsub(/\r/, " ", evr)
            if ((arch == native_arch || arch == "noarch") && valid_source(source) && valid_id(name))
                printf "dnf\t%s\t%s\t%s\t%s\t%s\t%s\n", source, name, name, summary, evr, "system"
        }
    ' "$raw_file"
    rm -f -- "$raw_file"
}

wsp_catalog_live_flatpak_rows_for_scope() {
    local scope="$1"
    local source
    local raw_file
    local identifier
    local name
    local summary
    local version
    local branch

    command -v flatpak >/dev/null 2>&1 || return 1
    while IFS= read -r source; do
        [[ -n "$source" ]] || continue
        raw_file="$(mktemp 2>/dev/null)" || return 1
        if ! wsp_run_timeout 90 flatpak remote-ls "--$scope" --cached --app \
            --columns=application,name,description,version,branch "$source" \
            > "$raw_file" 2>/dev/null; then
            rm -f -- "$raw_file"
            continue
        fi
        while IFS=$'\t' read -r identifier name summary version branch || [[ -n "$identifier" ]]; do
            [[ -n "$identifier" ]] || continue
            wsp_valid_flatpak_id "$identifier" || continue
            name="${name:-$identifier}"
            name="${name//$'\t'/ }"
            name="${name//$'\r'/ }"
            summary="${summary//$'\t'/ }"
            summary="${summary//$'\r'/ }"
            version="${version//$'\t'/ }"
            version="${version//$'\r'/ }"
            branch="${branch//$'\t'/ }"
            branch="${branch//$'\r'/ }"
            if [[ -n "$branch" && "$branch" != "-" ]]; then
                version="${version:-unknown} @ ${branch}"
            fi
            printf 'flatpak\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$source" "$identifier" "$name" "$summary" "$version" "$scope"
        done < "$raw_file"
        rm -f -- "$raw_file"
    done < <(wsp_flatpak_remote_names "$scope" || true)
}

wsp_catalog_live_rows() {
    # Fedora's local DNF metadata is available without the session bus and is
    # normally the fastest complete source. Emit it first so the selector has
    # rows even when a Flatpak remote is slow or unavailable.
    wsp_catalog_live_dnf_rows || true
    wsp_catalog_live_flatpak_rows_for_scope system || true
    wsp_catalog_live_flatpak_rows_for_scope user || true
}

wsp_catalog_seed_aurelia_discovery() {
    local temporary
    local filtered

    [[ -n "${WSP_AURELIA_DISCOVERY_SOURCE:-}" &&
       -n "${WSP_AURELIA_DISCOVERY_IDENTIFIER:-}" ]] || return 1
    wsp_catalog_paths_safe || return 1
    temporary="$(mktemp "$WSP_CACHE_DIR/.catalog-seed.XXXXXX" 2>/dev/null)" || return 1
    filtered="$(mktemp "$WSP_CACHE_DIR/.catalog-seed-filtered.XXXXXX" 2>/dev/null)" || {
        rm -f -- "$temporary"
        return 1
    }
    if [[ -f "$WSP_CATALOG_FILE" ]] && ! cp -- "$WSP_CATALOG_FILE" "$temporary"; then
        rm -f -- "$temporary" "$filtered"
        return 1
    fi
    if [[ ! -f "$WSP_CATALOG_FILE" ]]; then
        : > "$temporary"
    fi
    awk -F '\t' \
        -v s="$WSP_AURELIA_DISCOVERY_SOURCE" \
        -v i="$WSP_AURELIA_DISCOVERY_IDENTIFIER" \
        '!(($1 == "aurelia") && ($2 == s) && ($3 == i))' \
        "$temporary" > "$filtered"
    printf 'aurelia\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$WSP_AURELIA_DISCOVERY_SOURCE" \
        "$WSP_AURELIA_DISCOVERY_IDENTIFIER" \
        "$WSP_AURELIA_DISCOVERY_NAME" \
        "$WSP_AURELIA_DISCOVERY_SUMMARY" \
        "$WSP_AURELIA_DISCOVERY_VERSION" \
        "$WSP_AURELIA_DISCOVERY_SCOPE" \
        "$WSP_AURELIA_DISCOVERY_ASSET" \
        "$WSP_AURELIA_DISCOVERY_CHECKSUM" \
        "$WSP_AURELIA_DISCOVERY_TARGET" \
        "$WSP_AURELIA_DISCOVERY_ARTIFACT_URL" >> "$filtered"
    sort -u "$filtered" > "$temporary"
    if ! wsp_atomic_replace "$WSP_CATALOG_FILE" "$temporary"; then
        rm -f -- "$temporary" "$filtered"
        return 1
    fi
    rm -f -- "$temporary" "$filtered"
}

wsp_catalog_rows_for_tui() {
    wsp_catalog_paths_safe || return 1
    if [[ -s "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" ]]; then
        cat -- "$WSP_CATALOG_FILE"
        if ! wsp_catalog_has_provider dnf &&
           ( command -v dnf5 >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1 ); then
            # Repair the old Flatpak-only cache in the foreground from local
            # metadata when possible; the network refresh still runs in the
            # background and atomically replaces the cache later.
            wsp_catalog_live_dnf_rows || true
        fi
        return 0
    fi
    wsp_catalog_live_rows
}
