#!/usr/bin/env bash

# Wallhaven source integration.
#
# Wallhaven is treated as a remote wallpaper source, not as a software
# repository: results are metadata, and a download only becomes a library entry
# after it passes host allowlisting, size bounds, and an image signature check.
#
# Safety defaults:
#   - SFW-only purity unless the caller explicitly widens the filter.
#   - The API key is read from a 0600 file and is never printed or passed in
#     argv, so it cannot leak through process listings or logs.

aurelia_wallpaper_wallhaven_key_status() {
    local raw_key=""

    if [[ -f "$AW_WALLHAVEN_KEY_FILE" && ! -L "$AW_WALLHAVEN_KEY_FILE" ]]; then
        raw_key="$(jq -r '.api_key // empty' "$AW_WALLHAVEN_KEY_FILE" || true)"
    fi
    if [[ -n "$raw_key" ]]; then
        printf 'configured\n'
    else
        printf 'not-configured\n'
    fi
}

aurelia_wallpaper_wallhaven_key_read() {
    local raw_key=""

    [[ -f "$AW_WALLHAVEN_KEY_FILE" && ! -L "$AW_WALLHAVEN_KEY_FILE" ]] || return 1
    raw_key="$(jq -r '.api_key // empty' "$AW_WALLHAVEN_KEY_FILE" || true)"
    [[ -n "$raw_key" ]] || return 1
    printf '%s\n' "$raw_key"
}

# The key is accepted only through stdin. An argv form would expose the secret
# to every process on the machine through /proc/<pid>/cmdline.
aurelia_wallpaper_wallhaven_key_set() {
    local raw_key=""

    IFS= read -r raw_key || true
    raw_key="${raw_key//[$'\r\n\t ']/}"
    [[ -n "$raw_key" ]] ||
        aurelia_wallpaper_fail "No wallhaven API key was provided on stdin."
    [[ "$raw_key" =~ ^[A-Za-z0-9_-]{16,64}$ ]] ||
        aurelia_wallpaper_fail "Wallhaven API key has an unexpected format."

    aurelia_wallpaper_lock || return 1
    aurelia_wallpaper_atomic_text \
        "$(jq -n --arg key "$raw_key" '{api_key:$key}')" \
        "$AW_WALLHAVEN_KEY_FILE" || return 1
    chmod 0600 -- "$AW_WALLHAVEN_KEY_FILE"
    printf 'Wallhaven API key stored.\n'
}

aurelia_wallpaper_url_encode() {
    jq -rn --arg value "$1" '$value|@uri'
}

aurelia_wallpaper_wallhaven_search_url() {
    local query="$1"
    local categories="$2"
    local purity="$3"
    local sorting="$4"
    local order="$5"
    local atleast="$6"
    local page="$7"
    local seed="$8"
    local api_key="$9"
    local url="https://wallhaven.cc/api/v1/search"
    local separator="?"
    local pair=""
    local name=""
    local value=""

    for pair in \
        "categories=$categories" \
        "purity=$purity" \
        "sorting=$sorting" \
        "order=$order" \
        "atleast=$atleast" \
        "page=$page" \
        "seed=$seed" \
        "q=$query" \
        "apikey=$api_key"; do
        name="${pair%%=*}"
        value="${pair#*=}"
        [[ -n "$value" ]] || continue
        url="${url}${separator}${name}=$(aurelia_wallpaper_url_encode "$value")"
        separator="&"
    done

    printf '%s\n' "$url"
}

aurelia_wallpaper_wallhaven_fetch_json() {
    local url="$1"
    local response_file=""

    aurelia_wallpaper_prepare_cache || return 1
    response_file="$(mktemp "$AW_DOWNLOAD_ROOT/response-XXXXXX.json")" ||
        aurelia_wallpaper_fail "Could not create a wallhaven response staging file."

    if ! aurelia_wallpaper_http_fetch "$url" "$response_file" \
        "$AW_SEARCH_TIMEOUT" "$AW_MAX_DOWNLOAD_BYTES"; then
        rm -f -- "$response_file"
        return 1
    fi

    if ! jq -e 'type == "object"' "$response_file" >/dev/null; then
        rm -f -- "$response_file"
        aurelia_wallpaper_fail "Wallhaven returned a response that is not valid JSON."
        return 1
    fi

    cat -- "$response_file"
    rm -f -- "$response_file"
}

