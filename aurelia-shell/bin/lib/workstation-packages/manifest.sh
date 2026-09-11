#!/usr/bin/env bash

# Validation and deterministic editing for the tracked package manifests.
#
# The manifest is intentionally line-oriented. It is easy to review in Git,
# has no generated backup files, and does not require a general-purpose parser.

wsp_manifest_header() {
    printf '%s\n' \
        '# schema=2' \
        '# provider<TAB>source<TAB>identifier<TAB>scope<TAB>profiles' \
        '# Aurelia rows append: version<TAB>asset<TAB>checksum<TAB>target<TAB>artifact_url' \
        '# User-adopted package intent only; dependencies and runtimes are not tracked automatically.'
}

wsp_sources_header() {
    printf '%s\n' \
        '# schema=1' \
        '# provider<TAB>source<TAB>url<TAB>scope' \
        '# Flatpak remotes are configured from this file; DNF repositories are managed by the installer.'
}

wsp_manifest_rows() {
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

    if [[ ! -e "$WSP_MANIFEST" ]]; then
        return 0
    fi
    [[ -f "$WSP_MANIFEST" && ! -L "$WSP_MANIFEST" ]] || {
        wsp_error "Tracked package manifest is missing or is a symlink: $WSP_MANIFEST"
        return 1
    }
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(wsp_trim_line "$line")"
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
           ! wsp_validate_record "$provider" "$source" "$identifier" "$scope" "$profiles"; then
            wsp_error "Malformed package manifest row: $line"
            return 1
        fi
        if [[ "$provider" == aurelia ]]; then
            if ! declare -F wsp_aurelia_metadata_valid >/dev/null 2>&1 ||
                ! wsp_aurelia_metadata_valid "$source" "$identifier" "$version" "$asset" "$checksum" "$target" "$artifact_url"; then
                wsp_error "Malformed Aurelia package metadata: $line"
                return 1
            fi
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$provider" "$source" "$identifier" "$scope" "$profiles" \
                "$version" "$asset" "$checksum" "$target" "$artifact_url"
        elif [[ -n "$version" || -n "$asset" || -n "$checksum" || -n "$target" || -n "$artifact_url" ]]; then
            wsp_error "Only Aurelia rows may contain pinned upstream metadata: $line"
            return 1
        else
            printf '%s\t%s\t%s\t%s\t%s\n' \
                "$provider" "$source" "$identifier" "$scope" "$profiles"
        fi
    done < "$WSP_MANIFEST"
}

wsp_validate_manifest() {
    wsp_manifest_rows >/dev/null
}

wsp_manifest_has() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="$4"

    wsp_manifest_rows | awk -F '\t' \
        -v p="$provider" -v s="$source" -v i="$identifier" -v c="$scope" \
        '$1 == p && $2 == s && $3 == i && $4 == c { found=1 } END { exit(found ? 0 : 1) }'
}

wsp_manifest_write_rows() {
    local rows_file="$1"
    local temporary

    temporary="$(mktemp)" || return 1
    {
        wsp_manifest_header
        sort -u "$rows_file"
    } > "$temporary" || {
        rm -f -- "$temporary"
        return 1
    }
    if ! wsp_atomic_replace "$WSP_MANIFEST" "$temporary"; then
        rm -f -- "$temporary"
        return 1
    fi
    rm -f -- "$temporary"
}

