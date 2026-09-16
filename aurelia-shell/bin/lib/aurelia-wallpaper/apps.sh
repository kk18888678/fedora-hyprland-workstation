#!/usr/bin/env bash

# Custom app theming (Aether custom-apps parity). The user declares apps in:
#
#   ~/.config/aurelia/custom-apps/<name>/config.json
#       { "template": "theme.ini", "destination": "~/.config/cava/theme" }
#   ~/.config/aurelia/custom-apps/<name>/<template>
#       ... with {background}, {accent}, {accent.strip}, {red.rgb},
#           {blue.rgba:0.5}, {theme_type}, {wallpaper} variables
#
# Rendering writes the substituted template to the destination atomically.
# Reload hooks are intentionally NOT executed: a theming tool must never run
# commands from configuration files it did not ship.

aurelia_wallpaper_apps_load_palette() {
    declare -gA AW_PAL=()
    local line key value
    [[ -f "$AW_ACTIVE_COLORS_PATH" && ! -L "$AW_ACTIVE_COLORS_PATH" ]] ||
        aurelia_wallpaper_fail "No active palette. Apply a theme first."
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^([A-Za-z0-9_-]+)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
        key="${BASH_REMATCH[1],,}"
        value="${BASH_REMATCH[2]}"
        value="${value//\"/}"
        [[ "$value" =~ ^[A-Za-z0-9#(),._+/%[:space:]-]*$ ]] || continue
        AW_PAL["$key"]="$value"
    done <"$AW_ACTIVE_COLORS_PATH"
    [[ -n "${AW_PAL[background]:-}" && -n "${AW_PAL[foreground]:-}" ]] ||
        aurelia_wallpaper_fail "Active palette is incomplete."
}

aurelia_wallpaper_apps_resolve_token() {
    local key="${1,,}"
    local modifier="${2:-}"
    local value=""

    case "$key" in
        theme_type) value="${AW_PAL[mode]:-dark}" ;;
        wallpaper) value="$(aurelia_wallpaper_current_path  || true)" ;;
        *)
            [[ -n "${AW_PAL[$key]:-}" ]] || return 1
            value="${AW_PAL[$key]}" ;;
    esac

    case "$modifier" in
        "") ;;
        .strip) value="${value#\#}" ;;
        .rgb) value="$(aurelia_wallpaper_hex_rgb "$value")" ;;
        .rgba) value="$(aurelia_wallpaper_hex_rgba "$value")" ;;
        .rgba:*) value="$(aurelia_wallpaper_hex_rgba "$value" "${modifier#.rgba:}")" ;;
        *) return 1 ;;
    esac
    printf '%s' "$value"
}

aurelia_wallpaper_apps_render_template() {
    local template_file="$1"
    local line out="" replacement="" guard=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        out="$line"
        guard=0
        while [[ "$out" =~ \{([A-Za-z0-9_]+)(\.[A-Za-z]+(:[0-9.]+)?)?\} ]]; do
            replacement="$(aurelia_wallpaper_apps_resolve_token "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]:-}")" || {
                aurelia_wallpaper_fail "Unknown template variable: ${BASH_REMATCH[0]}"
                return 1
            }
            # sed is used because the bash ${var//pat/repl} form mangles
            # expanded patterns; token and value characters are safe here.
            out="$(sed -e "s|{${BASH_REMATCH[1]}${BASH_REMATCH[2]:-}}|\"$replacement\"|g" <<<"$out")"
            guard=$((guard + 1))
            (( guard < 50 )) || {
                aurelia_wallpaper_fail "Template variable substitution did not converge."
                return 1
            }
        done
        printf '%s\n' "$out"

    done <"$template_file"
}

aurelia_wallpaper_apps_expand_destination() {
    local raw="$1"
    local expanded="$raw"
    case "$raw" in
        '~') expanded="$AW_HOME" ;;
            '~'/*) expanded="$AW_HOME/${raw:2}" ;;
    esac
    [[ "$expanded" == /* && "$expanded" != "/" ]] ||
        aurelia_wallpaper_fail "Template destination must be absolute: $raw"
    [[ "$expanded" != *$'\n'* && "$expanded" != *$'\\r'* ]] ||
        aurelia_wallpaper_fail "Template destination contains control characters."
    printf '%s\n' "$expanded"
}

aurelia_wallpaper_apps_render() {
    local name="${1:-}"
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
        aurelia_wallpaper_fail "Invalid custom app name: $name"
    local app_root="$AW_APPS_ROOT/$name"
    local config="$app_root/config.json"
    [[ -f "$config" && ! -L "$config" ]] ||
        aurelia_wallpaper_fail "Custom app is not configured: $name"

    local template_rel="" destination_rel=""
    template_rel="$(jq -r '.template // empty' "$config")"
    destination_rel="$(jq -r '.destination // empty' "$config")"
    [[ "$template_rel" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ && "$template_rel" != *..* ]] ||
        aurelia_wallpaper_fail "Custom app template path is unsafe: $template_rel"
    [[ -n "$destination_rel" ]] ||
        aurelia_wallpaper_fail "Custom app has no destination: $name"

    local template_file="$app_root/$template_rel"
    [[ -f "$template_file" && ! -L "$template_file" ]] ||
        aurelia_wallpaper_fail "Custom app template does not exist: $template_rel"

    local destination=""
    destination="$(aurelia_wallpaper_apps_expand_destination "$destination_rel")" || return 1
    local -A pal=()
    aurelia_wallpaper_apps_load_palette

    local staging=""
    staging="$(mktemp)" || aurelia_wallpaper_fail "Could not stage the rendered template."
    if ! aurelia_wallpaper_apps_render_template "$template_file" >"$staging"; then
        rm -f -- "$staging"
        return 1
    fi

    local destination_dir=""
    destination_dir="$(dirname -- "$destination")"
    mkdir -p -- "$destination_dir" ||
        aurelia_wallpaper_fail "Could not create the destination directory: $destination_dir"
    aurelia_wallpaper_atomic_text "$(cat -- "$staging")" "$destination" || return 1
    rm -f -- "$staging"
    printf 'Rendered custom app: %s -> %s\n' "$name" "$destination"
}

aurelia_wallpaper_apps_list() {
    local wants_json="${1:-0}"
    [[ -d "$AW_APPS_ROOT" && ! -L "$AW_APPS_ROOT" ]] || return 0
    local app dir=""
    while IFS= read -r -d '' dir; do
        app="${dir##*/}"
        [[ -f "$dir/config.json" && ! -L "$dir/config.json" ]] || continue
        if aurelia_wallpaper_setting_is_true "$wants_json"; then
            jq -c --arg name "$app" '{name:$name, template:(.template // ""), destination:(.destination // "")}' "$dir/config.json"
        else
            printf '%s\n' "$app"
        fi
    done < <(find -P "$AW_APPS_ROOT" -mindepth 1 -maxdepth 1 -type d -print0 | LC_ALL=C sort -z)
}

aurelia_wallpaper_apps_render_all() {
    local failures=0
    local app=""
    while IFS= read -r app; do
        [[ -n "$app" ]] || continue
        if ! aurelia_wallpaper_apps_render "$app"; then
            printf 'Warning: custom app render failed: %s\n' "$app" >&2
            failures=$((failures + 1))
        fi
    done < <(aurelia_wallpaper_apps_list)
    return "$failures"
}
