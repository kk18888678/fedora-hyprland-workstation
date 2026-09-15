#!/usr/bin/env bash

# Read-only package catalog refresh and search.
#
# Catalog rows are cache data, not desired state. A refresh never installs or
# removes packages; it replaces one generated cache atomically and records
# partial-source failures separately.

# Catalog schema 6 keeps the original identity columns first so older callers
# can still identify a package. Columns 8-11 are reserved for Aurelia's pinned
# release metadata; columns 12 onward contain provider metadata. All values
# are flattened to one line before publication so descriptions and capability
# lists cannot corrupt the TSV record boundary.
WSP_CATALOG_SCHEMA_CURRENT=6
WSP_CATALOG_FIELD_SEPARATOR=$'\x1f'
WSP_CATALOG_RECORD_SEPARATOR=$'\x1e'
WSP_CATALOG_INDEX_SEPARATOR=$'\x1d'

wsp_catalog_progress() {
    printf 'INFO: %s\n' "$*" >&2
}

wsp_catalog_meta_value() {
    local key="$1"

    [[ -f "$WSP_CATALOG_META" && ! -L "$WSP_CATALOG_META" ]] || return 1
    awk -F '=' -v wanted="$key" '$1 == wanted { print substr($0, index($0, "=") + 1); exit }' \
        "$WSP_CATALOG_META"
}

wsp_catalog_schema() {
    local schema

    if schema="$(wsp_catalog_meta_value schema)"; then
        :
    else
        schema=''
    fi
    [[ "$schema" =~ ^[0-9]+$ ]] || schema=0
    printf '%s\n' "$schema"
}

wsp_catalog_human_age() {
    local seconds="${1:-}"
    local days
    local hours
    local minutes

    [[ "$seconds" =~ ^[0-9]+$ ]] || {
        printf '%s\n' 'unknown age'
        return 0
    }
    if (( seconds >= 999999999 )); then
        printf '%s\n' 'unavailable'
    elif (( seconds < 60 )); then
        printf '%ss\n' "$seconds"
    elif (( seconds < 3600 )); then
        minutes=$((seconds / 60))
        seconds=$((seconds % 60))
        printf '%sm %ss\n' "$minutes" "$seconds"
    elif (( seconds < 86400 )); then
        hours=$((seconds / 3600))
        minutes=$(((seconds % 3600) / 60))
        printf '%sh %sm\n' "$hours" "$minutes"
    else
        days=$((seconds / 86400))
        hours=$(((seconds % 86400) / 3600))
        printf '%sd %sh\n' "$days" "$hours"
    fi
}

wsp_catalog_cache_summary() {
    local age
    local schema
    local errors
    local freshness
    local rows='unknown'
    local dnf_rows='unknown'
    local flatpak_rows='unknown'
    local aurelia_rows='unknown'

    if [[ ! -s "$WSP_CATALOG_FILE" || -L "$WSP_CATALOG_FILE" ]]; then
        printf '%s\n' 'Catalog unavailable'
        return 0
    fi
    age="$(wsp_catalog_cache_age)"
    schema="$(wsp_catalog_schema)"
    if rows="$(wsp_catalog_meta_value rows)"; then :; fi
    if dnf_rows="$(wsp_catalog_meta_value dnf_rows)"; then :; fi
    if flatpak_rows="$(wsp_catalog_meta_value flatpak_rows)"; then :; fi
    if aurelia_rows="$(wsp_catalog_meta_value aurelia_rows)"; then :; fi
    if errors="$(wsp_catalog_meta_value errors)"; then
        :
    else
        errors='unknown'
    fi
    freshness='fresh'
    if [[ "$schema" =~ ^[0-9]+$ && "$schema" -lt "$WSP_CATALOG_SCHEMA_CURRENT" ]]; then
        freshness='upgrade-needed'
    fi
    if [[ "$age" =~ ^[0-9]+$ && "$age" -ge "${WSP_CFG_CATALOG_STALE_SECONDS:-21600}" ]]; then
        freshness='stale'
    fi
    case "$errors" in
        none) errors='healthy' ;;
        partial) errors='partial' ;;
        *) errors='unknown' ;;
    esac
    printf 'Catalog: %s old · %s · schema %s · sources %s\n' \
        "$(wsp_catalog_human_age "$age")" "$freshness" "$schema" "$errors"
    printf 'Packages: %s total · DNF %s · Flatpak %s · Aurelia %s\n' \
        "$rows" "$dnf_rows" "$flatpak_rows" "$aurelia_rows"
}

wsp_catalog_status_text() {
    local key
    local value

    wsp_catalog_cache_summary
    if [[ -f "$WSP_CATALOG_META" && ! -L "$WSP_CATALOG_META" ]]; then
        for key in refreshed_at rows dnf_rows flatpak_rows aurelia_rows metadata \
            dnf_status flatpak_system_status flatpak_user_status aurelia_status errors; do
            if value="$(wsp_catalog_meta_value "$key")"; then
                :
            else
                value=''
            fi
            [[ -n "$value" ]] && printf '%-22s %s\n' "$key" "$value"
        done
    fi
    if [[ -s "$WSP_CATALOG_ERRORS" && ! -L "$WSP_CATALOG_ERRORS" ]]; then
        printf '\nRecent source diagnostics:\n'
        sed -n '1,20p' "$WSP_CATALOG_ERRORS"
    fi
    if wsp_catalog_derived_ready; then
        printf 'search_index          ready\n'
    else
        printf 'search_index          not-ready (will rebuild before interactive search)\n'
    fi
}

wsp_catalog_cache_age() {
    local now
    local modified

    [[ -f "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" ]] || {
        printf '%s\n' 999999999
        return 0
    }
    now="$(date +%s)" || {
        wsp_error 'Could not read the current time while checking package catalog age.'
        printf '%s\n' 999999999
        return 0
    }
    if modified="$(stat -c '%Y' "$WSP_CATALOG_FILE")"; then
        :
    else
        wsp_error "Could not read the package catalog modification time: $WSP_CATALOG_FILE"
        modified=0
    fi
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
    [[ ! -L "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_META" &&
       ! -L "$WSP_CATALOG_ERRORS" && ! -L "$WSP_CATALOG_DISPLAY_FILE" &&
       ! -L "$WSP_CATALOG_INDEX_FILE" ]] || {
        wsp_error "Refusing symlinked package catalog cache file."
        return 1
    }
}

wsp_catalog_build_derived_indexes() {
    local source_file="$1"
    local display_tmp
    local index_tmp

    [[ -f "$source_file" && ! -L "$source_file" ]] || {
        wsp_error "Cannot build package catalog indexes from a missing or symlinked source: $source_file"
        return 1
    }
    display_tmp="$(mktemp "$WSP_CACHE_DIR/.catalog-display.XXXXXX")" || return 1
    index_tmp="$(mktemp "$WSP_CACHE_DIR/.catalog-index.XXXXXX")" || {
        rm -f -- "$display_tmp"
        return 1
    }
    if ! awk -F '\t' -v OFS='\t' \
        -v separator="$WSP_CATALOG_INDEX_SEPARATOR" \
        -v display_file="$display_tmp" -v index_file="$index_tmp" '
        function compact(value) {
            value = tolower(value)
            gsub(/[^[:alnum:]]/, "", value)
            return value
        }
        function spaced(value) {
            value = tolower(value)
            gsub(/[^[:alnum:]]+/, " ", value)
            sub(/^ +/, "", value)
            sub(/ +$/, "", value)
            return value
        }
        function human_size(value, number, unit) {
            if (value == "" || value == "-" || value == "0") return "n/a"
            if (value !~ /^[0-9]+$/) return value
            number = value + 0
            unit = "B"
            if (number >= 1024) { number /= 1024; unit = "KiB" }
            if (number >= 1024) { number /= 1024; unit = "MiB" }
            if (number >= 1024) { number /= 1024; unit = "GiB" }
            if (number >= 1024) { number /= 1024; unit = "TiB" }
            return sprintf("%.1f %s", number, unit)
        }
        function human_date(value) {
            if (value ~ /^[0-9]+$/ && value > 0) return strftime("%Y-%m-%d", value)
            return "-"
        }
        {
            if ($3 == "") next
            name = ($4 == "" ? $3 : $4)
            if (name == $3) name = "-"
            version = ($6 == "" ? "unknown" : $6)
            scope = ($7 == "" ? "system" : $7)
            arch = ($12 == "" ? "unknown" : $12)
            summary = ($5 == "" ? "(no summary)" : $5)
            print $1, $2, $3, name, version, scope, arch, human_size($13), human_size($14), "catalog", human_date($31), summary > display_file

            compact_fields = compact($1) separator compact($2) separator compact($3) separator compact($4) separator compact($5) separator compact($12) separator compact($13) separator compact($14) separator compact($15) separator compact($16) separator compact($17) separator compact($18) separator compact($27) separator compact($28) separator compact($30) separator compact($31)
            spaced_fields = spaced($1) separator spaced($2) separator spaced($3) separator spaced($4) separator spaced($5) separator spaced($12) separator spaced($13) separator spaced($14) separator spaced($15) separator spaced($16) separator spaced($17) separator spaced($18) separator spaced($27) separator spaced($28) separator spaced($30) separator spaced($31)
            print FNR, compact_fields, spaced_fields, compact($19), $31, compact($6) > index_file
        }
        END {
            close(display_file)
            close(index_file)
        }
    ' "$source_file"; then
        rm -f -- "$display_tmp" "$index_tmp"
        wsp_error "Could not build the local package catalog display/search indexes."
        return 1
    fi
    WSP_CATALOG_DISPLAY_STAGED="$display_tmp"
    WSP_CATALOG_INDEX_STAGED="$index_tmp"
}

