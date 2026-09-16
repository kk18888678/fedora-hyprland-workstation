#!/usr/bin/env bash

# Remote wallpaper catalog: the bjarneo wallpapers index
# (https://bjarneo.github.io/wallpapers/).
#
# The catalog is a static, client-side-searched index. The index is fetched
# once into the regenerable cache and reused until it expires, and every media
# URL is derived from a storage base URL that is validated against the pinned
# allowlist before anything is downloaded.
#
# Safety properties:
#   - the index host and the storage host are pinned in this repository;
#   - a catalog that declares a different storage host fails closed;
#   - media paths coming from the index may not carry a scheme or traversal;
#   - downloads go through the same bounded, signature-checked pipeline as
#     wallhaven and are never executed.

# Extract the JSON document from the catalog's JavaScript wrapper.
aurelia_wallpaper_catalog_json() {
    sed \
        -e '/^window\.[A-Za-z_][A-Za-z_]*[[:space:]]*=[[:space:]]*"/d' \
        -e 's/^window\.[A-Za-z_][A-Za-z_]*[[:space:]]*=[[:space:]]*//' \
        -e 's/;[[:space:]]*$//' "$1"
}

aurelia_wallpaper_catalog_declared_base_url() {
    sed -n 's/^window\.WALLPAPERS_BASE_URL[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$1" |
        head -n 1
}

aurelia_wallpaper_catalog_validate_index() {
    local index_file="$1"

    if ! aurelia_wallpaper_catalog_json "$index_file" |
        jq -e 'type == "object"' >/dev/null; then
        return 1
    fi
    return 0
}

# The index is cached for AW_CATALOG_INDEX_TTL seconds. A failed refresh falls
# back to the stale cached copy, because an expired catalog is still better
# than no catalog; a fresh failure is always reported.
aurelia_wallpaper_catalog_ensure_index() {
    local live="$1"
    local refresh="$2"
    local url="$AW_CATALOG_INDEX_URL"
    local name="wallpapers.js"

    if [[ "$live" == "1" ]]; then
        url="$AW_CATALOG_LIVE_URL"
        name="live.js"
    fi

    aurelia_wallpaper_prepare_cache || return 1
    aurelia_wallpaper_mkdir "$AW_CATALOG_INDEX_ROOT" "Wallpaper catalog cache" || return 1
    local index_path="$AW_CATALOG_INDEX_ROOT/$name"

    if [[ ! -L "$index_path" && -f "$index_path" && "$refresh" != "1" ]]; then
        local now=""
        local modified=""
        now="$(date +%s)"
        modified="$(stat -c '%Y' -- "$index_path")"
        if [[ "$modified" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ ]] &&
            (( now - modified < AW_CATALOG_INDEX_TTL )); then
            printf '%s\n' "$index_path"
            return 0
        fi
    fi

    local staging=""
    staging="$(mktemp "$AW_CATALOG_INDEX_ROOT/.index-XXXXXX")" ||
        aurelia_wallpaper_fail "Could not create a catalog index staging file."

    if ! aurelia_wallpaper_http_fetch "$url" "$staging" \
        "$AW_CATALOG_INDEX_TIMEOUT" "$AW_CATALOG_INDEX_MAX_BYTES" \
        "$AW_CATALOG_ALLOWED_HOSTS"; then
        local failure_message="${AW_HTTP_FAILURE_MESSAGE:-Catalog index fetch failed: $url}"
        rm -f -- "$staging"
        if [[ ! -L "$index_path" && -s "$index_path" ]] &&
            aurelia_wallpaper_catalog_validate_index "$index_path"; then
            printf 'Warning: keeping the cached catalog index after a failed refresh.\n' >&2
            printf '%s\n' "$index_path"
            return 0
        fi
        aurelia_wallpaper_fail "$failure_message"
        return 1
    fi

    if ! aurelia_wallpaper_catalog_validate_index "$staging"; then
        rm -f -- "$staging"
        aurelia_wallpaper_fail "Catalog index is not a valid wallpaper index: $url"
        return 1
    fi

    # The declared storage host is checked before the index is published, so a
    # foreign-host index can never enter the cache.
    if [[ -z "$(aurelia_wallpaper_catalog_base_url_or_empty "$staging")" ]]; then
        rm -f -- "$staging"
        aurelia_wallpaper_fail "Catalog index declares a non-allowlisted storage host: $url"
        return 1
    fi

    aurelia_wallpaper_atomic_move "$staging" "$index_path" || return 1
    printf '%s\n' "$index_path"
}

