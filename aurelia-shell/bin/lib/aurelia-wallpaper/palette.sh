#!/usr/bin/env bash

# Wallpaper palette generation.
#
# This module owns generated themes: it turns a wallpaper image into a
# data-only colors.toml user theme. It never activates anything itself:
# activation stays with `aurelia-theme set`, and the generated theme is an
# ordinary user theme in the existing theme pipeline.
#
# Generated themes are always marked, so a user-authored theme directory can
# never be overwritten or removed by this capability.

aurelia_wallpaper_palette_tool() {
    if command -v magick >/dev/null; then
        printf 'magick\n'
        return 0
    fi
    if command -v convert >/dev/null; then
        printf 'convert\n'
        return 0
    fi
    aurelia_wallpaper_fail "ImageMagick (magick or convert) is required for palette generation."
}

# A generated theme must never be produced from an unreadable or hostile image:
# decoding happens under a bounded timeout in the ImageMagick policy context.
aurelia_wallpaper_palette_identify() {
    local image="$1"
    local tool="$2"
    local status=0

    if [[ "$tool" == "magick" ]]; then
        "$AW_TIMEOUT_BIN" -k 5 30 "$tool" identify -quiet -- "$image" >/dev/null ||
            status=$?
    else
        "$AW_TIMEOUT_BIN" -k 5 30 identify -quiet -- "$image" >/dev/null ||
            status=$?
    fi

    case "$status" in
        0) return 0 ;;
        124|137)
            aurelia_wallpaper_fail "Image inspection timed out: $image"
            ;;
        *)
            aurelia_wallpaper_fail "File is not a readable image: $image"
            ;;
    esac
}

aurelia_wallpaper_palette_colors() {
    local image="$1"
    local tool="$2"
    local status=0

    # A fixed sample grid keeps extraction deterministic across resolutions.
    "$AW_TIMEOUT_BIN" -k 5 60 "$tool" "$image" \
        -alpha remove -background '#808080' \
        -resize 200x200! -colors 16 -unique-colors -depth 8 txt:- |
        grep -oE '#[0-9A-Fa-f]{6}' || status=$?

    if (( status == 0 || status == 1 )); then
        return 0
    fi
    aurelia_wallpaper_fail "Color extraction failed: $image"
}

aurelia_wallpaper_palette_mean() {
    local image="$1"
    local tool="$2"

    "$AW_TIMEOUT_BIN" -k 5 30 "$tool" "$image" \
        -alpha remove -background '#808080' \
        -resize 1x1! -depth 8 txt:- |
        grep -oE '#[0-9A-Fa-f]{6}' | head -n 1
}

aurelia_wallpaper_palette_document() {
    local image="$1"
    local slug="$2"
    local forced_mode="${3:-}"
    local digest="${4:-}"
    local tool=""
    local mean=""
    local colors=""
    local document=""
    local status=0

    tool="$(aurelia_wallpaper_palette_tool)" || return 1
    aurelia_wallpaper_palette_identify "$image" "$tool" || return 1

    mean="$(aurelia_wallpaper_palette_mean "$image" "$tool")" || true
    colors="$(aurelia_wallpaper_palette_colors "$image" "$tool")" || return 1
    [[ -n "$colors" ]] ||
        aurelia_wallpaper_fail "No candidate colors could be extracted from: $image"

    document="$(printf '%s\n' "$colors" | awk \
        -v mean="$mean" \
        -v forced="$forced_mode" \
        -v name="$slug" \
        -v source="$image" \
        -v digest="$digest" \
        -f "$AW_BIN_ROOT/lib/aurelia-wallpaper/palette.awk")" || status=$?

    if (( status != 0 )) || [[ -z "$document" ]]; then
        aurelia_wallpaper_fail "Palette generation failed for: $image"
    fi

    printf '%s\n' "$document"
}

