#!/usr/bin/env bash

# Blueprints: save and restore complete looks (palette + wallpaper) the way
# Aether blueprints do. A blueprint is a JSON document in the user config:
#
#   ~/.config/aurelia/blueprints/<slug>.json
#
# Applying a blueprint publishes a generated data-only theme from the stored
# palette (and wallpaper, when present) through the shared theme publisher.

aurelia_wallpaper_blueprint_slug() {
    local slug=""
    slug="$(aurelia_theme_normalize_name "$1"  || true)"
    [[ -n "$slug" ]] || aurelia_wallpaper_fail "Invalid blueprint name: $1"
    printf '%s\n' "$slug"
}

aurelia_wallpaper_blueprint_path() {
    local slug=""
    slug="$(aurelia_wallpaper_blueprint_slug "$1")" || return 1
    printf '%s' "$AW_BLUEPRINT_ROOT/$slug.json"
}

aurelia_wallpaper_blueprint_active_palette() {
    local palette_file="$AW_ACTIVE_COLORS_PATH"
    [[ -f "$palette_file" && ! -L "$palette_file" && -s "$palette_file" ]] ||
        aurelia_wallpaper_fail "No active palette to save. Apply a theme first."
    printf '%s\n' "$palette_file"
}

aurelia_wallpaper_blueprint_save() {
    local name="${1:-}"
    local wallpaper="${2:-}"
    [[ -n "$name" ]] || aurelia_wallpaper_fail "blueprint save requires a name."
    local palette_file=""
    palette_file="$(aurelia_wallpaper_blueprint_active_palette)" || return 1
    if [[ -z "$wallpaper" ]]; then
        if [[ -f "$AW_ACTIVE_BACKGROUND_PATH" && ! -L "$AW_ACTIVE_BACKGROUND_PATH" ]]; then
            wallpaper="$(sed -n 1p "$AW_ACTIVE_BACKGROUND_PATH")"
            [[ "$wallpaper" == /* && -f "$wallpaper" ]] || wallpaper=""
        fi
    fi
    local slug=""
    slug="$(aurelia_wallpaper_blueprint_slug "$name")" || return 1
    aurelia_wallpaper_prepare_config || return 1
    [[ ! -L "$AW_BLUEPRINT_ROOT" ]] ||
        aurelia_wallpaper_fail "Blueprint root must not be a symlink: $AW_BLUEPRINT_ROOT"
    aurelia_wallpaper_mkdir "$AW_BLUEPRINT_ROOT" "Blueprint root" || return 1
    local document=""
    document="$(jq -n --arg slug "$slug" --arg name "$name" --rawfile palette "$palette_file" --arg wallpaper "$wallpaper" --arg created "$(date +%s)" '{slug:$slug,name:$name,created:$created,palette:$palette,wallpaper:$wallpaper}')" ||
        aurelia_wallpaper_fail "Could not serialize the blueprint."
    aurelia_wallpaper_atomic_text "$document" "$AW_BLUEPRINT_ROOT/$slug.json" || return 1
    printf 'Saved blueprint: %s\n' "$slug"
}

aurelia_wallpaper_blueprint_list() {
    local wants_json="${1:-0}"
    [[ -d "$AW_BLUEPRINT_ROOT" && ! -L "$AW_BLUEPRINT_ROOT" ]] || return 0
    if aurelia_wallpaper_setting_is_true "$wants_json"; then
        find -P "$AW_BLUEPRINT_ROOT" -maxdepth 1 -type f -name '*.json' -print0 |
            LC_ALL=C sort -z | xargs -0 -r jq -s 'sort_by(.slug) | map({slug, name:(.name // .slug), wallpaper:(.wallpaper // ""), created:(.created // 0)})' |
            jq -c '{blueprints:.}'
        return 0
    fi
    find -P "$AW_BLUEPRINT_ROOT" -maxdepth 1 -type f -name '*.json' -print |
        LC_ALL=C sort | xargs -r jq -r '[.slug, (.wallpaper // ""), (.created // 0)] | @tsv'
}

aurelia_wallpaper_blueprint_apply() {
    local name="${1:-}"
    local path=""
    path="$(aurelia_wallpaper_blueprint_path "$name")" || return 1
    [[ -f "$path" && ! -L "$path" ]] || aurelia_wallpaper_fail "Blueprint does not exist: $name"
    local slug=""
    slug="$(jq -r '.slug // empty' "$path")"
    [[ "$slug" =~ ^[a-z0-9][a-z0-9._+-]*$ ]] ||
        aurelia_wallpaper_fail "Blueprint has an invalid slug: $name"
    local wallpaper=""
    wallpaper="$(jq -r '.wallpaper // empty' "$path")"
    [[ "$wallpaper" == /* && -f "$wallpaper" ]] || wallpaper=""
    local staging=""
    staging="$(mktemp)" || aurelia_wallpaper_fail "Could not stage the blueprint palette."
    jq -r '.palette // empty' "$path" >"$staging"
    if [[ ! -s "$staging" ]]; then
        rm -f -- "$staging"
        aurelia_wallpaper_fail "Blueprint has no stored palette: $name"
    fi
    if ! aurelia_wallpaper_theme_publish "blueprint-$slug" "$staging" "$wallpaper" "blueprint-$slug"; then
        rm -f -- "$staging"
        return 1
    fi
    rm -f -- "$staging"
    [[ -x "$AW_THEME_BIN" ]] ||
        aurelia_wallpaper_fail "Aurelia theme command is unavailable: $AW_THEME_BIN"
    "$AW_THEME_BIN" set "blueprint-$slug" || return 1
    printf 'Applied blueprint: %s\n' "blueprint-$slug"
}

aurelia_wallpaper_blueprint_remove() {
    local name="${1:-}"
    local confirmed="${2:-0}"
    local path=""
    aurelia_wallpaper_setting_is_true "$confirmed" ||
        aurelia_wallpaper_fail "Blueprint removal requires --yes."
    path="$(aurelia_wallpaper_blueprint_path "$name")" || return 1
    [[ -f "$path" && ! -L "$path" ]] || aurelia_wallpaper_fail "Blueprint does not exist: $name"
    aurelia_wallpaper_lock || return 1
    rm -f -- "$path"
    printf 'Removed blueprint: %s\n' "$(aurelia_wallpaper_blueprint_slug "$name")"
}