wsp_manifest_add() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="$4"
    local profiles="$5"
    local version="${6:-}"
    local asset="${7:-}"
    local checksum="${8:-}"
    local target="${9:-}"
    local artifact_url="${10:-}"
    local rows_file
    local row

    wsp_validate_record "$provider" "$source" "$identifier" "$scope" "$profiles" || {
        wsp_error "Invalid package manifest record: $provider $source $identifier $scope $profiles"
        return 1
    }
    if [[ "$provider" == aurelia ]]; then
        wsp_aurelia_metadata_valid "$source" "$identifier" "$version" "$asset" "$checksum" "$target" "$artifact_url" || {
            wsp_error "Invalid Aurelia package metadata: $source/$identifier"
            return 1
        }
        row="$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
            "$provider" "$source" "$identifier" "$scope" "$profiles" \
            "$version" "$asset" "$checksum" "$target" "$artifact_url")"
    else
        [[ -z "$version" && -z "$asset" && -z "$checksum" && -z "$target" && -z "$artifact_url" ]] || {
            wsp_error "Pinned metadata is only valid for Aurelia packages."
            return 1
        }
        row="$(printf '%s\t%s\t%s\t%s\t%s' \
            "$provider" "$source" "$identifier" "$scope" "$profiles")"
    fi
    wsp_validate_manifest || return 1
    if wsp_manifest_has "$provider" "$source" "$identifier" "$scope"; then
        wsp_info "Already tracked: $provider/$source/$identifier ($scope)"
        return 0
    fi

    rows_file="$(mktemp)" || return 1
    if ! wsp_manifest_rows > "$rows_file"; then
        rm -f -- "$rows_file"
        return 1
    fi
    printf '%s\n' "$row" >> "$rows_file"
    if ! wsp_manifest_write_rows "$rows_file"; then
        rm -f -- "$rows_file"
        return 1
    fi
    rm -f -- "$rows_file"
    wsp_info "Tracked: $provider/$source/$identifier ($scope)"
}

wsp_manifest_remove() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="$4"
    local profiles="${5:-all}"
    local rows_file
    local removed_file

    wsp_validate_record "$provider" "$source" "$identifier" "$scope" "$profiles" || {
        wsp_error "Invalid package manifest record: $provider $source $identifier $scope $profiles"
        return 1
    }
    wsp_validate_manifest || return 1
    if ! awk -F '\t' -v p="$provider" -v s="$source" -v i="$identifier" \
        -v c="$scope" \
        '$1 == p && $2 == s && $3 == i && $4 == c { found=1 } END { exit(found ? 0 : 1) }' \
        < <(wsp_manifest_rows); then
        wsp_info "Not tracked: $provider/$source/$identifier ($scope)"
        return 0
    fi

    rows_file="$(mktemp)" || return 1
    removed_file="$(mktemp)" || {
        rm -f -- "$rows_file"
        return 1
    }
    if ! wsp_manifest_rows > "$rows_file"; then
        rm -f -- "$rows_file" "$removed_file"
        return 1
    fi
    awk -F '\t' -v p="$provider" -v s="$source" -v i="$identifier" \
        -v c="$scope" \
        '!(($1 == p) && ($2 == s) && ($3 == i) && ($4 == c))' \
        "$rows_file" > "$removed_file"
    if ! wsp_manifest_write_rows "$removed_file"; then
        rm -f -- "$rows_file" "$removed_file"
        return 1
    fi
    rm -f -- "$rows_file" "$removed_file"
    wsp_info "Untracked: $provider/$source/$identifier ($scope)"
}