# A generated theme is identified by its marker. An interrupted first run can
# leave a marker-less directory containing only generated file names; that
# shape is recoverable. Anything richer belongs to the user and is refused.
aurelia_wallpaper_theme_is_managed() {
    local theme_dir="$1"
    local entry=""
    local found=0

    [[ -d "$theme_dir" && ! -L "$theme_dir" ]] || return 1
    [[ "$theme_dir" == "$AW_THEME_ROOT/"* ]] || return 1
    if [[ -f "$theme_dir/.generated.json" && ! -L "$theme_dir/.generated.json" ]]; then
        return 0
    fi

    while IFS= read -r -d '' entry; do
        found=1
        case "${entry#"$theme_dir"/}" in
            colors.toml|backgrounds) continue ;;
            *) return 1 ;;
        esac
    done < <(find -P "$theme_dir" -mindepth 1 -maxdepth 1 -print0)
    (( found == 1 ))
}

aurelia_wallpaper_theme_slug_for() {
    local image="$1"
    local requested="${2:-}"
    local slug=""

    if [[ -n "$requested" ]]; then
        slug="$(aurelia_theme_normalize_name "$requested"  || true)"
        [[ -n "$slug" ]] ||
            aurelia_wallpaper_fail "Invalid generated theme name: $requested"
    else
        slug="$(aurelia_wallpaper_slug "$(basename -- "$image")"  || true)"
        [[ -n "$slug" ]] || slug="wallpaper"
        slug="wallpaper-$slug"
    fi
    printf '%s\n' "${slug:0:64}"
}

aurelia_wallpaper_theme_marker() {
    local slug="$1"
    local image="$2"
    local digest="$3"
    local background="$4"

    jq -n \
        --arg slug "$slug" \
        --arg source "$image" \
        --arg sha256 "$digest" \
        --arg background "$background" \
        --arg generator "aurelia-wallpaper" \
        '{generator:$generator,slug:$slug,source:$source,sha256:$sha256,background:$background,removable:true}'
}

