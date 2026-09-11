#!/usr/bin/env bash

# Aurelia is the verified upstream-release provider for user-owned binaries.
#
# A source is an official GitHub repository.  Discovery selects one stable,
# architecture-matching raw Linux release asset, requires a SHA-256 digest from
# the GitHub release metadata/body (or an official checksum asset), and returns
# a fully pinned record.  Discovery never changes the tracked manifest; only an
# explicit install/adopt operation does that.

WSP_AURELIA_DISCOVERY_SOURCE=""
WSP_AURELIA_DISCOVERY_IDENTIFIER=""
WSP_AURELIA_DISCOVERY_NAME=""
WSP_AURELIA_DISCOVERY_SUMMARY=""
WSP_AURELIA_DISCOVERY_VERSION=""
WSP_AURELIA_DISCOVERY_SCOPE=""
WSP_AURELIA_DISCOVERY_ASSET=""
WSP_AURELIA_DISCOVERY_CHECKSUM=""
WSP_AURELIA_DISCOVERY_TARGET=""
WSP_AURELIA_DISCOVERY_ARTIFACT_URL=""
WSP_AURELIA_LAST_ERROR=""
WSP_AURELIA_TEMP_FILES=()

WSP_AURELIA_MARKER_SOURCE=""
WSP_AURELIA_MARKER_CHECKSUM=""
WSP_AURELIA_MARKER_TARGET=""

wsp_aurelia_fail() {
    WSP_AURELIA_LAST_ERROR="$1"
    return 1
}