wsp_sources_rows() {
    local line
    local provider
    local source
    local url
    local scope
    local extra

    if [[ ! -e "$WSP_SOURCES" ]]; then
        return 0
    fi
    [[ -f "$WSP_SOURCES" && ! -L "$WSP_SOURCES" ]] || {
        wsp_error "Package source manifest is missing or is a symlink: $WSP_SOURCES"
        return 1
    }
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(wsp_trim_line "$line")"
        [[ -z "$line" || "$line" == \#* ]] && continue
        provider=""
        source=""
        url=""
        scope=""
        extra=""
        IFS=$'\t' read -r provider source url scope extra <<< "$line"
        if [[ -n "$extra" || "$provider" != "flatpak" || -z "$source" ||
              -z "$url" || -z "$scope" ]] ||
           ! wsp_valid_source "$source" || ! wsp_validate_url "$url" ||
           ! wsp_valid_scope "$scope"; then
            wsp_error "Malformed package source row: $line"
            return 1
        fi
        printf '%s\t%s\t%s\t%s\n' "$provider" "$source" "$url" "$scope"
    done < "$WSP_SOURCES"
}

wsp_validate_sources() {
    local rows_file
    local duplicate

    rows_file="$(mktemp)" || return 1
    if ! wsp_sources_rows > "$rows_file"; then
        rm -f -- "$rows_file"
        return 1
    fi
    duplicate="$(cut -f1-2,4 "$rows_file" | sort | uniq -d)"
    if [[ -n "$duplicate" ]]; then
        wsp_error "Duplicate configured package source: $duplicate"
        rm -f -- "$rows_file"
        return 1
    fi
    rm -f -- "$rows_file"
}

wsp_sources_write_rows() {
    local rows_file="$1"
    local temporary

    temporary="$(mktemp)" || return 1
    {
        wsp_sources_header
        sort -u "$rows_file"
    } > "$temporary" || {
        rm -f -- "$temporary"
        return 1
    }
    if ! wsp_atomic_replace "$WSP_SOURCES" "$temporary"; then
        rm -f -- "$temporary"
        return 1
    fi
    rm -f -- "$temporary"
}

wsp_source_add() {
    local provider="$1"
    local source="$2"
    local url="$3"
    local scope="$4"
    local rows_file
    local row

    [[ "$provider" == "flatpak" ]] || {
        wsp_error "Only Flatpak remotes can be added by this workflow. DNF sources require reviewed installer changes."
        return 1
    }
    wsp_valid_source "$source" || {
        wsp_error "Invalid Flatpak source name: $source"
        return 1
    }
    wsp_validate_url "$url" || {
        wsp_error "Flatpak sources must use HTTPS: $url"
        return 1
    }
    wsp_valid_scope "$scope" || {
        wsp_error "Invalid Flatpak source scope: $scope"
        return 1
    }
    wsp_validate_sources || return 1
    if wsp_sources_rows | awk -F '\t' -v s="$source" -v c="$scope" '$2 == s && $4 == c { found=1 } END { exit(found ? 0 : 1) }'; then
        wsp_info "Already tracked source: flatpak/$source ($scope)"
        return 0
    fi

    rows_file="$(mktemp)" || return 1
    if ! wsp_sources_rows > "$rows_file"; then
        rm -f -- "$rows_file"
        return 1
    fi
    local tab=$'\t'
    row="${provider}${tab}${source}${tab}${url}${tab}${scope}"
    printf '%s\n' "$row" >> "$rows_file"
    if ! wsp_sources_write_rows "$rows_file"; then
        rm -f -- "$rows_file"
        return 1
    fi
    rm -f -- "$rows_file"
    wsp_info "Tracked source: flatpak/$source ($scope)"
}

wsp_source_remove() {
    local provider="$1"
    local source="$2"
    local scope="$3"
    local rows_file
    local removed_file

    [[ "$provider" == "flatpak" ]] || {
        wsp_error "Only Flatpak remotes can be removed by this workflow."
        return 1
    }
    wsp_valid_source "$source" || return 1
    wsp_valid_scope "$scope" || return 1
    wsp_validate_sources || return 1

    if wsp_manifest_rows | awk -F '\t' -v p="$provider" -v s="$source" -v c="$scope" \
        '$1 == p && $2 == s && $4 == c { found=1 } END { exit(found ? 0 : 1) }'; then
        wsp_error "Source still owns tracked packages; remove or re-home those declarations first."
        return 1
    fi

    rows_file="$(mktemp)" || return 1
    removed_file="$(mktemp)" || {
        rm -f -- "$rows_file"
        return 1
    }
    if ! wsp_sources_rows > "$rows_file"; then
        rm -f -- "$rows_file" "$removed_file"
        return 1
    fi
    awk -F '\t' -v p="$provider" -v s="$source" -v c="$scope" \
        '!(($1 == p) && ($2 == s) && ($4 == c))' "$rows_file" > "$removed_file"
    if ! wsp_sources_write_rows "$removed_file"; then
        rm -f -- "$rows_file" "$removed_file"
        return 1
    fi
    rm -f -- "$rows_file" "$removed_file"
    wsp_info "Untracked source: flatpak/$source ($scope)"
}