wsp_catalog_publish_derived_indexes() {
    local display_staged="${WSP_CATALOG_DISPLAY_STAGED:-}"
    local index_staged="${WSP_CATALOG_INDEX_STAGED:-}"

    [[ -f "$display_staged" && ! -L "$display_staged" &&
       -f "$index_staged" && ! -L "$index_staged" ]] || {
        wsp_error 'Package catalog derived indexes are missing before publication.'
        return 1
    }
    [[ ! -L "$WSP_CATALOG_DISPLAY_FILE" && ! -L "$WSP_CATALOG_INDEX_FILE" ]] || {
        wsp_error 'Refusing to replace symlinked package catalog derived indexes.'
        return 1
    }
    if ! mv -f -- "$display_staged" "$WSP_CATALOG_DISPLAY_FILE"; then
        wsp_error "Could not publish the package catalog display index: $WSP_CATALOG_DISPLAY_FILE"
        return 1
    fi
    WSP_CATALOG_DISPLAY_STAGED=''
    if ! mv -f -- "$index_staged" "$WSP_CATALOG_INDEX_FILE"; then
        wsp_error "Could not publish the package catalog search index: $WSP_CATALOG_INDEX_FILE"
        return 1
    fi
    WSP_CATALOG_INDEX_STAGED=''
}

wsp_catalog_derived_ready() {
    local catalog_rows
    local display_rows
    local index_rows
    local catalog_mtime
    local display_mtime
    local index_mtime

    [[ -f "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" &&
       -f "$WSP_CATALOG_DISPLAY_FILE" && ! -L "$WSP_CATALOG_DISPLAY_FILE" &&
       -f "$WSP_CATALOG_INDEX_FILE" && ! -L "$WSP_CATALOG_INDEX_FILE" ]] || return 1
    if catalog_rows="$(wc -l < "$WSP_CATALOG_FILE")" &&
       display_rows="$(wc -l < "$WSP_CATALOG_DISPLAY_FILE")" &&
       index_rows="$(wc -l < "$WSP_CATALOG_INDEX_FILE")"; then
        :
    else
        wsp_error 'Could not count package catalog files while validating the local search index.'
        return 1
    fi
    [[ "$catalog_rows" == "$display_rows" && "$catalog_rows" == "$index_rows" ]] || return 1
    if ! awk -F '\t' 'NF != 12 || $3 == $4 { invalid=1; exit } END { exit(invalid ? 1 : 0) }' \
        "$WSP_CATALOG_DISPLAY_FILE"; then
        return 1
    fi
    if ! awk -F '\t' 'NF != 6 { invalid=1; exit } END { exit(invalid ? 1 : 0) }' \
        "$WSP_CATALOG_INDEX_FILE"; then
        return 1
    fi
    if catalog_mtime="$(stat -c '%Y' "$WSP_CATALOG_FILE")" &&
       display_mtime="$(stat -c '%Y' "$WSP_CATALOG_DISPLAY_FILE")" &&
       index_mtime="$(stat -c '%Y' "$WSP_CATALOG_INDEX_FILE")"; then
        :
    else
        wsp_error 'Could not read package catalog index timestamps.'
        return 1
    fi
    [[ "$display_mtime" -ge "$catalog_mtime" && "$index_mtime" -ge "$catalog_mtime" ]]
}

wsp_catalog_ensure_derived_indexes() {
    local acquired_lock=0
    local status=0

    wsp_catalog_paths_safe || return 1
    [[ -s "$WSP_CATALOG_FILE" ]] || {
        wsp_error 'Cannot build package catalog indexes without a published catalog.'
        return 1
    }
    wsp_catalog_derived_ready && return 0
    wsp_catalog_progress 'Preparing the local package search index from cached metadata...'
    if [[ -z "${WSP_LOCK_FD:-}" ]]; then
        wsp_lock_start || return 1
        acquired_lock=1
    fi
    if wsp_catalog_derived_ready; then
        :
    elif wsp_catalog_build_derived_indexes "$WSP_CATALOG_FILE" &&
         wsp_catalog_publish_derived_indexes; then
        :
    else
        status=$?
    fi
    if (( acquired_lock == 1 )); then
        if wsp_lock_stop; then
            :
        else
            wsp_warn 'Package search index preparation finished, but lock cleanup reported an error.'
            (( status == 0 )) && status=1
        fi
    fi
    return "$status"
}

wsp_catalog_stale() {
    local age
    age="$(wsp_catalog_cache_age)"
    [[ "$age" =~ ^[0-9]+$ && "$age" -ge "${WSP_CFG_CATALOG_STALE_SECONDS:-21600}" ]]
}

wsp_catalog_has_provider() {
    local provider="$1"
    [[ -f "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" ]] &&
        awk -F '\t' -v p="$provider" '$1 == p { found=1 } END { exit(found ? 0 : 1) }' \
            "$WSP_CATALOG_FILE"
}

wsp_catalog_needs_refresh() {
    local schema
    local metadata

    wsp_catalog_paths_safe || return 2
    [[ ! -s "$WSP_CATALOG_FILE" ]] && return 0
    schema="$(wsp_catalog_schema)"
    (( schema >= WSP_CATALOG_SCHEMA_CURRENT )) || return 0
    if metadata="$(wsp_catalog_meta_value metadata)"; then
        :
    else
        metadata=''
    fi
    [[ "$metadata" == *release_time* ]] || return 0
    wsp_catalog_stale && return 0

    # Version 1 of the catalog could silently drop DNF rows because DNF5's
    # query format did not include an explicit record newline. Invalidate such
    # a cache instead of presenting a Flatpak-only search surface.
    if command -v dnf5 >/dev/null || command -v dnf >/dev/null; then
        wsp_catalog_has_provider dnf || return 0
    fi
    if declare -F wsp_aurelia_sources_rows >/dev/null; then
        local aurelia_sources_file
        local aurelia_sources
        local catalog_mtime
        local sources_mtime

        if aurelia_sources_file="$(wsp_aurelia_sources_path)"; then
            :
        else
            wsp_warn 'Could not resolve the Aurelia source manifest while checking catalog freshness.'
            return 0
        fi
        if aurelia_sources="$(wsp_aurelia_sources_rows)"; then
            :
        else
            wsp_warn 'Could not read the Aurelia source manifest while checking catalog freshness.'
            return 0
        fi
        if [[ -n "$aurelia_sources" ]]; then
            wsp_catalog_has_provider aurelia || return 0
            while IFS=$'\t' read -r source _url _profiles; do
                [[ -n "$source" ]] || continue
                if ! awk -F '\t' -v s="$source" '$1 == "aurelia" && $2 == s { found=1 } END { exit(found ? 0 : 1) }' \
                    "$WSP_CATALOG_FILE"; then
                    return 0
                fi
            done <<< "$aurelia_sources"
            catalog_mtime="$(stat -c '%Y' "$WSP_CATALOG_FILE"  || printf '%s' 0)"
            sources_mtime="$(stat -c '%Y' "$aurelia_sources_file"  || printf '%s' 0)"
            if [[ "$sources_mtime" =~ ^[0-9]+$ && "$catalog_mtime" =~ ^[0-9]+$ &&
                  "$sources_mtime" -gt "$catalog_mtime" ]]; then
                return 0
            fi
        fi
    fi
    return 1
}