# The storage base URL is declared by the index itself. Trusting it blindly
# would let a compromised index point downloads anywhere, so the declared host
# must be one of the pinned catalog hosts.
# Non-exiting variant for pre-publication validation inside cleanup paths.
aurelia_wallpaper_catalog_base_url_or_empty() {
    local index_path="$1"
    local declared=""

    declared="$(aurelia_wallpaper_catalog_declared_base_url "$index_path")"
    [[ -n "$declared" ]] || declared="$AW_CATALOG_DEFAULT_BASE_URL"

    if aurelia_wallpaper_host_allowed "$declared" "$AW_CATALOG_ALLOWED_HOSTS"; then
        printf '%s\n' "${declared%/}"
    fi
}

aurelia_wallpaper_catalog_base_url() {
    local declared=""

    declared="$(aurelia_wallpaper_catalog_base_url_or_empty "$1")"
    [[ -n "$declared" ]] ||
        aurelia_wallpaper_fail "Catalog index declares a non-allowlisted storage host."
    printf '%s\n' "$declared"
}
# Client-side catalog search. Row shape (TSV):
#   id (storage key), thumbnail, label, resolution, purity, page URL
# The storage base URL is already allowlist-validated by the caller. Media
# paths taken from the index are rejected when they carry a scheme or
# traversal, so every published URL stays on the pinned storage host.
aurelia_wallpaper_catalog_normalize() {
    local index_path="$1"
    local query="$2"
    local base_url="$3"
    local limit="$4"

    jq -c \
        --arg query "$query" \
        --arg base "$base_url" \
        --argjson limit "$limit" '
        def entry_label:
          (.value.title // .value.description // .key | tostring);
        def entry_thumb($base):
          (.value.medium_path // "") as $medium
          | (if $medium == "" then ($base + "/" + .key) else ($base + "/" + $medium) end);
        [ to_entries[]
          | .key as $key
          | select(($query == "") or
              (((($key + " " + (entry_label) + " " +
                  ((.value.tags // []) | join(" ")) + " " +
                  (.value.color // "") + " " + (.value.theme // ""))
                | ascii_downcase) | contains($query))))
          | (.value.medium_path // "") as $medium
          | select(($medium | contains("..")) | not)
          | select(($medium | startswith("http")) | not)
          | select(($medium | startswith("//")) | not)
          | {
              id: $key,
              thumb: entry_thumb($base),
              label: entry_label,
              resolution: ((.value.dimensions // "") | tostring),
              purity: "sfw",
              page: ($base + "/" + $key),
              size: (.value.size_bytes // 0)
            }
        ] | sort_by(.id) | .[0:$limit]' \
        <(aurelia_wallpaper_catalog_json "$index_path")
}

aurelia_wallpaper_catalog_thumb() {
    local key="$1"
    local url="$2"
    local extension=""
    local destination=""
    local safe_id=""

    [[ "$key" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || return 1
    extension="$(aurelia_wallpaper_url_extension "$url"  || true)"
    [[ -n "$extension" ]] || return 1

    aurelia_wallpaper_prepare_cache >/dev/null || return 1
    safe_id="${key//\//_}"
    destination="$AW_THUMB_ROOT/catalog-$safe_id.$extension"
    if [[ -f "$destination" && ! -L "$destination" ]]; then
        printf '%s\n' "$destination"
        return 0
    fi

    aurelia_wallpaper_fetch_image "$url" "$destination" \
        "$AW_CATALOG_ALLOWED_HOSTS" >/dev/null || return 1
    printf '%s\n' "$destination"
}

aurelia_wallpaper_catalog_search() {
    local query="$1"
    local mode="$2"
    local with_thumbs="$3"
    local refresh="$4"
    local live="$5"
    local index_path=""
    local base_url=""
    local normalized=""

    index_path="$(aurelia_wallpaper_catalog_ensure_index "$live" "$refresh")" || return 1
    base_url="$(aurelia_wallpaper_catalog_base_url "$index_path")" || return 1
    normalized="$(aurelia_wallpaper_catalog_normalize \
        "$index_path" "$query" "$base_url" "$AW_CFG_WALLHAVEN_PAGE_SIZE" | \
        jq -c --arg query "$query" --argjson live "$live" \
        '{provider: "bjarneo-catalog", query: $query, live: ($live == 1), results: .}')" || return 1

    if [[ "$mode" == "json" ]]; then
        printf '%s\n' "$normalized"
        return 0
    fi

    if [[ "$mode" == "rows" ]]; then
        # Row shape: id, thumbnail, label, resolution, purity, page URL.
        # Without --thumbs the thumbnail is the remote preview URL; with
        # --thumbs it is a cached local preview so the UI never fetches the
        # network itself.
        local id=""
        local thumb=""
        local label=""
        local resolution=""
        local purity_value=""
        local page_url=""
        local cached=""
        local fetched=0

        while IFS=$'\t' read -r id thumb label resolution purity_value page_url; do
            [[ -n "$id" ]] || continue
            cached=""
            if [[ "$with_thumbs" == "1" && -n "$thumb" ]] &&
                (( fetched < AW_WALLHAVEN_THUMB_LIMIT )); then
                cached="$(aurelia_wallpaper_catalog_thumb "$id" "$thumb"  || true)"
                if [[ -n "$cached" ]]; then
                    fetched=$((fetched + 1))
                fi
            fi
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$id" "${cached:-$thumb}" "$label" "$resolution" "$purity_value" "$page_url"
        done < <(jq -r '.results[] | [.id, .thumb, .label, .resolution, .purity, .page] | @tsv' \
            <<<"$normalized")
        return 0
    fi

    aurelia_wallpaper_fail "Unsupported catalog output mode: $mode"
}

# Publish a catalog wallpaper into a library source. The storage key selects
# the index entry; the published file is named after the key with the
# directory separators folded, and re-downloads are skipped when the stored
# size already matches the index (or when the catalog does not declare one).
aurelia_wallpaper_catalog_key_is_safe() {
    local key="$1"

    [[ "$key" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || return 1
    [[ "$key" != *".."* ]] || return 1
    [[ "$key" != *"//"* ]] || return 1
    return 0
}

aurelia_wallpaper_catalog_download() {
    local key="$1"
    local target_source="${2:-library}"
    local live="0"
    local index_path=""
    local base_url=""
    local entry=""
    local extension=""
    local size="0"
    local directory=""
    local download_dir=""
    local destination=""
    local existing_size="0"
    local url=""

    if [[ "$key" == live/* ]]; then
        live="1"
    fi

    if ! aurelia_wallpaper_catalog_key_is_safe "$key"; then
        aurelia_wallpaper_fail "Invalid catalog wallpaper key: $key"
        return 1
    fi

    index_path="$(aurelia_wallpaper_catalog_ensure_index "$live" 0)" || return 1
    base_url="$(aurelia_wallpaper_catalog_base_url "$index_path")" || return 1

    entry="$(aurelia_wallpaper_catalog_json "$index_path" |
        jq -c --arg key "$key" \
        'to_entries[] | select(.key == $key) |
         {size: (.value.size_bytes // 0)}' | head -n 1)"
    [[ -n "$entry" ]] ||
        aurelia_wallpaper_fail "Key not found in the catalog index: $key"

    extension="$(aurelia_wallpaper_url_extension "$key"  || true)"
    [[ -n "$extension" ]] ||
        aurelia_wallpaper_fail "Catalog wallpaper key has an unsupported extension: $key"

    size="$(jq -r '.size // 0' <<<"$entry")"

    directory="$(aurelia_wallpaper_import_target_dir "$target_source")" || return 1
    download_dir="$directory/catalog"
    aurelia_wallpaper_mkdir "$download_dir" "Catalog library folder" || return 1

    destination="$download_dir/${key//\//_}"
    if [[ -f "$destination" && ! -L "$destination" ]]; then
        existing_size="$(stat -c '%s' -- "$destination")"
        if [[ "$size" =~ ^[0-9]+$ ]] &&
            { [[ "$size" == "0" ]] || [[ "$existing_size" == "$size" ]]; }; then
            printf '%s\n' "$destination"
            return 0
        fi
    fi

    url="$base_url/$key"
    aurelia_wallpaper_fetch_image "$url" "$destination" \
        "$AW_CATALOG_ALLOWED_HOSTS" || return 1
    aurelia_wallpaper_record_download \
        "bjarneo-catalog" "$key" "$url" "$destination" \
        "$AW_FETCHED_SHA256" "$url" || true
    printf '%s\n' "$destination"
}