# Search results are metadata only. Every returned URL must be HTTPS on an
# allowlisted host, so a compromised or misdirected response cannot make the
# shell or the CLI contact an arbitrary endpoint.
aurelia_wallpaper_wallhaven_normalize() {
    local response="$1"
    local hosts="$2"
    local limit="$3"

    jq -c \
        --arg hosts "$hosts" \
        --argjson limit "$limit" '
        def host_of($u): ($u | sub("^https://"; "") | split("/")[0] | split("@")[-1] | split(":")[0]);
        def allowed($u): (($u | startswith("https://")) and (($hosts | split(" ")) | index(host_of($u)) != null));
        {
          page: (.meta.current_page // 1),
          lastPage: (.meta.last_page // 1),
          total: (.meta.total // 0),
          perPage: (.meta.per_page // 0),
          results: ([
            (.data // [])[]
            | select(.id != null)
            | {
                id: (.id | tostring),
                resolution: (.resolution // "" | tostring),
                category: (.category // "" | tostring),
                purity: (.purity // "" | tostring),
                fileSize: (.file_size // 0),
                thumb: ((.thumbs.small // .thumbs.original // "") | tostring),
                page: ((.url // "") | tostring),
                path: ((.path // "") | tostring)
              }
            | select(allowed(.thumb) and ((.path == "") or allowed(.path)))
          ] | .[0:$limit])
        }' <<<"$response"
}

aurelia_wallpaper_wallhaven_search() {
    local query="$1"
    local categories="$2"
    local purity="$3"
    local sorting="$4"
    local order="$5"
    local atleast="$6"
    local page="$7"
    local seed="$8"
    local mode="$9"
    local with_thumbs="${10:-0}"
    local api_key=""
    local url=""
    local response=""
    local normalized=""

    api_key="$(aurelia_wallpaper_wallhaven_key_read  || true)"
    url="$(aurelia_wallpaper_wallhaven_search_url \
        "$query" "$categories" "$purity" "$sorting" "$order" \
        "$atleast" "$page" "$seed" "$api_key")" || return 1

    response="$(aurelia_wallpaper_wallhaven_fetch_json "$url")" || return 1
    jq -e 'type == "object"' <<<"$response" >/dev/null ||
        aurelia_wallpaper_fail "Wallhaven response is not an object."
    if ! jq -e '(.data | type) == "array"' <<<"$response" >/dev/null; then
        local api_error=""
        api_error="$(jq -r '.error // empty' <<<"$response" || true)"
        aurelia_wallpaper_fail "Wallhaven search failed${api_error:+: $api_error}"
    fi

    normalized="$(aurelia_wallpaper_wallhaven_normalize \
        "$response" "$AW_WALLHAVEN_ALLOWED_HOSTS" "$AW_CFG_WALLHAVEN_PAGE_SIZE")" || return 1

    if [[ "$mode" == "json" ]]; then
        printf '%s\n' "$normalized"
        return 0
    fi

    if [[ "$mode" == "rows" ]]; then
        # Row shape: id, thumbnail, resolution, purity, page URL.
        # Without --thumbs the thumbnail is the remote preview URL; with
        # --thumbs it is a cached local preview so the UI never fetches the
        # network itself.
        local id=""
        local resolution=""
        local thumb=""
        local path_url=""
        local category=""
        local purity_value=""
        local page_url=""
        local cached=""
        local fetched=0

        while IFS=$'\t' read -r id resolution thumb path_url purity_value page_url; do
            [[ -n "$id" ]] || continue
            cached=""
            if aurelia_wallpaper_setting_is_true "$with_thumbs" &&
                [[ -n "$thumb" ]] && (( fetched < AW_WALLHAVEN_THUMB_LIMIT )); then
                cached="$(aurelia_wallpaper_wallhaven_thumb "$id" "$thumb"  || true)"
                if [[ -n "$cached" ]]; then
                    fetched=$((fetched + 1))
                fi
            fi
            printf '%s\t%s\t%s\t%s\t%s\n' \
                "$id" "${cached:-$thumb}" "$resolution" "$purity_value" "$page_url"
        done < <(jq -r '.results[] | [.id, .resolution, .thumb, .path, .purity, .page] | @tsv' \
            <<<"$normalized")
        return 0
    fi

    aurelia_wallpaper_fail "Unsupported wallhaven search output mode: $mode"
}

# Preview images are cached through the same bounded fetch path as wallpapers.
aurelia_wallpaper_wallhaven_thumb() {
    local wallpaper_id="$1"
    local thumb_url="$2"
    local extension=""
    local destination=""

    [[ "$wallpaper_id" =~ ^[A-Za-z0-9]{3,32}$ ]] || return 1
    extension="$(aurelia_wallpaper_url_extension "$thumb_url"  || true)"
    [[ -n "$extension" ]] || return 1

    aurelia_wallpaper_prepare_cache >/dev/null || return 1
    destination="$AW_THUMB_ROOT/$wallpaper_id.$extension"
    if [[ -f "$destination" && ! -L "$destination" ]]; then
        printf '%s\n' "$destination"
        return 0
    fi

    aurelia_wallpaper_fetch_image "$thumb_url" "$destination" >/dev/null || return 1
    printf '%s\n' "$destination"
}
# One authoritative detail lookup. The download path is taken from this
# response rather than from a search result, so the file that is fetched is the
# file wallhaven reports for that id.
aurelia_wallpaper_wallhaven_detail() {
    local wallpaper_id="$1"
    local api_key=""
    local url=""
    local response=""

    api_key="$(aurelia_wallpaper_wallhaven_key_read  || true)"
    url="https://wallhaven.cc/api/v1/w/$(aurelia_wallpaper_url_encode "$wallpaper_id")"
    if [[ -n "$api_key" ]]; then
        url="${url}?apikey=$(aurelia_wallpaper_url_encode "$api_key")"
    fi

    response="$(aurelia_wallpaper_wallhaven_fetch_json "$url")" || return 1
    if ! jq -e '(.data | type) == "object"' <<<"$response" >/dev/null; then
        aurelia_wallpaper_fail "Wallhaven did not return a detail record for: $wallpaper_id"
        return 1
    fi
    jq -c '{meta:{current_page:1,last_page:1,total:1,per_page:1}, data:[.data]}' <<<"$response"
}

aurelia_wallpaper_wallhaven_download() {
    local wallpaper_id="$1"
    local target_source="${2:-library}"
    local detail=""
    local normalized=""
    local purity_value=""
    local path_url=""
    local page_url=""
    local file_size="0"
    local extension=""
    local directory=""
    local download_dir=""
    local destination=""
    local existing_size="0"

    [[ "$wallpaper_id" =~ ^[A-Za-z0-9]{3,32}$ ]] ||
        aurelia_wallpaper_fail "Invalid wallhaven wallpaper id: $wallpaper_id"

    detail="$(aurelia_wallpaper_wallhaven_detail "$wallpaper_id")" || return 1
    normalized="$(aurelia_wallpaper_wallhaven_normalize "$detail" "$AW_WALLHAVEN_ALLOWED_HOSTS" 1)" ||
        return 1

    purity_value="$(jq -r '.results[0].purity // empty' <<<"$normalized")"
    path_url="$(jq -r '.results[0].path // empty' <<<"$normalized")"
    page_url="$(jq -r '.results[0].page // empty' <<<"$normalized")"
    file_size="$(jq -r '.results[0].fileSize // 0' <<<"$normalized")"

    [[ -n "$path_url" ]] ||
        aurelia_wallpaper_fail "Wallhaven did not provide a downloadable path for $wallpaper_id."
    # Fail closed on anything but a safe-for-work result unless the caller has
    # explicitly widened the purity filter for the search that produced the id.
    [[ "$purity_value" == "sfw" ]] ||
        aurelia_wallpaper_fail "Refusing to download a non-SFW wallpaper ($wallpaper_id is ${purity_value:-unknown})."

    extension="$(aurelia_wallpaper_url_extension "$path_url"  || true)"
    [[ -n "$extension" ]] ||
        aurelia_wallpaper_fail "Wallhaven download URL has an unsupported extension: $path_url"

    directory="$(aurelia_wallpaper_import_target_dir "$target_source")" || return 1
    download_dir="$directory/wallhaven"
    aurelia_wallpaper_mkdir "$download_dir" "Wallhaven library folder" || return 1

    destination="$download_dir/wallhaven-$wallpaper_id.$extension"
    if [[ -f "$destination" && ! -L "$destination" ]]; then
        existing_size="$(stat -c '%s' -- "$destination" || printf '0')"
        if [[ "$file_size" =~ ^[0-9]+$ && "$file_size" -gt 0 && "$existing_size" == "$file_size" ]]; then
            printf '%s\n' "$destination"
            return 0
        fi
    fi

    aurelia_wallpaper_fetch_image "$path_url" "$destination" || return 1
    aurelia_wallpaper_record_download \
        "wallhaven" "$wallpaper_id" "$path_url" "$destination" \
        "$AW_FETCHED_SHA256" "$page_url" || true
    printf '%s\n' "$destination"
}