aurelia_wallpaper_cmd_theme_generate() {
    local image="$1"
    local requested_name="${2:-}"
    local mode="${3:-}"
    local wants_json="${4:-0}"
    local slug=""
    local theme_dir=""
    local marker=""
    local digest=""
    local extension=""
    local document=""
    local recorded_digest=""
    local background=""

    [[ "$image" == /* && -f "$image" && ! -L "$image" ]] ||
        aurelia_wallpaper_fail "A readable wallpaper image is required: $image"
    aurelia_wallpaper_is_still_image "$image" ||
        aurelia_wallpaper_fail "Palette generation requires a still image: $image"
    [[ -z "$mode" || "$mode" == "dark" || "$mode" == "light" ]] ||
        aurelia_wallpaper_fail "Unsupported palette mode: $mode"

    slug="$(aurelia_wallpaper_theme_slug_for "$image" "$requested_name")" || return 1
    theme_dir="$AW_THEME_ROOT/$slug"
    marker="$theme_dir/.generated.json"
    digest="$(aurelia_wallpaper_sha256 "$image")" || return 1

    [[ ! -L "$theme_dir" ]] ||
        aurelia_wallpaper_fail "Refusing to write through a symlinked theme directory: $theme_dir"
    if [[ -e "$theme_dir" ]]; then
        aurelia_wallpaper_theme_is_managed "$theme_dir" ||
            aurelia_wallpaper_fail "Refusing to overwrite a theme this capability did not generate: $theme_dir"
        recorded_digest="$(jq -r '.sha256 // empty' "$marker" || true)"
        if [[ "$recorded_digest" == "$digest" && -f "$theme_dir/colors.toml" ]]; then
            background="$(jq -r '.background // empty' "$marker" || true)"
            if [[ -n "$background" && -f "$theme_dir/$background" ]]; then
                if aurelia_wallpaper_setting_is_true "$wants_json"; then
                    jq -n \
                        --arg slug "$slug" \
                        --arg path "$theme_dir" \
                        --arg background "$theme_dir/$background" \
                        --arg source "$image" \
                        '{slug:$slug,path:$path,background:$background,source:$source,changed:false}'
                else
                    printf '%s\n' "$slug"
                fi
                return 0
            fi
        fi
    fi

    extension="${image##*.}"
    extension="$(LC_ALL=C printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')"
    if [[ "$extension" == "jpeg" ]]; then
        extension="jpg"
    fi
    background="backgrounds/1-wallpaper.$extension"

    document="$(aurelia_wallpaper_palette_document "$image" "$slug" "$mode" "$digest")" ||
        return 1

    aurelia_wallpaper_mkdir "$theme_dir" "Generated theme directory" || return 1
    aurelia_wallpaper_mkdir "$theme_dir/backgrounds" "Generated theme background directory" ||
        return 1

    # Replace only this capability's own generated artifacts.
    local stale=""
    while IFS= read -r -d '' stale; do
        rm -f -- "$stale"
    done < <(find -P "$theme_dir/backgrounds" -mindepth 1 -maxdepth 1 -type f \
        -name '1-wallpaper.*' -print0)

    aurelia_wallpaper_atomic_text "$document" "$theme_dir/colors.toml" || return 1
    cp -- "$image" "$theme_dir/$background" ||
        aurelia_wallpaper_fail "Could not copy the wallpaper into the generated theme."
    chmod 0600 -- "$theme_dir/$background" || true

    # The marker is written last so an interrupted run is never mistaken for a
    # complete generated theme.
    aurelia_wallpaper_atomic_text \
        "$(aurelia_wallpaper_theme_marker "$slug" "$image" "$digest" "$background")" \
        "$marker" || return 1

    if aurelia_wallpaper_setting_is_true "$wants_json"; then
        jq -n \
            --arg slug "$slug" \
            --arg path "$theme_dir" \
            --arg background "$theme_dir/$background" \
            --arg source "$image" \
            --arg sha256 "$digest" \
            '{slug:$slug,path:$path,background:$background,source:$source,sha256:$sha256,changed:true}'
    else
        printf '%s\n' "$slug"
    fi
}

aurelia_wallpaper_active_theme_slug() {
    local slug=""

    if [[ -f "$AW_THEME_NAME_PATH" && ! -L "$AW_THEME_NAME_PATH" ]]; then
        slug="$(sed -n '1p' "$AW_THEME_NAME_PATH")"
    fi
    [[ -n "$slug" ]] || slug="default"
    printf '%s\n' "$slug"
}

aurelia_wallpaper_cmd_theme_apply() {
    local image="$1"
    local requested_name="${2:-}"
    local mode="${3:-}"
    local slug=""

    [[ -x "$AW_THEME_BIN" ]] ||
        aurelia_wallpaper_fail "Aurelia theme command is unavailable: $AW_THEME_BIN"

    slug="$(aurelia_wallpaper_cmd_theme_generate "$image" "$requested_name" "$mode" 0)" ||
        return 1
    aurelia_wallpaper_lock || return 1
    "$AW_THEME_BIN" set "$slug" || return 1
    printf '%s\n' "$slug"
}

aurelia_wallpaper_theme_rows() {
    local slug=""
    local theme_dir=""
    local marker=""
    local active=""
    local source=""
    local background=""
    local generated_at=""

    active="$(aurelia_wallpaper_active_theme_slug)"
    [[ -d "$AW_THEME_ROOT" && ! -L "$AW_THEME_ROOT" ]] || return 0

    while IFS= read -r -d '' theme_dir; do
        marker="$theme_dir/.generated.json"
        [[ -f "$marker" && ! -L "$marker" ]] || continue
        slug="$(basename -- "$theme_dir")"
        [[ "$slug" =~ ^[a-z0-9][a-z0-9._+-]*$ ]] || continue
        source="$(jq -r '.source // empty' "$marker" || true)"
        background="$(jq -r '.background // empty' "$marker" || true)"
        generated_at="$(stat -c '%y' -- "$marker" | cut -d '.' -f 1 || true)"
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$slug" \
            "$source" \
            "$([[ -n "$background" ]] && printf '%s' "$theme_dir/$background" || printf '')" \
            "$([[ "$slug" == "$active" ]] && printf '1' || printf '0')" \
            "$generated_at"
    done < <(find -P "$AW_THEME_ROOT" -mindepth 1 -maxdepth 1 -type d -print0 |
        LC_ALL=C sort -z) |
        LC_ALL=C sort -t $'\t' -k1,1
}

aurelia_wallpaper_cmd_theme_list() {
    local wants_json="${1:-0}"
    local row=""
    local slug=""
    local source=""
    local background=""
    local active=""

    if aurelia_wallpaper_setting_is_true "$wants_json"; then
        local rows="[]"
        while IFS= read -r row; do
            [[ -n "$row" ]] || continue
            slug="$(cut -f1 <<<"$row")"
            source="$(cut -f2 <<<"$row")"
            background="$(cut -f3 <<<"$row")"
            active="$(cut -f4 <<<"$row")"
            rows="$(jq -c \
                --arg slug "$slug" \
                --arg source "$source" \
                --arg background "$background" \
                --arg active "$active" \
                '. + [{slug:$slug,source:$source,background:$background,active:($active == "1")}]' \
                <<<"$rows")"
        done < <(aurelia_wallpaper_theme_rows)
        jq -n --arg active "$(aurelia_wallpaper_active_theme_slug)" --argjson themes "$rows" \
            '{activeTheme:$active,themes:$themes}'
        return 0
    fi

    printf '%-24s %-9s %s\n' "SLUG" "ACTIVE" "SOURCE"
    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        slug="$(cut -f1 <<<"$row")"
        source="$(cut -f2 <<<"$row")"
        active="$(cut -f4 <<<"$row")"
        printf '%-24s %-9s %s\n' "$slug" "$([[ "$active" == "1" ]] && printf 'yes' || printf 'no')" "$source"
    done < <(aurelia_wallpaper_theme_rows)
}

aurelia_wallpaper_cmd_theme_remove() {
    local slug="$1"
    local confirmed="${2:-0}"
    local theme_dir="$AW_THEME_ROOT/$slug"
    local active=""

    aurelia_wallpaper_setting_is_true "$confirmed" ||
        aurelia_wallpaper_fail "Theme removal requires --yes."
    [[ "$slug" =~ ^[a-z0-9][a-z0-9._+-]*$ ]] ||
        aurelia_wallpaper_fail "Invalid generated theme name: $slug"
    [[ "$theme_dir" == "$AW_THEME_ROOT/"* && "$theme_dir" != "$AW_THEME_ROOT/" ]] ||
        aurelia_wallpaper_fail "Refusing to remove an unexpected theme path."
    [[ -d "$theme_dir" && ! -L "$theme_dir" ]] ||
        aurelia_wallpaper_fail "Generated theme does not exist: $slug"
    [[ -f "$theme_dir/.generated.json" && ! -L "$theme_dir/.generated.json" ]] ||
        aurelia_wallpaper_fail "Refusing to remove a theme this capability did not generate: $slug"

    active="$(aurelia_wallpaper_active_theme_slug)"
    [[ "$slug" != "$active" ]] ||
        aurelia_wallpaper_fail "Refusing to remove the active theme. Switch themes first: $slug"

    aurelia_wallpaper_lock || return 1
    # Narrow, symlink-safe deletion: only entries inside the proven generated
    # theme directory are removed, and no path outside it is ever followed.
    find -P "$theme_dir" -mindepth 1 -delete ||
        aurelia_wallpaper_fail "Could not remove the generated theme contents: $slug"
    rmdir -- "$theme_dir" ||
        aurelia_wallpaper_fail "Could not remove the generated theme directory: $slug"
    printf 'Removed generated theme %s\n' "$slug"
}