wsp_dnf_binary() {
    if command -v dnf5 >/dev/null; then
        command -v dnf5
    elif command -v dnf >/dev/null; then
        command -v dnf
    else
        return 1
    fi
}

wsp_catalog_dnf_query_format() {
    # Unit and record separators keep multiline descriptions and capability
    # lists parseable. They are replaced before the final TSV row is written.
    printf '%s' $'%{name}\x1f%{summary}\x1f%{description}\x1f%{evr}\x1f%{repoid}\x1f%{arch}\x1f%{installsize}\x1f%{downloadsize}\x1f%{license}\x1f%{url}\x1f%{location}\x1f%{sourcerpm}\x1f%{packager}\x1f%{vendor}\x1f%{provides}\x1f%{requires}\x1f%{recommends}\x1f%{suggests}\x1f%{supplements}\x1f%{enhances}\x1f%{obsoletes}\x1f%{conflicts}\x1f%{full_nevra}\x1f%{buildtime}\x1e'
}

wsp_catalog_parse_dnf_rows() {
    local raw_file="$1"
    local native_arch="$2"
    local field_separator="$WSP_CATALOG_FIELD_SEPARATOR"
    local record_separator="$WSP_CATALOG_RECORD_SEPARATOR"

    if ! LC_ALL=C grep -Fq -- "$record_separator" "$raw_file"; then
        # Compatibility path for the compact schema used by older catalogs
        # and older test doubles. A rich refresh replaces this immediately.
        awk -F '\t' -v native_arch="$native_arch" '
            function valid_source(value) {
                return value ~ /^[A-Za-z0-9][A-Za-z0-9_.:\/-]{0,127}$/
            }
            function valid_id(value) {
                return value ~ /^[A-Za-z0-9][A-Za-z0-9+._:-]{0,127}$/
            }
            function clean(value) {
                gsub(/[[:cntrl:]]/, " ", value)
                gsub(/[[:space:]]+/, " ", value)
                sub(/^ +/, "", value)
                sub(/ +$/, "", value)
                return value
            }
            function emit_row(    i) {
                for (i = 1; i <= 31; i++) {
                    if (i > 1) printf "\t"
                    printf "%s", out[i]
                }
                printf "\n"
            }
            NF >= 1 {
                name = clean($1)
                summary = clean($2)
                evr = clean($3)
                source = clean($4)
                arch = clean($5)
                if (arch != native_arch && arch != "noarch") next
                if (!valid_source(source) || !valid_id(name)) next
                for (i = 1; i <= 31; i++) out[i] = ""
                out[1] = "dnf"
                out[2] = source
                out[3] = name
                out[4] = name
                out[5] = summary
                out[6] = evr
                out[7] = "system"
                out[12] = arch
                out[29] = name " " summary
                emit_row()
            }
        ' "$raw_file"
        return 0
    fi

    awk -v RS="$record_separator" -v FS="$field_separator" -v native_arch="$native_arch" '
        function clean(value) {
            gsub(/[[:cntrl:]]/, " ", value)
            gsub(/[[:space:]]+/, " ", value)
            sub(/^ +/, "", value)
            sub(/ +$/, "", value)
            return value
        }
        function valid_source(value) {
            return value ~ /^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,127}$/
        }
        function valid_id(value) {
            return value ~ /^[A-Za-z0-9][A-Za-z0-9+._:-]{0,127}$/
        }
        function emit_row(    i) {
            for (i = 1; i <= 31; i++) {
                if (i > 1) printf "\t"
                printf "%s", out[i]
            }
            printf "\n"
        }
        NF >= 1 {
            for (i = 1; i <= NF; i++) $i = clean($i)
            name = $1
            summary = $2
            description = $3
            evr = $4
            source = ($5 == "" ? "dnf" : $5)
            arch = ($6 == "" ? "unknown" : $6)
            installsize = $7
            downloadsize = $8
            license = $9
            url = $10
            location = $11
            sourcerpm = $12
            packager = $13
            vendor = $14
            provides = $15
            requires = $16
            recommends = $17
            suggests = $18
            supplements = $19
            enhances = $20
            obsoletes = $21
            conflicts = $22
            full_nevra = $23
            release_time = $24
            if (arch != native_arch && arch != "noarch") next
            if (!valid_source(source) || !valid_id(name)) next
            if (packager != "" && vendor != "") packager = packager " / " vendor
            else if (vendor != "") packager = vendor
            out[1] = "dnf"
            out[2] = source
            out[3] = name
            out[4] = name
            out[5] = summary
            out[6] = evr
            out[7] = "system"
            out[8] = ""
            out[9] = ""
            out[10] = ""
            out[11] = ""
            out[12] = arch
            out[13] = installsize
            out[14] = downloadsize
            out[15] = license
            out[16] = url
            out[17] = location
            out[18] = sourcerpm
            out[19] = provides
            out[20] = requires
            out[21] = recommends
            out[22] = suggests
            out[23] = supplements
            out[24] = enhances
            out[25] = obsoletes
            out[26] = conflicts
            out[27] = packager
            out[28] = description
            out[29] = name " " summary " " description " " license " " url " " location " " sourcerpm " " provides
            out[30] = full_nevra
            out[31] = release_time
            emit_row()
        }
    ' "$raw_file"
}

wsp_catalog_dnf_query_raw() {
    local raw_file="$1"
    local cache_only="${2:-0}"
    local query="${3:-}"
    local timeout_seconds="${4:-${WSP_CFG_DNF_METADATA_TIMEOUT:-240}}"
    local dnf_bin
    local -a command_argv=()

    dnf_bin="$(wsp_dnf_binary)" || return 1
    command_argv=("$dnf_bin")
    if [[ "$cache_only" == 1 ]]; then
        command_argv+=(-C)
    fi
    command_argv+=(-q repoquery --available)
    if [[ -n "$query" ]]; then
        command_argv+=(--whatprovides "$query")
    fi
    command_argv+=(--qf "$(wsp_catalog_dnf_query_format)")
    wsp_run_timeout "$timeout_seconds" "${command_argv[@]}" > "$raw_file"
}