wsp_aurelia_sources_path() {
    local path="${WORKSTATION_PACKAGE_AURELIA_SOURCES:-$WSP_REPO_ROOT/packages/aurelia-sources.tsv}"
    [[ "$path" == /* && "$path" != "/" ]] || return 1
    wsp_path_components_safe "$path" || return 1
    printf '%s\n' "$path"
}

wsp_aurelia_source_valid() {
    [[ "${1:-}" =~ ^github\.[cC][oO][mM]/[A-Za-z0-9][A-Za-z0-9_.-]{0,99}/[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$ ]]
}

wsp_aurelia_parse_github_url() {
    local url="$1"
    local owner
    local repository

    WSP_AURELIA_PARSED_SOURCE=""
    WSP_AURELIA_PARSED_OWNER=""
    WSP_AURELIA_PARSED_REPOSITORY=""
    WSP_AURELIA_PARSED_API_REPOSITORY=""

    if [[ ! "$url" =~ ^https://github\.com/([A-Za-z0-9][A-Za-z0-9_.-]{0,99})/([A-Za-z0-9][A-Za-z0-9_.-]{0,99})/?$ ]]; then
        return 1
    fi
    owner="${BASH_REMATCH[1]}"
    repository="${BASH_REMATCH[2]}"
    WSP_AURELIA_PARSED_OWNER="$owner"
    WSP_AURELIA_PARSED_REPOSITORY="$repository"
    WSP_AURELIA_PARSED_API_REPOSITORY="${owner,,}/${repository,,}"
    WSP_AURELIA_PARSED_SOURCE="github.com/${owner,,}/${repository,,}"
}

wsp_aurelia_source_url() {
    local source="$1"
    wsp_aurelia_source_valid "$source" || return 1
    printf 'https://%s\n' "$source"
}

wsp_aurelia_source_from_url() {
    local url="$1"
    wsp_aurelia_parse_github_url "$url" || return 1
    printf '%s\n' "$WSP_AURELIA_PARSED_SOURCE"
}

wsp_aurelia_sources_rows() {
    local manifest
    local line
    local source
    local url
    local profiles
    local extra
    local canonical_source

    manifest="$(wsp_aurelia_sources_path)" || return 1
    if [[ ! -e "$manifest" ]]; then
        return 0
    fi
    [[ -f "$manifest" && ! -L "$manifest" ]] || {
        wsp_error "Aurelia source manifest is missing or is a symlink: $manifest"
        return 1
    }
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(wsp_trim_line "$line")"
        [[ -z "$line" || "$line" == \#* ]] && continue
        source=""
        url=""
        profiles=""
        extra=""
        IFS=$'\t' read -r source url profiles extra <<< "$line"
        canonical_source=""
        if [[ -n "$extra" || -z "$source" || -z "$url" || -z "$profiles" ]] ||
            ! wsp_aurelia_source_valid "$source" ||
            ! wsp_aurelia_parse_github_url "$url" ||
            [[ "$source" != "$WSP_AURELIA_PARSED_SOURCE" ]] ||
            ! wsp_valid_profiles "$profiles"; then
            wsp_error "Malformed Aurelia source row: $line"
            return 1
        fi
        canonical_source="$WSP_AURELIA_PARSED_SOURCE"
        printf '%s\t%s\t%s\n' "$canonical_source" "$url" "$profiles"
    done < "$manifest"
}

wsp_aurelia_validate_sources() {
    local rows_file
    local duplicate

    rows_file="$(mktemp)" || return 1
    if ! wsp_aurelia_sources_rows > "$rows_file"; then
        rm -f -- "$rows_file"
        return 1
    fi
    duplicate="$(cut -f1 "$rows_file" | sort | uniq -d)"
    if [[ -n "$duplicate" ]]; then
        wsp_error "Duplicate Aurelia source: $duplicate"
        rm -f -- "$rows_file"
        return 1
    fi
    rm -f -- "$rows_file"
}

wsp_aurelia_sources_write_rows() {
    local rows_file="$1"
    local target
    local temporary

    target="$(wsp_aurelia_sources_path)" || return 1
    temporary="$(mktemp)" || return 1
    {
        printf '%s\n' \
            '# schema=1' \
            '# source<TAB>github_url<TAB>profiles' \
            '# Stable GitHub release sources for the Aurelia upstream-binary provider.'
        sort -u "$rows_file"
    } > "$temporary" || {
        rm -f -- "$temporary"
        return 1
    }
    if ! wsp_atomic_replace "$target" "$temporary"; then
        rm -f -- "$temporary"
        return 1
    fi
    rm -f -- "$temporary"
}

wsp_aurelia_source_add() {
    local source="$1"
    local url="$2"
    local profiles="${3:-all}"
    local canonical_source
    local canonical_url
    local rows_file

    canonical_source="$(wsp_aurelia_source_from_url "$url")" || {
        wsp_error "Aurelia sources must be official GitHub repository URLs: $url"
        return 1
    }
    canonical_url="https://$canonical_source"
    [[ "$source" == "$canonical_source" ]] || {
        wsp_error "Aurelia source does not match its GitHub URL: $source"
        return 1
    }
    wsp_valid_profiles "$profiles" || {
        wsp_error "Invalid Aurelia source profile selector: $profiles"
        return 1
    }
    wsp_aurelia_validate_sources || return 1

    if wsp_aurelia_sources_rows | awk -F '\t' -v s="$source" '$1 == s { found=1 } END { exit(found ? 0 : 1) }'; then
        if ! wsp_aurelia_sources_rows | awk -F '\t' -v s="$source" -v u="$canonical_url" -v p="$profiles" \
            '$1 == s && $2 == u && $3 == p { found=1 } END { exit(found ? 0 : 1) }'; then
            wsp_error "Aurelia source already exists with different metadata: $source"
            return 1
        fi
        wsp_info "Already tracked source: aurelia/$source"
        return 0
    fi

    rows_file="$(mktemp)" || return 1
    if ! wsp_aurelia_sources_rows > "$rows_file"; then
        rm -f -- "$rows_file"
        return 1
    fi
    printf '%s\t%s\t%s\n' "$source" "$canonical_url" "$profiles" >> "$rows_file"
    if ! wsp_aurelia_sources_write_rows "$rows_file"; then
        rm -f -- "$rows_file"
        return 1
    fi
    rm -f -- "$rows_file"
    wsp_info "Tracked source: aurelia/$source"
}

wsp_aurelia_source_remove() {
    local source="$1"
    local rows_file
    local removed_file

    wsp_aurelia_source_valid "$source" || {
        wsp_error "Invalid Aurelia source: $source"
        return 1
    }
    wsp_aurelia_validate_sources || return 1
    if wsp_manifest_rows | awk -F '\t' -v s="$source" '$1 == "aurelia" && $2 == s { found=1 } END { exit(found ? 0 : 1) }'; then
        wsp_error "Aurelia source still owns tracked packages; remove or re-home those declarations first."
        return 1
    fi
    rows_file="$(mktemp)" || return 1
    removed_file="$(mktemp)" || {
        rm -f -- "$rows_file"
        return 1
    }
    if ! wsp_aurelia_sources_rows > "$rows_file"; then
        rm -f -- "$rows_file" "$removed_file"
        return 1
    fi
    awk -F '\t' -v s="$source" '!(($1 == s))' "$rows_file" > "$removed_file"
    if ! wsp_aurelia_sources_write_rows "$removed_file"; then
        rm -f -- "$rows_file" "$removed_file"
        return 1
    fi
    rm -f -- "$rows_file" "$removed_file"
    wsp_info "Untracked source: aurelia/$source"
}

wsp_aurelia_arch_regex() {
    case "$(uname -m)" in
        x86_64) printf '%s\n' '(^|[-_.])(amd64|x86_64|x64)([-_.]|$)' ;;
        aarch64|arm64) printf '%s\n' '(^|[-_.])(arm64|aarch64|armv8)([-_.]|$)' ;;
        *) return 1 ;;
    esac
}

wsp_aurelia_checksum_from_text() {
    local text="$1"
    local asset="$2"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == *"$asset"* ]] || continue
        if [[ "$line" =~ ([[:xdigit:]]{64}) ]]; then
            printf 'sha256:%s\n' "${BASH_REMATCH[1],,}"
            return 0
        fi
    done <<< "$text"
    return 1
}

wsp_aurelia_download() {
    local url="$1"
    local output="$2"
    local timeout_seconds="${3:-180}"

    wsp_validate_url "$url" || return 1
    wsp_run_timeout "$timeout_seconds" curl --proto '=https' --proto-redir '=https' -fsSL \
        --connect-timeout 15 --max-time "$((timeout_seconds - 5))" \
        --retry 2 --retry-delay 1 \
        -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: fedora-hyprland-workstation-package-manager' \
        -o "$output" "$url"
}

wsp_aurelia_valid_version() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9+._:/-]{0,127}$ ]]
}

wsp_aurelia_valid_asset() {
    local asset="${1:-}"
    [[ -n "$asset" && ${#asset} -le 255 ]] || return 1
    [[ "$asset" != *$'\t'* && "$asset" != *$'\r'* && "$asset" != *$'\n'* ]] || return 1
    [[ "$asset" =~ ^[A-Za-z0-9][A-Za-z0-9._+@%()-]{0,254}$ ]]
}

wsp_aurelia_valid_checksum() {
    [[ "${1:-}" =~ ^sha256:[0-9a-fA-F]{64}$ ]]
}

wsp_aurelia_valid_target() {
    local identifier="$1"
    local target="$2"
    [[ "$target" == ".local/bin/$identifier" ]] || return 1
    [[ "$target" =~ ^\.local/bin/[A-Za-z0-9][A-Za-z0-9+._:-]{0,127}$ ]]
}

wsp_aurelia_valid_artifact_url() {
    local source="$1"
    local url="$2"
    local repository="${source#github.com/}"
    local lower_url="${url,,}"
    local lower_repository="${repository,,}"

    [[ "$lower_url" == "https://github.com/$lower_repository/releases/download/"* ]] || return 1
    [[ "$url" != *[[:space:]]* && "$url" != *\?* && "$url" != *\#* ]]
}

wsp_aurelia_metadata_valid() {
    local source="$1"
    local identifier="$2"
    local version="$3"
    local asset="$4"
    local checksum="$5"
    local target="$6"
    local artifact_url="$7"
    local repository="${source#github.com/}"
    local lower_url="${artifact_url,,}"
    local lower_repository="${repository,,}"
    local lower_version="${version,,}"
    local lower_asset="${asset,,}"

    wsp_aurelia_source_valid "$source" || return 1
    wsp_valid_dnf_id "$identifier" || return 1
    wsp_aurelia_valid_version "$version" || return 1
    wsp_aurelia_valid_asset "$asset" || return 1
    wsp_aurelia_valid_checksum "$checksum" || return 1
    wsp_aurelia_valid_target "$identifier" "$target" || return 1
    wsp_aurelia_valid_artifact_url "$source" "$artifact_url" || return 1
    [[ "$lower_url" == "https://github.com/$lower_repository/releases/download/$lower_version/$lower_asset" ]] || return 1
}

wsp_aurelia_discover_source() {
    local source_or_url="$1"
    local source
    local api_url
    local releases_file
    local sidecar_file
    local candidate_json
    local arch_regex
    local tag
    local body
    local asset
    local artifact_url
    local digest
    local sidecar_url
    local identifier
    local checksum=""

    WSP_AURELIA_LAST_ERROR=""
    WSP_AURELIA_DISCOVERY_SOURCE=""
    WSP_AURELIA_DISCOVERY_IDENTIFIER=""
    WSP_AURELIA_DISCOVERY_NAME=""
    WSP_AURELIA_DISCOVERY_SUMMARY=""
    WSP_AURELIA_DISCOVERY_VERSION=""
    WSP_AURELIA_DISCOVERY_SCOPE=""
    WSP_AURELIA_DISCOVERY_ASSET=""
    WSP_AURELIA_DISCOVERY_CHECKSUM=""
    WSP_AURELIA_DISCOVERY_TARGET=""
    WSP_AURELIA_DISCOVERY_ARTIFACT_URL=""

    if [[ "$source_or_url" == https://* ]]; then
        if ! wsp_aurelia_parse_github_url "$source_or_url"; then
            wsp_aurelia_fail "Aurelia source must be an exact https://github.com/OWNER/REPOSITORY URL."
            return 1
        fi
    else
        if ! wsp_aurelia_source_valid "$source_or_url"; then
            wsp_aurelia_fail "Invalid Aurelia source: $source_or_url"
            return 1
        fi
        source="${source_or_url,,}"
        WSP_AURELIA_PARSED_SOURCE="$source"
        WSP_AURELIA_PARSED_API_REPOSITORY="${source#github.com/}"
        WSP_AURELIA_PARSED_REPOSITORY="${WSP_AURELIA_PARSED_API_REPOSITORY##*/}"
        WSP_AURELIA_PARSED_OWNER="${WSP_AURELIA_PARSED_API_REPOSITORY%%/*}"
    fi
    source="$WSP_AURELIA_PARSED_SOURCE"
    api_url="https://api.github.com/repos/$WSP_AURELIA_PARSED_API_REPOSITORY/releases?per_page=30"
    if ! arch_regex="$(wsp_aurelia_arch_regex)"; then
        wsp_aurelia_fail "Unsupported architecture for Aurelia release discovery: $(uname -m)"
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        wsp_aurelia_fail 'curl is required for Aurelia release discovery.'
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        wsp_aurelia_fail 'jq is required for Aurelia release discovery.'
        return 1
    fi

    if ! releases_file="$(mktemp)"; then
        wsp_aurelia_fail 'Could not create a temporary GitHub release response.'
        return 1
    fi
    WSP_AURELIA_TEMP_FILES+=("$releases_file")
    if ! wsp_aurelia_download "$api_url" "$releases_file" 60; then
        rm -f -- "$releases_file"
        wsp_aurelia_fail "Could not query GitHub releases for $source."
        return 1
    fi
    if ! jq -e 'type == "array"' "$releases_file" >/dev/null 2>&1; then
        rm -f -- "$releases_file"
        wsp_aurelia_fail "GitHub returned an invalid release response for $source."
        return 1
    fi

    candidate_json="$(jq -cer --arg arch_regex "$arch_regex" '
        def stable_release:
            ((.tag_name // "") + " " + (.name // "") | ascii_downcase) as $label
            | ($label | test("(^|[^a-z0-9])(alpha|beta|rc|preview|pre|nightly|dev|snapshot)[0-9]*([^a-z0-9]|$)"; "i") | not);
        [ .[]?
          | select((.draft // false) != true)
          | select((.prerelease // false) != true)
          | select(stable_release)
          | . as $release
          | [($release.assets // [])[]?
             | select((.name // "") | type == "string")
             | select(((.name | ascii_downcase) | contains("linux")))
             | select(((.name | ascii_downcase) | test($arch_regex)))
             | select((((.name | ascii_downcase) | test("\\.(sha256|sha512|sha1|asc|sig|txt|json|tar|tar\\.gz|tgz|xz|zip|deb|rpm|dmg|exe|msi)$"; "i")) | not))
             | select((.browser_download_url // "") | type == "string")
           ] as $matches
          | select(($matches | length) == 1)
          | {
              tag: (.tag_name // ""),
              release_name: (.name // ""),
              body: (.body // ""),
              published_at: (.published_at // .created_at // ""),
              asset: $matches[0].name,
              artifact_url: $matches[0].browser_download_url,
              digest: ($matches[0].digest // ""),
              checksum_asset: ([($release.assets // [])[]?
                | select((.name // "") | type == "string")
                | select(((.name | ascii_downcase) | test("(sha256|checksums?|checksum)"; "i")))
                | select((.browser_download_url // "") | type == "string")
              ] | first // {})
            }
        ]
        | sort_by(.published_at)
        | reverse
        | first // empty
    ' "$releases_file")" || {
        rm -f -- "$releases_file"
        wsp_aurelia_fail "No stable raw Linux release asset matching $(uname -m) was found for $source."
        return 1
    }

    tag="$(jq -r '.tag // empty' <<< "$candidate_json")"
    body="$(jq -r '.body // empty' <<< "$candidate_json")"
    asset="$(jq -r '.asset // empty' <<< "$candidate_json")"
    artifact_url="$(jq -r '.artifact_url // empty' <<< "$candidate_json")"
    digest="$(jq -r '.digest // empty' <<< "$candidate_json")"
    sidecar_url="$(jq -r '.checksum_asset.browser_download_url // empty' <<< "$candidate_json")"
    rm -f -- "$releases_file"

    if [[ "$digest" =~ ^sha256:[0-9a-fA-F]{64}$ ]]; then
        checksum="${digest,,}"
    elif checksum="$(wsp_aurelia_checksum_from_text "$body" "$asset" 2>/dev/null)"; then
        :
    elif [[ -n "$sidecar_url" ]]; then
        if ! sidecar_file="$(mktemp)"; then
            wsp_aurelia_fail "Could not create a temporary checksum response for $source."
            return 1
        fi
        WSP_AURELIA_TEMP_FILES+=("$sidecar_file")
        if wsp_aurelia_download "$sidecar_url" "$sidecar_file" 60; then
            checksum="$(wsp_aurelia_checksum_from_text "$(<"$sidecar_file")" "$asset" 2>/dev/null || true)"
        fi
        rm -f -- "$sidecar_file"
    fi
    if [[ -z "$checksum" ]]; then
        wsp_aurelia_fail "The selected GitHub release for $source does not publish a SHA-256 checksum for $asset."
        return 1
    fi

    identifier="${WSP_AURELIA_PARSED_REPOSITORY,,}"
    if ! wsp_aurelia_metadata_valid \
        "$source" "$identifier" "$tag" "$asset" "$checksum" \
        ".local/bin/$identifier" "$artifact_url"; then
        wsp_aurelia_fail "GitHub release metadata for $source failed Aurelia safety validation."
        return 1
    fi

    WSP_AURELIA_DISCOVERY_SOURCE="$source"
    WSP_AURELIA_DISCOVERY_IDENTIFIER="$identifier"
    WSP_AURELIA_DISCOVERY_NAME="$identifier"
    WSP_AURELIA_DISCOVERY_SUMMARY="Official GitHub release from $source"
    WSP_AURELIA_DISCOVERY_VERSION="$tag"
    WSP_AURELIA_DISCOVERY_SCOPE="user"
    WSP_AURELIA_DISCOVERY_ASSET="$asset"
    WSP_AURELIA_DISCOVERY_CHECKSUM="$checksum"
    WSP_AURELIA_DISCOVERY_TARGET=".local/bin/$identifier"
    WSP_AURELIA_DISCOVERY_ARTIFACT_URL="$artifact_url"
}

wsp_aurelia_discovery_row() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$WSP_AURELIA_DISCOVERY_SOURCE" \
        "$WSP_AURELIA_DISCOVERY_IDENTIFIER" \
        "$WSP_AURELIA_DISCOVERY_NAME" \
        "$WSP_AURELIA_DISCOVERY_SUMMARY" \
        "$WSP_AURELIA_DISCOVERY_VERSION" \
        "$WSP_AURELIA_DISCOVERY_SCOPE" \
        "$WSP_AURELIA_DISCOVERY_ASSET" \
        "$WSP_AURELIA_DISCOVERY_CHECKSUM" \
        "$WSP_AURELIA_DISCOVERY_TARGET" \
        "$WSP_AURELIA_DISCOVERY_ARTIFACT_URL"
}

wsp_aurelia_catalog_rows() {
    local rows
    local source
    local url
    local profiles
    local status=0

    rows="$(wsp_aurelia_sources_rows)" || return 1
    [[ -n "$rows" ]] || return 0
    while IFS=$'\t' read -r source url profiles; do
        [[ -n "$source" ]] || continue
        if ! wsp_aurelia_discover_source "$source"; then
            if [[ -n "${WSP_REFRESH_ERRORS:-}" ]]; then
                printf 'aurelia/%s: %s\n' "$source" "${WSP_AURELIA_LAST_ERROR:-discovery failed}" >> "$WSP_REFRESH_ERRORS"
            fi
            status=1
            continue
        fi
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
            "$WSP_AURELIA_DISCOVERY_ARTIFACT_URL"
    done <<< "$rows"
    return "$status"
}

wsp_aurelia_source_url_for() {
    local wanted_source="$1"
    local source
    local url
    local profiles

    while IFS=$'\t' read -r source url profiles; do
        [[ "$source" == "$wanted_source" ]] || continue
        printf '%s\n' "$url"
        return 0
    done < <(wsp_aurelia_sources_rows || true)
    return 1
}

wsp_aurelia_resolve_record() {
    local source="$1"
    local identifier="$2"
    local version="${3:-}"
    local asset="${4:-}"
    local checksum="${5:-}"
    local target="${6:-}"
    local artifact_url="${7:-}"
    local source_url

    if [[ -n "$version" && -n "$asset" && -n "$checksum" && -n "$target" && -n "$artifact_url" ]]; then
        if ! wsp_aurelia_metadata_valid "$source" "$identifier" "$version" "$asset" "$checksum" "$target" "$artifact_url"; then
            wsp_aurelia_fail "Pinned Aurelia metadata is invalid for $source/$identifier."
            return 1
        fi
        WSP_AURELIA_DISCOVERY_SOURCE="$source"
        WSP_AURELIA_DISCOVERY_IDENTIFIER="$identifier"
        WSP_AURELIA_DISCOVERY_NAME="$identifier"
        WSP_AURELIA_DISCOVERY_SUMMARY="Official GitHub release from $source"
        WSP_AURELIA_DISCOVERY_VERSION="$version"
        WSP_AURELIA_DISCOVERY_SCOPE="user"
        WSP_AURELIA_DISCOVERY_ASSET="$asset"
        WSP_AURELIA_DISCOVERY_CHECKSUM="$checksum"
        WSP_AURELIA_DISCOVERY_TARGET="$target"
        WSP_AURELIA_DISCOVERY_ARTIFACT_URL="$artifact_url"
        return 0
    fi
    source_url="$(wsp_aurelia_source_url_for "$source" 2>/dev/null || true)"
    [[ -n "$source_url" ]] || source_url="https://$source"
    if ! wsp_aurelia_discover_source "$source_url"; then
        wsp_error "${WSP_AURELIA_LAST_ERROR:-Could not discover Aurelia release metadata for $source.}"
        return 1
    fi
    [[ "$WSP_AURELIA_DISCOVERY_IDENTIFIER" == "$identifier" ]] || {
        wsp_error "GitHub repository $source resolves to '$WSP_AURELIA_DISCOVERY_IDENTIFIER', not '$identifier'."
        return 1
    }
}

wsp_aurelia_home_safe() {
    [[ "${HOME:-}" == /* && "$HOME" != "/" && -d "$HOME" && ! -L "$HOME" && -O "$HOME" ]] || return 1
    wsp_path_components_safe "$HOME"
}

wsp_aurelia_ensure_target_dir() {
    local local_dir
    local bin_dir
    local path

    wsp_aurelia_home_safe || return 1
    local_dir="$HOME/.local"
    bin_dir="$local_dir/bin"
    for path in "$local_dir" "$bin_dir"; do
        wsp_path_components_safe "$path" || return 1
        if [[ -L "$path" || -e "$path" && ! -d "$path" ]]; then
            return 1
        fi
        if [[ ! -e "$path" ]]; then
            mkdir -m 0755 -- "$path" || return 1
        fi
        [[ -d "$path" && ! -L "$path" && -O "$path" && -w "$path" ]] || return 1
    done
}

wsp_aurelia_target_path() {
    local identifier="$1"
    local target="${2:-.local/bin/$identifier}"

    wsp_aurelia_home_safe || return 1
    wsp_aurelia_valid_target "$identifier" "$target" || return 1
    printf '%s/%s\n' "$HOME" "$target"
}

wsp_aurelia_state_dir() {
    local state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
    [[ "$state_home" == /* && "$state_home" != "/" ]] || return 1
    wsp_path_components_safe "$state_home" || return 1
    printf '%s/fedora-hyprland-workstation/package-manager/aurelia\n' "$state_home"
}

wsp_aurelia_ensure_state_dir() {
    local state_dir
    local path

    wsp_aurelia_home_safe || return 1
    state_dir="$(wsp_aurelia_state_dir)" || return 1
    for path in "${XDG_STATE_HOME:-$HOME/.local/state}" \
        "${XDG_STATE_HOME:-$HOME/.local/state}/fedora-hyprland-workstation" \
        "${XDG_STATE_HOME:-$HOME/.local/state}/fedora-hyprland-workstation/package-manager" \
        "$state_dir"; do
        wsp_path_components_safe "$path" || return 1
        if [[ -L "$path" || -e "$path" && ! -d "$path" ]]; then
            return 1
        fi
        if [[ ! -e "$path" ]]; then
            mkdir -m 0700 -- "$path" || return 1
        fi
        [[ -d "$path" && ! -L "$path" && -O "$path" && -w "$path" ]] || return 1
    done
}

wsp_aurelia_marker_path() {
    local identifier="$1"
    wsp_valid_dnf_id "$identifier" || return 1
    printf '%s/%s.owner\n' "$(wsp_aurelia_state_dir)" "$identifier"
}

wsp_aurelia_read_marker() {
    local identifier="$1"
    local marker
    local line
    local key
    local value
    local extra
    local source_count=0
    local checksum_count=0
    local target_count=0

    WSP_AURELIA_MARKER_SOURCE=""
    WSP_AURELIA_MARKER_CHECKSUM=""
    WSP_AURELIA_MARKER_TARGET=""
    marker="$(wsp_aurelia_marker_path "$identifier")" || return 1
    [[ -f "$marker" && ! -L "$marker" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        key=""
        value=""
        extra=""
        IFS='=' read -r key value extra <<< "$line"
        [[ -z "$extra" ]] || return 1
        case "$key" in
            source) WSP_AURELIA_MARKER_SOURCE="$value"; source_count=$((source_count + 1)) ;;
            checksum) WSP_AURELIA_MARKER_CHECKSUM="$value"; checksum_count=$((checksum_count + 1)) ;;
            target) WSP_AURELIA_MARKER_TARGET="$value"; target_count=$((target_count + 1)) ;;
            '') return 1 ;;
            *) return 1 ;;
        esac
    done < "$marker"
    [[ "$source_count" -eq 1 && "$checksum_count" -eq 1 && "$target_count" -eq 1 ]] || return 1
    wsp_aurelia_source_valid "$WSP_AURELIA_MARKER_SOURCE" || return 1
    wsp_aurelia_valid_checksum "$WSP_AURELIA_MARKER_CHECKSUM" || return 1
    wsp_aurelia_valid_target "$identifier" "$WSP_AURELIA_MARKER_TARGET" || return 1
}

wsp_aurelia_marker_matches_target() {
    local identifier="$1"
    local target_path="$2"
    local actual_checksum

    wsp_aurelia_read_marker "$identifier" || return 1
    [[ "$WSP_AURELIA_MARKER_TARGET" == ".local/bin/$identifier" ]] || return 1
    [[ -f "$target_path" && ! -L "$target_path" ]] || return 1
    actual_checksum="$(sha256sum -- "$target_path" | awk '{print $1}')" || return 1
    [[ "sha256:${actual_checksum,,}" == "$WSP_AURELIA_MARKER_CHECKSUM" ]]
}

wsp_aurelia_write_marker() {
    local source="$1"
    local identifier="$2"
    local checksum="$3"
    local target="$4"
    local marker
    local marker_tmp

    wsp_aurelia_metadata_valid "$source" "$identifier" "release" "asset" "$checksum" "$target" \
        "https://github.com/${source#github.com/}/releases/download/release/asset" || return 1
    wsp_aurelia_ensure_state_dir || {
        wsp_error "Could not create the private Aurelia ownership state directory."
        return 1
    }
    marker="$(wsp_aurelia_marker_path "$identifier")" || return 1
    [[ ! -L "$marker" ]] || {
        wsp_error "Refusing to replace a symlinked Aurelia ownership marker: $marker"
        return 1
    }
    marker_tmp="$(mktemp)" || return 1
    WSP_AURELIA_TEMP_FILES+=("$marker_tmp")
    {
        printf 'source=%s\n' "$source"
        printf 'checksum=%s\n' "$checksum"
        printf 'target=%s\n' "$target"
    } > "$marker_tmp"
    if ! wsp_atomic_replace "$marker" "$marker_tmp"; then
        rm -f -- "$marker_tmp"
        return 1
    fi
    rm -f -- "$marker_tmp"
    chmod 0600 -- "$marker"
}

wsp_aurelia_entry_installed() {
    local source="$1"
    local identifier="$2"
    local target="${3:-.local/bin/$identifier}"
    local target_path

    target_path="$(wsp_aurelia_target_path "$identifier" "$target")" || return 1
    wsp_aurelia_marker_matches_target "$identifier" "$target_path" || return 1
    [[ "$WSP_AURELIA_MARKER_SOURCE" == "$source" ]]
}

wsp_aurelia_rollback_target() {
    local target_path="$1"
    local target_backup="${2:-}"
    local failed=0

    if [[ -e "$target_path" || -L "$target_path" ]]; then
        if [[ -f "$target_path" && ! -L "$target_path" ]]; then
            rm -f -- "$target_path" || failed=1
        else
            failed=1
        fi
    fi

    if (( failed == 0 )) &&
        [[ -n "$target_backup" && -e "$target_backup" && ! -L "$target_backup" &&
           ! -e "$target_path" && ! -L "$target_path" ]]; then
        mv -T -- "$target_backup" "$target_path" || failed=1
    fi

    return "$failed"
}

wsp_aurelia_rollback_marker() {
    local marker="$1"
    local marker_backup="${2:-}"
    local failed=0

    if [[ -e "$marker" || -L "$marker" ]]; then
        if [[ -f "$marker" && ! -L "$marker" ]]; then
            rm -f -- "$marker" || failed=1
        else
            failed=1
        fi
    fi

    if (( failed == 0 )) &&
        [[ -n "$marker_backup" && -e "$marker_backup" && ! -L "$marker_backup" &&
           ! -e "$marker" && ! -L "$marker" ]]; then
        mv -T -- "$marker_backup" "$marker" || failed=1
    fi

    return "$failed"
}

wsp_aurelia_install_record() {
    local source="$1"
    local identifier="$2"
    local version="$3"
    local asset="$4"
    local checksum="$5"
    local target="$6"
    local artifact_url="$7"
    local target_path
    local target_dir
    local artifact_tmp
    local install_tmp
    local actual_checksum
    local marker
    local marker_dir
    local target_backup=""
    local marker_backup=""

    wsp_aurelia_metadata_valid "$source" "$identifier" "$version" "$asset" "$checksum" "$target" "$artifact_url" || {
        wsp_error "Invalid pinned Aurelia install metadata for $source/$identifier."
        return 1
    }
    wsp_aurelia_ensure_target_dir || {
        wsp_error "The user-local binary directory is unavailable or unsafe."
        return 1
    }
    target_path="$(wsp_aurelia_target_path "$identifier" "$target")" || return 1
    target_dir="$(dirname -- "$target_path")"
    wsp_target_is_safe "$target_path" || return 1
    marker="$(wsp_aurelia_marker_path "$identifier")" || return 1
    marker_dir="$(dirname -- "$marker")"
    [[ ! -L "$marker" ]] || {
        wsp_error "Refusing to modify a symlinked Aurelia ownership marker: $marker"
        return 1
    }

    if [[ -e "$target_path" ]]; then
        [[ -f "$target_path" && ! -L "$target_path" ]] || {
            wsp_error "Refusing to replace a non-regular Aurelia target: $target_path"
            return 1
        }
        if ! wsp_aurelia_marker_matches_target "$identifier" "$target_path" ||
            [[ "$WSP_AURELIA_MARKER_SOURCE" != "$source" ]]; then
            wsp_error "Refusing to replace an unowned or modified Aurelia target: $target_path"
            return 1
        fi
    elif [[ -f "$marker" ]]; then
        wsp_aurelia_read_marker "$identifier" || {
            wsp_error "Aurelia ownership marker is malformed: $identifier"
            return 1
        }
        [[ "$WSP_AURELIA_MARKER_SOURCE" == "$source" ]] || {
            wsp_error "Aurelia ownership marker belongs to another source: $identifier"
            return 1
        }
    fi

    artifact_tmp="$(mktemp)" || return 1
    WSP_AURELIA_TEMP_FILES+=("$artifact_tmp")
    if ! wsp_aurelia_download "$artifact_url" "$artifact_tmp" 180; then
        rm -f -- "$artifact_tmp"
        wsp_error "Could not download Aurelia release asset: $artifact_url"
        return 1
    fi
    actual_checksum="$(sha256sum -- "$artifact_tmp" | awk '{print $1}')" || {
        rm -f -- "$artifact_tmp"
        return 1
    }
    if [[ "sha256:${actual_checksum,,}" != "$checksum" ]]; then
        rm -f -- "$artifact_tmp"
        wsp_error "Aurelia checksum verification failed for $source/$identifier."
        return 1
    fi

    install_tmp="$(mktemp "$target_dir/.${identifier}.XXXXXX")" || {
        rm -f -- "$artifact_tmp"
        return 1
    }
    WSP_AURELIA_TEMP_FILES+=("$install_tmp")
    if ! cp -- "$artifact_tmp" "$install_tmp" || ! chmod 0755 -- "$install_tmp"; then
        rm -f -- "$artifact_tmp" "$install_tmp"
        return 1
    fi
    rm -f -- "$artifact_tmp"
    actual_checksum="$(sha256sum -- "$install_tmp" | awk '{print $1}')" || {
        rm -f -- "$install_tmp"
        return 1
    }
    if [[ "sha256:${actual_checksum,,}" != "$checksum" ]]; then
        rm -f -- "$install_tmp"
        wsp_error "Aurelia staged binary checksum changed before publication."
        return 1
    fi

    # Preserve the currently owned target and marker until the new target has
    # passed post-install validation and the new ownership marker is durable.
    # If marker publication fails, a future restore must still be able to
    # recognize and repair the previous valid installation.
    if [[ -e "$marker" ]]; then
        [[ -f "$marker" && ! -L "$marker" ]] || {
            wsp_error "Refusing to replace a non-regular Aurelia ownership marker: $marker"
            rm -f -- "$install_tmp"
            return 1
        }
        marker_backup="$(mktemp "$marker_dir/.${identifier}.owner-backup.XXXXXX")" || {
            rm -f -- "$install_tmp"
            return 1
        }
        if ! rm -f -- "$marker_backup" || ! mv -T -- "$marker" "$marker_backup"; then
            rm -f -- "$marker_backup" "$install_tmp"
            return 1
        fi
    fi

    if [[ -e "$target_path" ]]; then
        target_backup="$(mktemp "$target_dir/.${identifier}.target-backup.XXXXXX")" || {
            [[ -n "$marker_backup" ]] && mv -T -- "$marker_backup" "$marker" || true
            rm -f -- "$install_tmp"
            return 1
        }
        if ! rm -f -- "$target_backup" || ! mv -T -- "$target_path" "$target_backup"; then
            rm -f -- "$target_backup" "$install_tmp"
            [[ -n "$marker_backup" ]] && mv -T -- "$marker_backup" "$marker" || true
            return 1
        fi
    fi

    if ! mv -T -- "$install_tmp" "$target_path"; then
        rm -f -- "$install_tmp"
        wsp_aurelia_rollback_target "$target_path" "$target_backup" || true
        wsp_aurelia_rollback_marker "$marker" "$marker_backup" || true
        return 1
    fi
    if ! [[ -x "$target_path" && ! -L "$target_path" ]] ||
        [[ "sha256:$(sha256sum -- "$target_path" | awk '{print tolower($1)}')" != "$checksum" ]]; then
        wsp_error "Aurelia binary failed post-install validation: $target_path"
        wsp_aurelia_rollback_target "$target_path" "$target_backup" || true
        wsp_aurelia_rollback_marker "$marker" "$marker_backup" || true
        return 1
    fi
    wsp_aurelia_write_marker "$source" "$identifier" "$checksum" "$target" || {
        wsp_error "Aurelia binary installed but ownership state could not be recorded: $identifier"
        if ! wsp_aurelia_rollback_target "$target_path" "$target_backup"; then
            wsp_error "Aurelia target rollback was incomplete; inspect: ${target_backup:-$target_path}"
        fi
        if ! wsp_aurelia_rollback_marker "$marker" "$marker_backup"; then
            wsp_error "Aurelia ownership marker rollback was incomplete; inspect: ${marker_backup:-$marker}"
        fi
        return 1
    }
    if [[ -n "$target_backup" ]]; then
        rm -f -- "$target_backup" || wsp_warn "Could not remove temporary Aurelia target backup: $target_backup"
    fi
    if [[ -n "$marker_backup" ]]; then
        rm -f -- "$marker_backup" || wsp_warn "Could not remove temporary Aurelia marker backup: $marker_backup"
    fi
    wsp_info "Installed Aurelia $identifier $version to ~/$target (SHA-256 verified)."
}

wsp_aurelia_adopt_record() {
    local source="$1"
    local identifier="$2"
    local version="$3"
    local asset="$4"
    local checksum="$5"
    local target="$6"
    local artifact_url="$7"
    local target_path
    local actual_checksum

    wsp_aurelia_metadata_valid "$source" "$identifier" "$version" "$asset" "$checksum" "$target" "$artifact_url" || return 1
    target_path="$(wsp_aurelia_target_path "$identifier" "$target")" || return 1
    [[ -f "$target_path" && ! -L "$target_path" && -x "$target_path" ]] || {
        wsp_error "Cannot adopt missing or non-executable Aurelia binary: $target_path"
        return 1
    }
    actual_checksum="$(sha256sum -- "$target_path" | awk '{print $1}')" || return 1
    [[ "sha256:${actual_checksum,,}" == "$checksum" ]] || {
        wsp_error "Cannot adopt Aurelia binary because its checksum does not match the pinned release."
        return 1
    }
    wsp_aurelia_write_marker "$source" "$identifier" "$checksum" "$target" || return 1
    wsp_info "Adopted Aurelia $identifier $version after checksum verification."
}

wsp_aurelia_remove_record() {
    local source="$1"
    local identifier="$2"
    local target="${3:-.local/bin/$identifier}"
    local target_path
    local marker

    wsp_aurelia_source_valid "$source" || return 1
    wsp_valid_dnf_id "$identifier" || return 1
    target_path="$(wsp_aurelia_target_path "$identifier" "$target")" || return 1
    marker="$(wsp_aurelia_marker_path "$identifier")" || return 1
    wsp_aurelia_read_marker "$identifier" || {
        wsp_error "Refusing to remove an Aurelia target without a valid ownership marker: $target_path"
        return 1
    }
    [[ "$WSP_AURELIA_MARKER_SOURCE" == "$source" && "$WSP_AURELIA_MARKER_TARGET" == "$target" ]] || {
        wsp_error "Aurelia ownership metadata does not match the requested package: $identifier"
        return 1
    }
    if [[ -e "$target_path" ]]; then
        wsp_aurelia_marker_matches_target "$identifier" "$target_path" || {
            wsp_error "Refusing to remove a modified Aurelia binary: $target_path"
            return 1
        }
        rm -f -- "$target_path"
    fi
    rm -f -- "$marker"
    wsp_info "Removed Aurelia $identifier from ~/$target; personal files were not purged."
}
