#!/usr/bin/env bash

# Local wallpaper library operations.
#
# This module owns local source discovery, library imports, and the delegation
# of activation to the existing background command. It never writes the active
# wallpaper state itself.

# Stable, deterministic enumeration of one local source. Only regular files are
# returned: a symlink may exist in the directory, but it is never followed into
# another location, and hidden files are ignored.
aurelia_wallpaper_collect_source() {
    local source_id="$1"
    local directory=""

    directory="$(aurelia_wallpaper_source_path_for "$source_id")" || return 1
    [[ -d "$directory" ]] || return 0

    find -P "$directory" -maxdepth 3 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \
           -o -iname '*.bmp' -o -iname '*.webp' -o -iname '*.mp4' -o -iname '*.m4v' \
           -o -iname '*.mov' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.avi' \) \
        -print0 | LC_ALL=C sort -z -u
}

aurelia_wallpaper_local_source_ids() {
    local index
    local id="library"

    if aurelia_wallpaper_source_enabled "$id"; then
        printf '%s\n' "$id"
    fi
    for index in ${AW_CFG_SOURCE_IDS[@]+"${!AW_CFG_SOURCE_IDS[@]}"}; do
        id="${AW_CFG_SOURCE_IDS[$index]}"
        aurelia_wallpaper_source_enabled "$id" || continue
        printf '%s\n' "$id"
    done
}

aurelia_wallpaper_collect_selected() {
    local requested="${1:-all}"
    local id=""

    if [[ "$requested" != "all" ]]; then
        local record=""
        record="$(aurelia_wallpaper_source_record "$requested")" ||
            aurelia_wallpaper_fail "Unknown wallpaper source: $requested"
        [[ "$(cut -f2 <<<"$record")" != "remote" ]] ||
            aurelia_wallpaper_fail "Wallpaper source is not a local directory: $requested"
        aurelia_wallpaper_collect_source "$requested"
        return
    fi

    while IFS= read -r id; do
        aurelia_wallpaper_collect_source "$id"
    done < <(aurelia_wallpaper_local_source_ids) | LC_ALL=C sort -z -u
}

aurelia_wallpaper_source_of_path() {
    local path="$1"
    local id=""
    local directory=""

    while IFS= read -r id; do
        directory="$(aurelia_wallpaper_source_path_for "$id"  || true)"
        [[ -n "$directory" ]] || continue
        if [[ "$path" == "$directory/"* ]]; then
            printf '%s\n' "$id"
            return 0
        fi
    done < <(aurelia_wallpaper_local_source_ids)
    printf '%s\n' "external"
}