wsp_catalog_dnf_provider_rows() {
    local query="$1"
    local capability
    local raw_file
    local native_arch
    local query_status=0
    local parse_status

    [[ "$query" =~ ^[A-Za-z0-9][A-Za-z0-9+._:/-]{2,127}$ ]] || return 2
    native_arch="$(wsp_dnf_native_arch)" || return 1
    raw_file="$(mktemp)" || return 1
    if [[ "$query" == /* || "$query" == */* ]]; then
        capability="$query"
    else
        capability="*/$query"
    fi
    : > "$raw_file"
    if wsp_catalog_dnf_query_raw "$raw_file" 1 "$capability" "${WSP_CFG_DNF_RESOLVE_TIMEOUT:-30}"; then
        query_status=0
    else
        query_status=$?
        wsp_warn "DNF cache-only capability lookup failed for '$capability' (status $query_status); retrying."
    fi
    if [[ -s "$raw_file" ]]; then
        if wsp_catalog_parse_dnf_rows "$raw_file" "$native_arch" | awk -F '\t' '{ print $0 "\tprovided capability" }'; then
            parse_status=0
        else
            parse_status=$?
        fi
        rm -f -- "$raw_file"
        return "$parse_status"
    fi
    if [[ ! -s "$raw_file" && "$capability" != "$query" ]]; then
        # Some repository metadata records a virtual capability but not a
        # file glob. Retry the exact capability before declaring no match.
        : > "$raw_file"
        if wsp_catalog_dnf_query_raw "$raw_file" 1 "$query" "${WSP_CFG_DNF_RESOLVE_TIMEOUT:-30}"; then
            query_status=0
        else
            query_status=$?
            wsp_warn "DNF cache-only capability lookup failed for '$query' (status $query_status); retrying live metadata."
        fi
        if [[ -s "$raw_file" ]]; then
            if wsp_catalog_parse_dnf_rows "$raw_file" "$native_arch" | awk -F '\t' '{ print $0 "\tprovided capability" }'; then
                parse_status=0
            else
                parse_status=$?
            fi
            rm -f -- "$raw_file"
            return "$parse_status"
        fi
    fi
    if [[ ! -s "$raw_file" ]]; then
        # A fresh boot cache may not contain filelists yet. A capability search
        # is the one case where an explicit query may perform a bounded live
        # lookup; normal catalog search remains entirely local.
        : > "$raw_file"
        if wsp_catalog_dnf_query_raw "$raw_file" 0 "$capability" "${WSP_CFG_DNF_RESOLVE_TIMEOUT:-30}"; then
            query_status=0
        else
            query_status=$?
            wsp_warn "DNF live capability lookup failed for '$capability' (status $query_status)."
        fi
        if [[ -s "$raw_file" ]]; then
            if wsp_catalog_parse_dnf_rows "$raw_file" "$native_arch" | awk -F '\t' '{ print $0 "\tprovided capability" }'; then
                parse_status=0
            else
                parse_status=$?
            fi
            rm -f -- "$raw_file"
            return "$parse_status"
        fi
    fi
    if [[ ! -s "$raw_file" && "$capability" != "$query" ]]; then
        : > "$raw_file"
        if wsp_catalog_dnf_query_raw "$raw_file" 0 "$query" "${WSP_CFG_DNF_RESOLVE_TIMEOUT:-30}"; then
            query_status=0
        else
            query_status=$?
            wsp_warn "DNF live capability lookup failed for '$query' (status $query_status)."
        fi
        if [[ -s "$raw_file" ]]; then
            if wsp_catalog_parse_dnf_rows "$raw_file" "$native_arch" | awk -F '\t' '{ print $0 "\tprovided capability" }'; then
                parse_status=0
            else
                parse_status=$?
            fi
            rm -f -- "$raw_file"
            return "$parse_status"
        fi
    fi
    rm -f -- "$raw_file"
    if (( query_status != 0 )); then
        wsp_error "DNF capability lookup failed for '$query' after bounded retries."
        return "$query_status"
    fi
    printf 'INFO: DNF capability search found no provider for %s.\n' "$query" >&2
}

wsp_catalog_refresh_dnf() {
    local dnf_bin
    local raw_file
    local err_file
    local native_arch
    local status=0

    dnf_bin="$(wsp_dnf_binary)" || {
        printf '%s\n' 'DNF is unavailable.' >> "$WSP_REFRESH_ERRORS"
        wsp_error 'DNF is unavailable; the Fedora package catalog could not be refreshed.'
        return 1
    }
    native_arch="$(wsp_dnf_native_arch)" || {
        printf 'Unsupported host architecture for DNF catalog.\n' >> "$WSP_REFRESH_ERRORS"
        wsp_error 'The host architecture is unsupported for the DNF package catalog.'
        return 1
    }
    raw_file="$(mktemp)" || return 1
    err_file="$(mktemp)" || {
        rm -f -- "$raw_file"
        return 1
    }

    if ! wsp_run_timeout "${WSP_CFG_DNF_METADATA_TIMEOUT:-240}" "$dnf_bin" -q makecache --refresh \
        2> >(tee "$err_file" >&2); then
        printf 'dnf makecache: %s\n' "$(tr '\r\n' ' ' < "$err_file" | cut -c1-240)" >> "$WSP_REFRESH_ERRORS"
        status=1
    fi
    if ! wsp_catalog_dnf_query_raw "$raw_file" 0 2> >(tee "$err_file" >&2); then
        printf 'dnf repoquery: %s\n' "$(tr '\r\n' ' ' < "$err_file" | cut -c1-240)" >> "$WSP_REFRESH_ERRORS"
        rm -f -- "$raw_file" "$err_file"
        return 1
    fi
    if wsp_catalog_parse_dnf_rows "$raw_file" "$native_arch" >> "$WSP_CATALOG_ROWS"; then
        :
    else
        wsp_error 'DNF metadata was retrieved but could not be parsed into the package catalog.'
        status=1
    fi

    rm -f -- "$raw_file" "$err_file"
    return "$status"
}

wsp_flatpak_remote_names() {
    local scope="$1"
    local output

    command -v flatpak >/dev/null || return 1
    output="$(wsp_run_timeout "${WSP_CFG_FLATPAK_METADATA_TIMEOUT:-180}" flatpak remotes "--$scope" --columns=name )" || return 1
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
    local status=0

    command -v flatpak >/dev/null || {
        printf '%s\n' 'Flatpak is unavailable.' >> "$WSP_REFRESH_ERRORS"
        wsp_error 'Flatpak is unavailable; its package catalog could not be refreshed.'
        return 1
    }
    local sources_file

    sources_file="$(mktemp)" || return 1
    if ! wsp_flatpak_remote_names "$scope" > "$sources_file"; then
        printf 'flatpak/%s: could not enumerate configured remotes.\n' "$scope" >> "$WSP_REFRESH_ERRORS"
        wsp_error "Could not enumerate Flatpak remotes for $scope scope."
        status=1
    fi
    while IFS= read -r source; do
        [[ -n "$source" ]] || continue
        if raw_file="$(mktemp )"; then
            :
        else
            wsp_error "Could not create temporary storage for Flatpak $scope metadata."
            status=1
            break
        fi
        err_file="$(mktemp )" || {
            rm -f -- "$raw_file"
            wsp_error "Could not create temporary diagnostic storage for Flatpak $scope metadata."
            status=1
            break
        }
        if ! wsp_run_timeout "${WSP_CFG_FLATPAK_METADATA_TIMEOUT:-180}" flatpak remote-ls "--$scope" --app \
            --columns=application,name,description,version,branch,arch,origin,ref,runtime,installed-size,download-size,options,commit "$source" \
            > "$raw_file" 2> >(tee "$err_file" >&2); then
            printf 'flatpak/%s/%s: %s\n' "$scope" "$source" \
                "$(tr '\r\n' ' ' < "$err_file" | cut -c1-240)" >> "$WSP_REFRESH_ERRORS"
            status=1
            rm -f -- "$raw_file" "$err_file"
            continue
        fi

        awk -F '\t' -v source="$source" -v scope="$scope" '
            function clean(value) {
                gsub(/[[:cntrl:]]/, " ", value)
                gsub(/[[:space:]]+/, " ", value)
                sub(/^ +/, "", value)
                sub(/ +$/, "", value)
                return value
            }
            function valid_id(value) {
                return value ~ /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/
            }
            function emit_row(    i) {
                for (i = 1; i <= 31; i++) {
                    if (i > 1) printf "\t"
                    printf "%s", out[i]
                }
                printf "\n"
            }
            {
                for (i = 1; i <= NF; i++) $i = clean($i)
                identifier = $1
                name = ($2 == "" ? identifier : $2)
                description = $3
                version = $4
                branch = $5
                arch = ($6 == "" ? "unknown" : $6)
                origin = $7
                ref = $8
                runtime = $9
                installed_size = $10
                download_size = $11
                options = $12
                commit = $13
                if (branch != "" && branch != "-") version = (version == "" ? "unknown" : version) " @ " branch
                if (identifier == "" || !valid_id(identifier)) next
                out[1] = "flatpak"
                out[2] = source
                out[3] = identifier
                out[4] = name
                out[5] = description
                out[6] = version
                out[7] = scope
                out[8] = ""
                out[9] = ""
                out[10] = ""
                out[11] = ""
                out[12] = arch
                out[13] = installed_size
                out[14] = download_size
                out[15] = ""
                out[16] = ""
                out[17] = ref
                out[18] = runtime
                out[19] = options
                out[20] = ""
                out[21] = ""
                out[22] = ""
                out[23] = ""
                out[24] = ""
                out[25] = ""
                out[26] = ""
                out[27] = origin
                out[28] = description
                out[29] = identifier " " name " " description " " ref " " runtime " " options
                out[30] = commit
                out[31] = ""
                emit_row()
            }
        ' "$raw_file" >> "$WSP_CATALOG_ROWS" || {
            wsp_error "Flatpak metadata for $scope remote '$source' could not be parsed into the package catalog."
            status=1
        }
        rm -f -- "$raw_file" "$err_file"
    done < "$sources_file"
    rm -f -- "$sources_file"

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
    local catalog_row_count=0
    local dnf_row_count=0
    local flatpak_row_count=0
    local aurelia_row_count=0

    wsp_catalog_paths_safe || return 1
    temporary="$(mktemp "$cache_dir/.catalog.XXXXXX" )" || return 1
    WSP_CATALOG_ROWS="$temporary"
    WSP_REFRESH_ERRORS="$(mktemp )" || {
        rm -f -- "$temporary"
        return 1
    }
    : > "$WSP_REFRESH_ERRORS"

    wsp_catalog_progress 'Refreshing Fedora package sources...'
    if wsp_catalog_refresh_dnf; then
        :
    else
        dnf_status=$?
    fi
    wsp_catalog_progress 'Refreshing Flatpak remotes...'
    if wsp_catalog_refresh_flatpak_scope system; then
        :
    else
        flatpak_system_status=$?
    fi
    if wsp_catalog_refresh_flatpak_scope user; then
        :
    else
        flatpak_user_status=$?
    fi
    wsp_catalog_progress 'Refreshing Aurelia GitHub release sources...'
    if declare -F wsp_aurelia_catalog_rows >/dev/null; then
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

    if ! sort -u "$temporary" > "$temporary.sorted"; then
        wsp_error 'Could not sort the generated package catalog before publication.'
        rm -f -- "$temporary" "$temporary.sorted" "$WSP_REFRESH_ERRORS"
        WSP_CATALOG_ROWS=""
        WSP_REFRESH_ERRORS=""
        return 1
    fi
    if ! mv -f -- "$temporary.sorted" "$temporary"; then
        rm -f -- "$temporary" "$temporary.sorted" "$WSP_REFRESH_ERRORS"
        WSP_CATALOG_ROWS=""
        WSP_REFRESH_ERRORS=""
        return 1
    fi
    if ! wsp_catalog_build_derived_indexes "$temporary"; then
        rm -f -- "$temporary" "$WSP_REFRESH_ERRORS" \
            "${WSP_CATALOG_DISPLAY_STAGED:-}" "${WSP_CATALOG_INDEX_STAGED:-}"
        WSP_CATALOG_ROWS=""
        WSP_REFRESH_ERRORS=""
        WSP_CATALOG_DISPLAY_STAGED=''
        WSP_CATALOG_INDEX_STAGED=''
        return 1
    fi
    if ! wsp_atomic_replace "$WSP_CATALOG_FILE" "$temporary"; then
        rm -f -- "$temporary" "$WSP_REFRESH_ERRORS" \
            "$WSP_CATALOG_DISPLAY_STAGED" "$WSP_CATALOG_INDEX_STAGED"
        WSP_CATALOG_ROWS=""
        WSP_REFRESH_ERRORS=""
        WSP_CATALOG_DISPLAY_STAGED=''
        WSP_CATALOG_INDEX_STAGED=''
        return 1
    fi
    rm -f -- "$temporary"
    if ! wsp_catalog_publish_derived_indexes; then
        rm -f -- "$WSP_REFRESH_ERRORS" \
            "${WSP_CATALOG_DISPLAY_STAGED:-}" "${WSP_CATALOG_INDEX_STAGED:-}"
        WSP_CATALOG_ROWS=""
        WSP_REFRESH_ERRORS=""
        WSP_CATALOG_DISPLAY_STAGED=''
        WSP_CATALOG_INDEX_STAGED=''
        return 1
    fi

    catalog_row_count="$(wc -l < "$WSP_CATALOG_FILE" | tr -d '[:space:]')"
    dnf_row_count="$(awk -F '\t' '$1 == "dnf" { count++ } END { print count + 0 }' "$WSP_CATALOG_FILE")"
    flatpak_row_count="$(awk -F '\t' '$1 == "flatpak" { count++ } END { print count + 0 }' "$WSP_CATALOG_FILE")"
    aurelia_row_count="$(awk -F '\t' '$1 == "aurelia" { count++ } END { print count + 0 }' "$WSP_CATALOG_FILE")"

    [[ ! -L "$WSP_CATALOG_META.tmp" && ! -L "$WSP_CATALOG_META" ]] || {
        rm -f -- "$WSP_CATALOG_META.tmp" "$WSP_REFRESH_ERRORS"
        WSP_CATALOG_ROWS=""
        WSP_REFRESH_ERRORS=""
        wsp_error "Refusing symlinked package catalog metadata file."
        return 1
    }
    {
        printf 'schema=%s\n' "$WSP_CATALOG_SCHEMA_CURRENT"
        printf 'refreshed_at=%s\n' "$(date --iso-8601=seconds)"
        printf 'rows=%s\n' "$catalog_row_count"
        printf 'dnf_rows=%s\n' "$dnf_row_count"
        printf 'flatpak_rows=%s\n' "$flatpak_row_count"
        printf 'aurelia_rows=%s\n' "$aurelia_row_count"
        printf 'metadata=description,arch,installsize,downloadsize,license,url,location,runtime,provides,requires,recommends,suggests,supplements,enhances,obsoletes,conflicts,vendor,release_time,full_nevra_or_commit\n'
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

    if (( status == 2 )); then
        wsp_warn 'Package catalog refresh completed with one or more source errors.'
    else
        wsp_catalog_progress 'Package catalog refresh completed.'
    fi
    return "$status"
}

wsp_catalog_ensure() {
    local acquired_lock=0

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
            wsp_warn 'Using the previous package catalog because the requested refresh failed.'
        fi
        [[ "$acquired_lock" -eq 1 ]] && wsp_lock_stop
    fi
}

wsp_catalog_rows() {
    wsp_catalog_paths_safe || return 1
    [[ -f "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" ]] || return 1
    cat -- "$WSP_CATALOG_FILE"
}