aurelia_wallpaper_current_path() {
    local current=""

    if [[ -f "$AW_BACKGROUND_PATH" && ! -L "$AW_BACKGROUND_PATH" ]]; then
        current="$(sed -n '1p' "$AW_BACKGROUND_PATH")"
    fi
    if [[ -n "$current" && "$current" == /* && -f "$current" ]]; then
        printf '%s\n' "$current"
        return 0
    fi
    return 1
}

# Activation is delegated: aurelia-theme-bg remains the only writer of the
# active background state, and it owns the live shell reload boundary.
aurelia_wallpaper_activate() {
    local path="$1"

    [[ -x "$AW_THEME_BG_BIN" ]] ||
        aurelia_wallpaper_fail "Aurelia background command is unavailable: $AW_THEME_BG_BIN"
    "$AW_THEME_BG_BIN" set "$path"
}

aurelia_wallpaper_resolve_apply_target() {
    local candidate="$1"
    local resolved=""

    [[ -n "$candidate" ]] ||
        aurelia_wallpaper_fail "A wallpaper path is required."
    [[ "$candidate" == /* ]] ||
        aurelia_wallpaper_fail "A wallpaper path must be absolute: $candidate"
    [[ "$candidate" != *$'\n'* && "$candidate" != *$'\r'* ]] ||
        aurelia_wallpaper_fail "Wallpaper path contains control characters."
    aurelia_wallpaper_is_supported_image "$candidate" ||
        aurelia_wallpaper_fail "Unsupported wallpaper type (expected an image or video file): $candidate"
    resolved="$(readlink -f -- "$candidate"  || true)"
    [[ -n "$resolved" && -f "$resolved" && "$resolved" != "/" ]] ||
        aurelia_wallpaper_fail "Wallpaper file does not exist: $candidate"
    # Extension alone is not proof of content: apply only what really is media.
    aurelia_wallpaper_signature_matches "$resolved" ||
        aurelia_wallpaper_fail "File content does not match its media type: $candidate"
    printf '%s\n' "$resolved"
}

# Reuse the existing theme thumbnail boundary: stills resolve to their own path
# and video frames use the bounded ffmpegthumbnailer cache.
aurelia_wallpaper_thumbnail_for() {
    local path="$1"
    local thumbnail=""

    thumbnail="$(aurelia_theme_thumbnail_for "$path" || true)"
    [[ -n "$thumbnail" ]] || thumbnail="$path"
    printf '%s\n' "$thumbnail"
}

aurelia_wallpaper_cmd_sources() {
    local wants_json="${1:-0}"
    local row=""
    local id=""
    local kind=""
    local path=""
    local exists=""
    local enabled=""

    if aurelia_wallpaper_setting_is_true "$wants_json"; then
        local rows="[]"
        while IFS= read -r row; do
            id="$(cut -f1 <<<"$row")"
            kind="$(cut -f2 <<<"$row")"
            path="$(cut -f3 <<<"$row")"
            exists="$(cut -f4 <<<"$row")"
            enabled="$(aurelia_wallpaper_source_enabled "$id" && printf '1' || printf '0')"
            rows="$(jq -c \
                --arg id "$id" \
                --arg kind "$kind" \
                --arg path "$path" \
                --argjson exists "$exists" \
                --arg enabled "$enabled" \
                '. + [{id:$id,kind:$kind,path:$path,exists:($exists == 1),enabled:($enabled == "1")}]' \
                <<<"$rows")"
        done < <(aurelia_wallpaper_source_rows)
        jq -n --argjson sources "$rows" '{sources:$sources}'
        return 0
    fi

    printf '%-14s %-10s %-9s %s\n' "ID" "KIND" "STATE" "PATH"
    while IFS= read -r row; do
        id="$(cut -f1 <<<"$row")"
        kind="$(cut -f2 <<<"$row")"
        path="$(cut -f3 <<<"$row")"
        exists="$(cut -f4 <<<"$row")"
        local state=""
        if ! aurelia_wallpaper_source_enabled "$id"; then
            state="disabled"
        elif [[ "$exists" == "1" ]]; then
            state="ready"
        else
            state="missing"
        fi
        printf '%-14s %-10s %-9s %s\n' "$id" "$kind" "$state" "$path"
    done < <(aurelia_wallpaper_source_rows)
}

aurelia_wallpaper_cmd_list() {
    local requested="${1:-all}"
    local mode="${2:-plain}"
    local path=""
    local current=""
    local count=0
    local record=""

    if [[ "$requested" != "all" ]]; then
        record="$(aurelia_wallpaper_source_record "$requested")" ||
            aurelia_wallpaper_fail "Unknown wallpaper source: $requested"
        [[ "$(cut -f2 <<<"$record")" != "remote" ]] ||
            aurelia_wallpaper_fail "Wallpaper source is not a local directory: $requested"
    fi

    current="$(aurelia_wallpaper_current_path  || true)"

    if [[ "$mode" == "rows" ]]; then
        while IFS= read -r -d '' path; do
            printf '%s\t%s\t%s\t%s\t%s\n' \
                "$path" \
                "$(aurelia_wallpaper_thumbnail_for "$path")" \
                "$(aurelia_wallpaper_label_for "$path")" \
                "$(aurelia_wallpaper_source_of_path "$path")" \
                "$([[ "$path" == "$current" ]] && printf '1' || printf '0')"
        done < <(aurelia_wallpaper_collect_selected "$requested")
        return 0
    fi

    if [[ "$mode" == "json" ]]; then
        local items="[]"
        while IFS= read -r -d '' path; do
            count=$((count + 1))
            items="$(jq -c \
                --arg path "$path" \
                --arg label "$(aurelia_wallpaper_label_for "$path")" \
                --arg source "$(aurelia_wallpaper_source_of_path "$path")" \
                --arg current "$([[ "$path" == "$current" ]] && printf '1' || printf '0')" \
                '. + [{path:$path,label:$label,source:$source,current:($current == "1")}]' \
                <<<"$items")"
        done < <(aurelia_wallpaper_collect_selected "$requested")
        jq -n \
            --arg source "$requested" \
            --arg current "${current:-}" \
            --argjson count "$count" \
            --argjson wallpapers "$items" \
            '{source:$source,current:$current,count:$count,wallpapers:$wallpapers}'
        return 0
    fi

    while IFS= read -r -d '' path; do
        printf '%s\n' "$path"
    done < <(aurelia_wallpaper_collect_selected "$requested")
}

aurelia_wallpaper_cmd_current() {
    local wants_json="${1:-0}"
    local current=""

    current="$(aurelia_wallpaper_current_path  || true)"
    if aurelia_wallpaper_setting_is_true "$wants_json"; then
        jq -n \
            --arg path "${current:-}" \
            --arg source "$([[ -n "$current" ]] && aurelia_wallpaper_source_of_path "$current" || printf 'unknown')" \
            '{path:$path,source:$source,active:($path != "")}'
        return 0
    fi
    printf '%s\n' "${current:-Unknown}"
}

aurelia_wallpaper_apply_path() {
    local target=""

    target="$(aurelia_wallpaper_resolve_apply_target "$1")" || return 1
    aurelia_wallpaper_activate "$target" || return 1
}

# Selector forms: index:<n> (1-based), next, random, first.
aurelia_wallpaper_apply_selection() {
    local requested_source="$1"
    local selector="$2"
    local -a entries=()
    local current=""
    local target_index=0
    local picked=""

    mapfile -d '' -t entries < <(aurelia_wallpaper_collect_selected "$requested_source")
    [[ "${#entries[@]}" -gt 0 ]] ||
        aurelia_wallpaper_fail "No wallpapers found in source: $requested_source"

    current="$(aurelia_wallpaper_current_path  || true)"

    case "$selector" in
        index:*)
            local requested_index="${selector#index:}"
            [[ "$requested_index" =~ ^[0-9]+$ && "$requested_index" -ge 1 ]] ||
                aurelia_wallpaper_fail "Wallpaper index must be a positive integer."
            (( requested_index <= ${#entries[@]} )) ||
                aurelia_wallpaper_fail "Wallpaper index ${requested_index} is out of range (1-${#entries[@]})."
            target_index=$((requested_index - 1))
            ;;
        next)
            target_index=0
            local index
            for index in "${!entries[@]}"; do
                if [[ -n "$current" && "${entries[$index]}" == "$current" ]]; then
                    target_index=$(((index + 1) % ${#entries[@]}))
                    break
                fi
            done
            ;;
        random)
            picked="$(printf '%s\0' "${entries[@]}" |
                "$AW_SHUFFLE_BIN" -z -n 1 | tr -d '\0')"
            [[ -n "$picked" ]] ||
                aurelia_wallpaper_fail "Could not select a random wallpaper."
            aurelia_wallpaper_apply_path "$picked"
            return
            ;;
        first)
            target_index=0
            ;;
        *)
            aurelia_wallpaper_fail "Unsupported wallpaper selector: $selector"
            ;;
    esac

    aurelia_wallpaper_apply_path "${entries[$target_index]}"
}

aurelia_wallpaper_import_target_dir() {
    local source_id="$1"
    local directory=""

    directory="$(aurelia_wallpaper_source_path_for "$source_id")" || return 1
    if [[ "$source_id" == "library" ]]; then
        aurelia_wallpaper_mkdir "$directory" "Wallpaper library" || return 1
    else
        [[ -d "$directory" ]] ||
            aurelia_wallpaper_fail "Configured wallpaper source is missing: $directory"
    fi
    printf '%s\n' "$directory"
}

# Bounded content duplicate scan limited to same-size files in one directory.
aurelia_wallpaper_find_duplicate() {
    local directory="$1"
    local size="$2"
    local digest="$3"
    local scanned=0
    local candidate=""

    while IFS= read -r -d '' candidate; do
        scanned=$((scanned + 1))
        (( scanned <= 200 )) || break
        [[ "$(stat -c '%s' -- "$candidate" || printf '0')" == "$size" ]] ||
            continue
        if [[ "$(aurelia_wallpaper_sha256 "$candidate"  || true)" == "$digest" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(find -P "$directory" -maxdepth 1 -type f -print0 | LC_ALL=C sort -z)
    return 1
}

aurelia_wallpaper_cmd_import() {
    local candidate="$1"
    local target_source="${2:-library}"
    local source_path=""
    local directory=""
    local extension=""
    local base_name=""
    local slug=""
    local digest=""
    local size=""
    local existing=""
    local destination=""
    local staging=""

    source_path="$(aurelia_wallpaper_resolve_apply_target "$candidate")" || return 1
    aurelia_wallpaper_is_still_image "$source_path" ||
        aurelia_wallpaper_fail "Only image wallpapers can be imported into the library."
    aurelia_wallpaper_signature_matches "$source_path" ||
        aurelia_wallpaper_fail "File is not a valid image: $source_path"

    directory="$(aurelia_wallpaper_import_target_dir "$target_source")" || return 1

    extension="${source_path##*.}"
    extension="$(LC_ALL=C printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')"
    if [[ "$extension" == "jpeg" ]]; then
        extension="jpg"
    fi
    base_name="$(basename -- "$source_path")"
    slug="$(aurelia_wallpaper_slug "${base_name%.*}"  || true)"
    [[ -n "$slug" ]] || slug="wallpaper"

    digest="$(aurelia_wallpaper_sha256 "$source_path")" || return 1
    size="$(stat -c '%s' -- "$source_path" || printf '0')"

    existing="$(aurelia_wallpaper_find_duplicate "$directory" "$size" "$digest"  || true)"
    if [[ -n "$existing" ]]; then
        printf '%s\n' "$existing"
        return 0
    fi

    destination="$directory/$slug.$extension"
    if [[ -f "$destination" && "$source_path" == "$destination" ]]; then
        printf '%s\n' "$destination"
        return 0
    fi
    if [[ -e "$destination" ]]; then
        [[ -f "$destination" && ! -L "$destination" ]] ||
            aurelia_wallpaper_fail "Refusing to replace a non-regular library entry: $destination"
        destination="$directory/$slug-${digest:0:8}.$extension"
        if [[ -e "$destination" && ! -L "$destination" ]]; then
            if [[ "$(aurelia_wallpaper_sha256 "$destination"  || true)" == "$digest" ]]; then
                printf '%s\n' "$destination"
                return 0
            fi
            aurelia_wallpaper_fail "Library destination already exists: $destination"
        fi
    fi

    staging="$(mktemp "$directory/.import-XXXXXX.$extension")" ||
        aurelia_wallpaper_fail "Could not create a library staging file."
    if ! cp -- "$source_path" "$staging"; then
        rm -f -- "$staging"
        aurelia_wallpaper_fail "Could not copy wallpaper into the library."
    fi
    if [[ "$(aurelia_wallpaper_sha256 "$staging"  || true)" != "$digest" ]]; then
        rm -f -- "$staging"
        aurelia_wallpaper_fail "Library copy does not match the source image."
    fi
    aurelia_wallpaper_atomic_move "$staging" "$destination" || return 1
    printf '%s\n' "$destination"
}
aurelia_wallpaper_config_document() {
    local document=""

    if [[ -f "$AW_CONFIG_FILE" ]]; then
        document="$(jq -c '.' "$AW_CONFIG_FILE")" || document=""
    fi
    [[ -n "$document" ]] || document='{"version":1,"sources":[]}'
    printf '%s\n' "$document"
}

aurelia_wallpaper_source_path_argument() {
    local raw="$1"
    local expanded="$raw"

    case "$raw" in
        '~') expanded="$AW_HOME" ;;
        '~'/*) expanded="$AW_HOME/${raw:2}" ;;
    esac
    [[ "$expanded" == /* && "$expanded" != "/" ]] ||
        aurelia_wallpaper_fail "A wallpaper source path must be absolute: $raw"
    expanded="${expanded%/}"
    [[ -n "$expanded" ]] || expanded="/"
    [[ "$expanded" == /* && "$expanded" != "/" ]] ||
        aurelia_wallpaper_fail "A wallpaper source path must be absolute: $raw"
    [[ ! -L "$expanded" ]] ||
        aurelia_wallpaper_fail "A wallpaper source must not be a symlink: $expanded"
    [[ -d "$expanded" ]] ||
        aurelia_wallpaper_fail "A wallpaper source must be an existing directory: $expanded"
    printf '%s\n' "$expanded"
}

aurelia_wallpaper_cmd_sources_add() {
    local raw_path="$1"
    local requested_id="${2:-}"
    local path=""
    local id=""
    local document=""
    local existing=""

    path="$(aurelia_wallpaper_source_path_argument "$raw_path")" || return 1
    [[ "$path" != "$AW_CFG_LIBRARY" ]] ||
        aurelia_wallpaper_fail "That directory is already the wallpaper library: $path"

    if [[ -n "$requested_id" ]]; then
        [[ "$requested_id" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]] ||
            aurelia_wallpaper_fail "Invalid wallpaper source id: $requested_id"
        id="$requested_id"
    else
        id="$(aurelia_wallpaper_slug "$(basename -- "$path")"  || true)"
        [[ -n "$id" ]] || id="wallpapers"
    fi

    local existing_id=""
    for existing_id in ${AW_CFG_SOURCE_IDS[@]+"${AW_CFG_SOURCE_IDS[@]}"}; do
        [[ "$existing_id" != "$id" ]] ||
            aurelia_wallpaper_fail "A wallpaper source with this id already exists: $id"
    done
    if [[ "$id" == "wallhaven" || "$id" == "library" ]]; then
        aurelia_wallpaper_fail "Reserved wallpaper source id: $id"
    fi

    aurelia_wallpaper_lock || return 1
    document="$(aurelia_wallpaper_config_document)" || return 1
    document="$(jq -c \
        --arg id "$id" \
        --arg path "$path" \
        '(.sources // []) as $current
         | {version: 1} + .
         | .sources = ($current + [{id:$id,path:$path,enabled:true}])' \
        <<<"$document")" || aurelia_wallpaper_fail "Could not update the wallpaper configuration."

    aurelia_wallpaper_config_write "$document" || return 1
    printf 'Added wallpaper source %s -> %s\n' "$id" "$path"
}

aurelia_wallpaper_cmd_sources_remove() {
    local id="$1"
    local document=""

    [[ "$id" != "library" && "$id" != "wallhaven" ]] ||
        aurelia_wallpaper_fail "The built-in wallpaper sources cannot be removed: $id"
    aurelia_wallpaper_source_record "$id" >/dev/null ||
        aurelia_wallpaper_fail "Unknown wallpaper source: $id"

    aurelia_wallpaper_lock || return 1
    document="$(aurelia_wallpaper_config_document)" || return 1
    document="$(jq -c \
        --arg id "$id" \
        '.sources = ((.sources // []) | map(select(.id != $id)))' \
        <<<"$document")" || aurelia_wallpaper_fail "Could not update the wallpaper configuration."

    aurelia_wallpaper_config_write "$document" || return 1
    printf 'Removed wallpaper source %s\n' "$id"
}

aurelia_wallpaper_cmd_sources_toggle() {
    local id="$1"
    local enabled="$2"
    local document=""

    [[ "$id" != "library" && "$id" != "wallhaven" ]] ||
        aurelia_wallpaper_fail "The built-in wallpaper sources cannot be toggled: $id"
    aurelia_wallpaper_source_record "$id" >/dev/null ||
        aurelia_wallpaper_fail "Unknown wallpaper source: $id"

    aurelia_wallpaper_lock || return 1
    document="$(aurelia_wallpaper_config_document)" || return 1
    document="$(jq -c \
        --arg id "$id" \
        --argjson enabled "$enabled" \
        '.sources = ((.sources // []) | map(if .id == $id then .enabled = $enabled else . end))' \
        <<<"$document")" || aurelia_wallpaper_fail "Could not update the wallpaper configuration."

    aurelia_wallpaper_config_write "$document" || return 1
    if [[ "$enabled" == "true" ]]; then
        printf 'Enabled wallpaper source %s\n' "$id"
    else
        printf 'Disabled wallpaper source %s\n' "$id"
    fi
}