wsp_catalog_search_ranked_legacy() {
    local query="${1:-}"
    local limit="${2:-${WSP_CFG_CATALOG_RESULT_LIMIT:-250}}"
    local all_versions="${3:-0}"
    local sorted_file
    local provider_file
    local provider_status

    wsp_catalog_paths_safe || return 1
    [[ -f "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" ]] || return 0
    [[ "$limit" =~ ^[0-9]+$ && "$limit" -gt 0 ]] || return 2

    # Search is intentionally performed by the catalog, not by fzf. A package
    # manager needs normalized semantic matching: "LibreOffice", "libreOffice"
    # and "libre office" must reach the same rows, while an approximate string
    # match must never turn an unrelated package into an install candidate.
    sorted_file="$(mktemp)" || return 1
    awk -F '\t' -v q="$query" '
        function compact(value) {
            value = tolower(value)
            gsub(/[^[:alnum:]]/, "", value)
            return value
        }
        function spaced(value) {
            value = tolower(value)
            gsub(/[^[:alnum:]]+/, " ", value)
            sub(/^ +/, "", value)
            sub(/ +$/, "", value)
            return value
        }
        function field_matches(value, normalized_value, i) {
            normalized_value = compact(value)
            if (index(normalized_value, query_compact) > 0) return 1
            if (word_count < 2) return 0
            normalized_value = spaced(value)
            for (i = 1; i <= word_count; i++) {
                if (words[i] != "" && index(" " normalized_value " ", " " compact(words[i]) " ") == 0) return 0
            }
            return 1
        }
        function emit_score(score, reason) {
            printf "%09d\t%s\t%s\n", 999999 - score, $0, reason
        }
        BEGIN {
            normalized = tolower(q)
            gsub(/[^[:alnum:]]+/, " ", normalized)
            sub(/^ +/, "", normalized)
            sub(/ +$/, "", normalized)
            word_count = split(normalized, words, / +/)
            query_compact = compact(q)
        }
        {
            # Search each user-facing field independently. Dependency edges
            # remain available in the preview but are intentionally excluded
            # from matching. A query must match as a normalized phrase inside
            # one field (or have all words in one descriptive field); this
            # prevents unrelated long capability lists from combining an
            # "edid" token from one entry with a "decode" token from another.
            if (query_compact == "") {
                emit_score(1, "")
                next
            }
            search_fields[1] = $1
            search_fields[2] = $2
            search_fields[3] = $3
            search_fields[4] = $4
            search_fields[5] = $5
            search_fields[6] = $12
            search_fields[7] = $13
            search_fields[8] = $14
            search_fields[9] = $15
            search_fields[10] = $16
            search_fields[11] = $17
            search_fields[12] = $18
            search_fields[13] = $27
            search_fields[14] = $28
            search_fields[15] = $30
            matched = 0
            for (field_index = 1; field_index <= 15; field_index++) {
                if (field_matches(search_fields[field_index])) {
                    matched = 1
                    break
                }
            }
            provided = index(compact($19), query_compact) > 0
            if (!matched && provided) matched = 1
            if (!matched) next

            id = compact($3)
            name = compact($4)
            summary = compact($5)
            provides = compact($19)
            description = compact($28)
            if (query_compact == id || query_compact == name) {
                score = 1000
                reason = "exact package"
            } else if (index(id, query_compact) == 1 || index(name, query_compact) == 1) {
                score = 940
                reason = "package name"
            } else if (provided) {
                score = 900
                reason = "provided capability"
            } else if (field_matches($5)) {
                score = 780
                reason = "summary"
            } else if (field_matches($28)) {
                score = 700
                reason = "description"
            } else {
                score = 500
                reason = "metadata"
            }
            emit_score(score, reason)
        }
    ' "$WSP_CATALOG_FILE" | sort -t $'\t' -k1,1n -k2,2 -k3,3 > "$sorted_file"

    if [[ ! -s "$sorted_file" && ${#query} -ge 3 ]]; then
        # A command or file capability may not be present in the persisted
        # package fields. Ask DNF's cached resolver once as a bounded fallback;
        # this is never run for every row and never mutates package state.
        provider_file="$(mktemp)" || {
            rm -f -- "$sorted_file"
            return 1
        }
        if wsp_catalog_dnf_provider_rows "$query" > "$provider_file"; then
            provider_status=0
        else
            provider_status=$?
            wsp_error "DNF capability lookup returned status $provider_status for '$query'."
        fi
        if [[ -s "$provider_file" ]]; then
            awk -F '\t' -v limit="$limit" 'NR <= limit { print }' "$provider_file"
            rm -f -- "$provider_file" "$sorted_file"
            return 0
        fi
        rm -f -- "$provider_file"
    fi

    awk -F '\t' -v limit="$limit" '
        NR > limit { exit }
        {
            reason = $NF
            sub(/\t[^\t]*$/, "", $0)
            sub(/^[^\t]*\t/, "", $0)
            print $0 "\t" reason
        }
    ' "$sorted_file"
    rm -f -- "$sorted_file"
}

wsp_catalog_index_ranked() {
    local query="${1:-}"
    local limit="${2:-${WSP_CFG_CATALOG_RESULT_LIMIT:-250}}"
    local all_versions="${3:-0}"
    local query_compact
    local candidate_file
    local search_file="$WSP_CATALOG_INDEX_FILE"
    local grep_status=0
    local status=0
    local -a pipeline_statuses=()

    wsp_catalog_ensure_derived_indexes || return 1
    [[ "$limit" =~ ^[0-9]+$ && "$limit" -gt 0 ]] || return 2
    query_compact="$(printf '%s' "${query,,}" | tr -cd '[:alnum:]')"
    if [[ ${#query_compact} -ge 3 && "$query" != *[[:space:]]* ]]; then
        candidate_file="$(mktemp)" || return 1
        if LC_ALL=C grep -F -- "$query_compact" "$WSP_CATALOG_INDEX_FILE" > "$candidate_file"; then
            search_file="$candidate_file"
        else
            grep_status=$?
            if (( grep_status > 1 )); then
                rm -f -- "$candidate_file"
                wsp_error "Could not scan the local package search index for '$query'."
                return "$grep_status"
            fi
        fi
    fi
    if awk -F '\t' -v q="$query" -v separator="$WSP_CATALOG_INDEX_SEPARATOR" '
        function phrase_matches(compact_value, spaced_value, i) {
            if (index(compact_value, query_compact) > 0) return 1
            if (word_count < 2) return 0
            for (i = 1; i <= word_count; i++) {
                if (words[i] != "" && index(" " spaced_value " ", " " words[i] " ") == 0) return 0
            }
            return 1
        }
        function token_matches(compact_value, spaced_value, i) {
            for (i = 1; i <= raw_word_count; i++) {
                if (compact_words[i] == "") continue
                if (index(compact_value, compact_words[i]) == 0 &&
                    index(" " spaced_value " ", " " spaced_words[i] " ") == 0) return 0
            }
            return 1
        }
        function emit_score(score, reason) {
            group = compact_fields[1] separator compact_fields[3]
            printf "%09d\t%s\t%s\t%s\t%s\t%s\n", 999999 - score, group, $5, $6, $1, reason
        }
        BEGIN {
            normalized = tolower(q)
            gsub(/[^[:alnum:]]+/, " ", normalized)
            sub(/^ +/, "", normalized)
            sub(/ +$/, "", normalized)
            word_count = split(normalized, words, / +/)
            query_compact = tolower(q)
            gsub(/[^[:alnum:]]/, "", query_compact)
            raw_word_count = split(q, raw_words, /[[:space:]]+/)
            for (word_index = 1; word_index <= raw_word_count; word_index++) {
                compact_words[word_index] = tolower(raw_words[word_index])
                gsub(/[^[:alnum:]]/, "", compact_words[word_index])
                spaced_words[word_index] = tolower(raw_words[word_index])
                gsub(/[^[:alnum:]]+/, " ", spaced_words[word_index])
            }
        }
        {
            split($2, compact_fields, separator)
            split($3, spaced_fields, separator)
            all_compact = ""
            all_spaced = ""
            for (field_index = 1; field_index <= 16; field_index++) {
                all_compact = all_compact compact_fields[field_index]
                all_spaced = all_spaced " " spaced_fields[field_index]
            }
            if (query_compact == "") {
                emit_score(1, "catalog")
                next
            }
            matched = 0
            for (field_index = 1; field_index <= 16; field_index++) {
                if (phrase_matches(compact_fields[field_index], spaced_fields[field_index])) {
                    matched = 1
                    break
                }
            }
            if (!matched && token_matches(all_compact, all_spaced)) matched = 1
            provided = index($4, query_compact) > 0
            if (!matched && provided) matched = 1
            if (!matched) next

            id = compact_fields[3]
            name = compact_fields[4]
            if (query_compact == id || query_compact == name) {
                score = 1000
                reason = "exact package"
            } else if (index(id, query_compact) == 1 || index(name, query_compact) == 1) {
                score = 940
                reason = "package name"
            } else if (provided) {
                score = 900
                reason = "provided capability"
            } else if (phrase_matches(compact_fields[5], spaced_fields[5])) {
                score = 780
                reason = "summary"
            } else if (phrase_matches(compact_fields[15], spaced_fields[15])) {
                score = 700
                reason = "description"
            } else {
                score = 500
                reason = "metadata"
            }
            emit_score(score, reason)
        }
    ' "$search_file" |
        sort -t $'\t' -k1,1n -k2,2 -k3,3nr -k4,4V -k5,5n |
        awk -F '\t' -v limit="$limit" -v all_versions="$all_versions" '
            {
                group = $2
                if (!all_versions && seen[group]++) next
                reason = $6
                if (!all_versions && seen_latest[group]++ == 0) reason = "LATEST · " reason
                if (count < limit) {
                    print $5 "\t" reason
                    count++
                }
            }
        '; then
        pipeline_statuses=("${PIPESTATUS[@]}")
    else
        pipeline_statuses=("${PIPESTATUS[@]}")
    fi
    for status in "${pipeline_statuses[@]}"; do
        if (( status != 0 )); then
            if [[ -n "${candidate_file:-}" ]]; then
                rm -f -- "$candidate_file"
            fi
            wsp_error "Could not rank the local package search results for '$query'."
            return 1
        fi
    done
    if [[ -n "${candidate_file:-}" ]]; then
        rm -f -- "$candidate_file"
    fi
    return 0
}

wsp_catalog_rows_for_index_matches() {
    local matches_file="$1"
    local source_file="$2"

    awk -F '\t' -v matches="$matches_file" '
        FILENAME == matches {
            order[++count] = $1
            reason[$1] = $2
            next
        }
        FNR in reason { rows[FNR] = $0 }
        END {
            for (i = 1; i <= count; i++) {
                line = order[i]
                if (line in rows) print rows[line] "\t" reason[line]
            }
        }
    ' "$matches_file" "$source_file"
}

wsp_catalog_display_rows_for_index_matches() {
    local matches_file="$1"
    local source_file="$2"

    awk -F '\t' -v OFS='\t' -v matches="$matches_file" '
        FILENAME == matches {
            order[++count] = $1
            reason[$1] = $2
            next
        }
        FNR in reason {
            $10 = reason[FNR]
            rows[FNR] = $0
        }
        END {
            for (i = 1; i <= count; i++) {
                line = order[i]
                if (line in rows) print rows[line]
            }
        }
    ' "$matches_file" "$source_file"
}

wsp_catalog_search_provider_fallback() {
    local query="$1"
    local limit="$2"
    local all_versions="${3:-0}"
    local provider_file
    local latest_file
    local status=0

    [[ ${#query} -ge 3 ]] || return 0
    provider_file="$(mktemp)" || return 1
    if wsp_catalog_dnf_provider_rows "$query" > "$provider_file"; then
        :
    else
        status=$?
        wsp_error "DNF capability fallback returned status $status for '$query'."
    fi
    if [[ -s "$provider_file" ]]; then
        if [[ "$all_versions" == 1 ]]; then
            awk -F '\t' -v limit="$limit" 'NR <= limit { print }' "$provider_file"
        else
            latest_file="$(mktemp)" || {
                rm -f -- "$provider_file"
                return 1
            }
            if ! sort -t $'\t' -k1,1 -k3,3 -k31,31nr -k6,6V "$provider_file" |
                awk -F '\t' -v OFS='\t' -v limit="$limit" '!seen[$1 SUBSEP $3]++ && count++ < limit { $32 = "LATEST · " $32; print }' > "$latest_file"; then
                rm -f -- "$provider_file" "$latest_file"
                wsp_error "Could not rank DNF capability fallback results for '$query'."
                return 1
            fi
            cat -- "$latest_file"
            rm -f -- "$latest_file"
        fi
        rm -f -- "$provider_file"
        return 0
    fi
    rm -f -- "$provider_file"
    return "$status"
}

wsp_catalog_search_ranked() {
    local query="${1:-}"
    local limit="${2:-${WSP_CFG_CATALOG_RESULT_LIMIT:-250}}"
    local all_versions="${3:-0}"
    local matches_file
    local rendered_file
    local status=0

    matches_file="$(mktemp)" || return 1
    rendered_file="$(mktemp)" || {
        rm -f -- "$matches_file"
        return 1
    }
    if wsp_catalog_index_ranked "$query" "$limit" "$all_versions" > "$matches_file"; then
        :
    else
        status=$?
    fi
    if (( status == 0 )); then
        if [[ -s "$matches_file" ]]; then
            if wsp_catalog_rows_for_index_matches "$matches_file" "$WSP_CATALOG_FILE" > "$rendered_file"; then
                :
            else
                status=$?
            fi
            if (( status == 0 )) && [[ -s "$rendered_file" ]]; then
                cat -- "$rendered_file"
            elif (( status == 0 )); then
                wsp_warn "The local package index returned no matching catalog rows for '$query'; trying the DNF capability fallback."
                wsp_catalog_search_provider_fallback "$query" "$limit" "$all_versions"
                status=$?
            fi
        else
            wsp_catalog_search_provider_fallback "$query" "$limit" "$all_versions"
            status=$?
        fi
    fi
    rm -f -- "$matches_file"
    rm -f -- "$rendered_file"
    return "$status"
}

wsp_catalog_search_tui_ranked() {
    local query="${1:-}"
    local limit="${2:-${WSP_CFG_CATALOG_RESULT_LIMIT:-250}}"
    local matches_file
    local rendered_file
    local status=0

    matches_file="$(mktemp)" || return 1
    rendered_file="$(mktemp)" || {
        rm -f -- "$matches_file"
        return 1
    }
    if wsp_catalog_index_ranked "$query" "$limit" > "$matches_file"; then
        :
    else
        status=$?
    fi
    if (( status == 0 )); then
        if [[ -s "$matches_file" ]]; then
            if wsp_catalog_display_rows_for_index_matches "$matches_file" "$WSP_CATALOG_DISPLAY_FILE" > "$rendered_file"; then
                :
            else
                status=$?
            fi
            if (( status == 0 )) && [[ -s "$rendered_file" ]]; then
                cat -- "$rendered_file"
            elif (( status == 0 )); then
                wsp_warn "The local package display index returned no rows for '$query'; trying the DNF capability fallback."
                wsp_catalog_search_provider_fallback "$query" "$limit"
                status=$?
            fi
        else
            wsp_catalog_search_provider_fallback "$query" "$limit"
            status=$?
        fi
    fi
    rm -f -- "$matches_file"
    rm -f -- "$rendered_file"
    return "$status"
}

wsp_catalog_search() {
    wsp_catalog_search_ranked "${1:-}"
}

wsp_catalog_row_for_identity() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="${4:-}"

    wsp_catalog_paths_safe || return 1
    [[ -f "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" ]] || return 1
    awk -F '\t' -v p="$provider" -v s="$source" -v i="$identifier" -v c="$scope" '
        $1 == p && $2 == s && $3 == i && (c == "" || $7 == c) { print; exit }
    ' "$WSP_CATALOG_FILE"
}

wsp_catalog_row_for_version() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="$4"
    local version="$5"
    local architecture="${6:-}"

    wsp_catalog_paths_safe || return 1
    [[ -f "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" ]] || return 1
    awk -F '\t' -v p="$provider" -v s="$source" -v i="$identifier" \
        -v c="$scope" -v v="$version" -v a="$architecture" '
        $1 == p && $2 == s && $3 == i && $6 == v &&
            (c == "" || $7 == c) && (a == "" || $12 == a) { print; exit }
    ' "$WSP_CATALOG_FILE"
}

wsp_catalog_info() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="${4:-}"
    local installed_size_override=""
    local target_path=""

    wsp_catalog_paths_safe || return 1
    [[ -f "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" ]] || return 1
    if [[ "$provider" == aurelia ]] &&
       target_path="$(wsp_aurelia_target_path "$identifier")" &&
       [[ -f "$target_path" && ! -L "$target_path" ]]; then
        if installed_size_override="$(stat -c '%s' "$target_path")" &&
           [[ "$installed_size_override" =~ ^[0-9]+$ ]]; then
            :
        else
            wsp_warn "Could not read the installed size for Aurelia binary: $target_path"
            installed_size_override=""
        fi
    fi
    awk -F '\t' -v p="$provider" -v s="$source" -v i="$identifier" -v c="$scope" \
        -v installed_override="$installed_size_override" '
        function human_size(value, number, unit) {
            if (value == "" || value == "-" || value == "0") return "not provided"
            if (value !~ /^[0-9]+$/) return value
            number = value + 0
            unit = "B"
            if (number >= 1024) { number /= 1024; unit = "KiB" }
            if (number >= 1024) { number /= 1024; unit = "MiB" }
            if (number >= 1024) { number /= 1024; unit = "GiB" }
            if (number >= 1024) { number /= 1024; unit = "TiB" }
            return sprintf("%.1f %s (%s bytes)", number, unit, value)
        }
        function show(label, value) {
            if (value != "") printf "%-16s: %s\n", label, value
        }
        $1 == p && $2 == s && $3 == i && (c == "" || $7 == c) {
            printf "Provider         : %s\nSource           : %s\nID               : %s\nName             : %s\n", $1, $2, $3, $4
            show("Summary", $5)
            show("Version", $6)
            show("Scope", $7)
            if ($31 ~ /^[0-9]+$/ && $31 > 0) {
                show("Release date", strftime("%Y-%m-%d %H:%M %Z", $31))
            } else if ($1 == "flatpak") {
                show("Release date", "not exposed by Flatpak remote metadata")
            }
            show("Architecture", $12)
            installed_size = $13
            if ($1 == "aurelia" && installed_override ~ /^[0-9]+$/) installed_size = installed_override
            show("Installed size", human_size(installed_size))
            show("Download size", human_size($14))
            show("License", $15)
            show("URL", $16)
            show("Location / ref", $17)
            show("Runtime / source", $18)
            show("Capabilities", $19)
            show("Requires", $20)
            show("Recommends", $21)
            show("Suggests", $22)
            show("Supplements", $23)
            show("Enhances", $24)
            show("Obsoletes", $25)
            show("Conflicts", $26)
            show("Vendor / packager", $27)
            show("Description", $28)
            show("NEVRA / commit", $30)
            if ($1 == "aurelia") {
                show("Asset", $8)
                show("Checksum", $9)
                show("Target", "~/" $10)
                show("Artifact URL", $11)
            }
            found = 1
            exit
        }
        END { exit(found ? 0 : 1) }
    ' "$WSP_CATALOG_FILE"
}

wsp_catalog_prepare_for_tui() {
    local refresh_status=0
    local freshness_status=0

    wsp_catalog_paths_safe || return 1
    if [[ -s "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" ]]; then
        if wsp_catalog_needs_refresh; then
            freshness_status=0
        else
            freshness_status=$?
        fi
        if (( freshness_status == 2 )); then
            wsp_error 'The package catalog path is unsafe; refusing to open package search.'
            return 1
        fi
        # Opening the TUI must be fast and deterministic. A stale or partial
        # cache remains usable; background refresh or explicit Ctrl-R owns
        # freshness. Only a missing cache takes the initial-refresh path below.
        wsp_catalog_ensure_derived_indexes || return 1
        return 0
    fi
    wsp_lock_start || return 1
    if wsp_catalog_refresh; then
        :
    else
        refresh_status=$?
    fi
    if ! wsp_lock_stop; then
        wsp_warn 'Initial catalog refresh completed, but package-operation lock cleanup reported an error.'
    fi
    if [[ ! -s "$WSP_CATALOG_FILE" ]]; then
        return 1
    fi
    # A partial refresh still publishes a last-known-good catalog. The UI can
    # show the recorded source status and the user can retry explicitly.
    if (( refresh_status != 0 )); then
        wsp_warn "Initial catalog refresh returned status $refresh_status; using the catalog that was published before the failure."
    fi
    wsp_catalog_ensure_derived_indexes
}

wsp_catalog_live_dnf_rows() {
    local raw_file
    local native_arch

    native_arch="$(wsp_dnf_native_arch)" || return 1
    raw_file="$(mktemp)" || return 1
    if ! wsp_catalog_dnf_query_raw "$raw_file" 1; then
        rm -f -- "$raw_file"
        return 1
    fi
    wsp_catalog_parse_dnf_rows "$raw_file" "$native_arch"
    rm -f -- "$raw_file"
}

wsp_catalog_live_flatpak_rows_for_scope() {
    local scope="$1"
    local source
    local raw_file
    local sources_file
    local status=0

    command -v flatpak >/dev/null || {
        wsp_error "Flatpak is unavailable; no live $scope catalog rows can be read."
        return 1
    }
    sources_file="$(mktemp)" || return 1
    if ! wsp_flatpak_remote_names "$scope" > "$sources_file"; then
        wsp_error "Could not enumerate Flatpak remotes for live $scope catalog rows."
        status=1
    fi
    while IFS= read -r source; do
        [[ -n "$source" ]] || continue
        raw_file="$(mktemp)" || {
            wsp_error "Could not create temporary storage for live Flatpak $scope metadata."
            status=1
            break
        }
        if ! wsp_run_timeout "${WSP_CFG_FLATPAK_METADATA_TIMEOUT:-180}" flatpak remote-ls "--$scope" --cached --app \
            --columns=application,name,description,version,branch,arch,origin,ref,runtime,installed-size,download-size,options,commit "$source" \
            > "$raw_file"; then
            wsp_error "Could not read cached Flatpak metadata for $scope remote '$source'."
            status=1
            rm -f -- "$raw_file"
            continue
        fi
        awk -F '\t' -v source="$source" -v scope="$scope" '
            function clean(value) {
                gsub(/[[:cntrl:]]/, " ", value)
                gsub(/[[:space:]]+/, " ", value)
                sub(/^ +/, "", value)
                sub(/ +$/, "", value)
                return value
            }
            function valid_id(value) {
                return value ~ /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/
            }
            function emit_row(    i) {
            for (i = 1; i <= 31; i++) {
                    if (i > 1) printf "\t"
                    printf "%s", out[i]
                }
                printf "\n"
            }
            {
                for (i = 1; i <= NF; i++) $i = clean($i)
                identifier = $1
                name = ($2 == "" ? identifier : $2)
                description = $3
                version = $4
                branch = $5
                arch = ($6 == "" ? "unknown" : $6)
                origin = $7
                ref = $8
                runtime = $9
                installed_size = $10
                download_size = $11
                options = $12
                commit = $13
                if (branch != "" && branch != "-") version = (version == "" ? "unknown" : version) " @ " branch
                if (identifier == "" || !valid_id(identifier)) next
                out[1] = "flatpak"
                out[2] = source
                out[3] = identifier
                out[4] = name
                out[5] = description
                out[6] = version
                out[7] = scope
                out[8] = ""
                out[9] = ""
                out[10] = ""
                out[11] = ""
                out[12] = arch
                out[13] = installed_size
                out[14] = download_size
                out[15] = ""
                out[16] = ""
                out[17] = ref
                out[18] = runtime
                out[19] = options
                out[20] = ""
                out[21] = ""
                out[22] = ""
                out[23] = ""
                out[24] = ""
                out[25] = ""
                out[26] = ""
                out[27] = origin
                out[28] = description
                out[29] = identifier " " name " " description " " ref " " runtime " " options
                out[30] = commit
                out[31] = ""
                emit_row()
            }
        ' "$raw_file"
        rm -f -- "$raw_file"
    done < "$sources_file"
    rm -f -- "$sources_file"
    return "$status"
}

wsp_catalog_live_rows() {
    local status=0

    # The live fallback is used only when no persisted catalog exists. It is
    # read-only and emits the same rich schema as the persisted catalog.
    if wsp_catalog_live_dnf_rows; then
        :
    else
        wsp_error 'Could not read live DNF package metadata.'
        status=1
    fi
    if wsp_catalog_live_flatpak_rows_for_scope system; then
        :
    else
        status=1
    fi
    if wsp_catalog_live_flatpak_rows_for_scope user; then
        :
    else
        status=1
    fi
    return "$status"
}

wsp_catalog_seed_aurelia_discovery() {
    local temporary
    local filtered

    [[ -n "${WSP_AURELIA_DISCOVERY_SOURCE:-}" &&
       -n "${WSP_AURELIA_DISCOVERY_IDENTIFIER:-}" ]] || return 1
    wsp_catalog_paths_safe || return 1
    temporary="$(mktemp "$WSP_CACHE_DIR/.catalog-seed.XXXXXX" )" || return 1
    filtered="$(mktemp "$WSP_CACHE_DIR/.catalog-seed-filtered.XXXXXX" )" || {
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
    wsp_aurelia_catalog_row >> "$filtered"
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
        if wsp_catalog_derived_ready; then
            cat -- "$WSP_CATALOG_DISPLAY_FILE"
        else
            cat -- "$WSP_CATALOG_FILE"
        fi
        return 0
    fi
    wsp_catalog_live_rows
}

wsp_catalog_initial_rows_for_tui() {
    # The catalog is already a bounded, atomically published cache. The TUI
    # must expose the complete cached result set; truncating it here makes a
    # valid package appear to be missing until a user guesses a search term.
    if [[ -s "$WSP_CATALOG_FILE" && ! -L "$WSP_CATALOG_FILE" ]]; then
        wsp_catalog_ensure_derived_indexes || return 1
        cat -- "$WSP_CATALOG_DISPLAY_FILE"
    else
        wsp_catalog_rows_for_tui
    fi
}
