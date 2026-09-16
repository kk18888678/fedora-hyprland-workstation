#!/usr/bin/env bash

# Base16 scheme import (https://github.com/chriskempson/base16 and the
# tinted-theming family). A base16 scheme file is simple YAML:
#
#   scheme: "Scheme Name"
#   base00: "1a1b26"
#
# The import converts the sixteen bases into the canonical Aurelia palette
# and publishes it as a generated data-only user theme.

aurelia_wallpaper_base16_parse() {
    local scheme_file="$1"
    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        key="${line%%:*}"
        key="${key#""${key%%[![:space:]]*}""}"
        key="${key%""${key##*[![:space:]]}""}"
        [[ "$key" =~ ^(base[0-9A-Fa-f]{2}|scheme)$ ]] || continue
        value="${line#*:}"
        value="${value//\"/}"
        value="${value#""${value%%[![:space:]]*}""}"
        value="${value%""${value##*[![:space:]]}""}"
        printf '%s\t%s\n' "$key" "$value"
    done <"$scheme_file"
}

aurelia_wallpaper_base16_import() {
    local scheme_file=""
    local requested_name=""
    local apply="0"
    local light="0"
    local wants_json="0"
    while (( $# > 0 )); do
        case "$1" in
            --name)
                [[ -n "${2:-}" ]] || aurelia_wallpaper_fail "--name requires a value."
                requested_name="$2"
                shift 2
                ;;
            --light) light="1"; shift ;;
            --apply) apply="1"; shift ;;
            --json) wants_json="1"; shift ;;
            *)
                [[ -z "$scheme_file" ]] || aurelia_wallpaper_fail "Only one scheme file allowed."
                scheme_file="$1"
                shift
                ;;
        esac
    done
    [[ -f "$scheme_file" && ! -L "$scheme_file" ]] ||
        aurelia_wallpaper_fail "Base16 scheme file does not exist: $scheme_file"

    local -A base=()
    local scheme_name=""
    local pk pv
    while IFS=$'\t' read -r pk pv; do
        if [[ "$pk" == "scheme" ]]; then scheme_name="$pv"
        else base[${pk,,}]="${pv,,}"; fi
    done < <(aurelia_wallpaper_base16_parse "$scheme_file")

    local -a required=(base00 base01 base02 base03 base04 base05 base06 base07
        base08 base09 base0a base0b base0c base0d base0e base0f)
    local key
    for key in "${required[@]}"; do
        [[ -n "${base[$key]:-}" ]] ||
            aurelia_wallpaper_fail "Base16 scheme is missing $key: $scheme_file"
        [[ "${base[$key]}" =~ ^[0-9a-f]{6}$ ]] ||
            aurelia_wallpaper_fail "Base16 value for $key is not six hex digits: ${base[$key]}"
    done

    local mode="dark"
    local sum=$(( 16#${base[base00]:0:2} + 16#${base[base00]:2:2} + 16#${base[base00]:4:2} ))
    if [[ "$light" == "1" ]] || (( sum > 382 )); then mode="light"; fi
    local mix_target="#000000"
    [[ "$mode" == "dark" ]] && mix_target="#ffffff"

    local document=""
    document+="# Imported from a base16 scheme. Data-only: no executable content."$'\n'

    document+="# scheme = ${scheme_name:-unnamed}"$'\n'

    document+="mode = \"$mode\""$'\n'

    document+="accent = \"#${base[base0d]}\""$'\n'

    document+="selection = \"#${base[base02]}\""$'\n'

    document+="muted = \"#${base[base03]}\""$'\n'

    document+="background = \"#${base[base00]}\""$'\n'

    document+="foreground = \"#${base[base05]}\""$'\n'

    document+="bright_foreground = \"#${base[base07]}\""$'\n'

    local -a map=(red:base08 yellow:base0A green:base0B cyan:base0C
        blue:base0d magenta:base0e brown:base0f orange:base09)
    local pair slot base_key normal bright
    for pair in "${map[@]}"; do
        slot="${pair%%:*}"
        base_key="${pair##*:}"
        normal="#${base[${base_key,,}]}"
        bright="$(aurelia_wallpaper_mix_hex "$normal" "$mix_target" 0.25)"
        document+="$slot = \"$normal\""$'\n'

        document+="bright_$slot = \"$bright\""$'\n'

    done

    local scheme_slug="$(aurelia_wallpaper_slug "${scheme_name:-scheme}"  || true)"
    local slug=""
    if [[ -n "$requested_name" ]]; then
        slug="$(aurelia_theme_normalize_name "$requested_name"  || true)"
        [[ -n "$slug" ]] || aurelia_wallpaper_fail "Invalid theme name: $requested_name"
    else
        [[ -n "$scheme_slug" ]] || scheme_slug="scheme"
        slug="base16-$scheme_slug"
    fi

    local staging=""
    staging="$(mktemp)" || aurelia_wallpaper_fail "Could not stage the imported palette."
    printf %s "$document" >"$staging"
    if ! aurelia_wallpaper_theme_publish "$slug" "$staging" "" "imported-base16"; then
        rm -f -- "$staging"
        return 1
    fi
    rm -f -- "$staging"

    if [[ "$apply" == "1" ]]; then
        [[ -x "$AW_THEME_BIN" ]] ||
            aurelia_wallpaper_fail "Aurelia theme command is unavailable: $AW_THEME_BIN"
        "$AW_THEME_BIN" set "$slug" || return 1
    fi

    if [[ "$wants_json" == "1" ]]; then
        jq -n --arg slug "$slug" --arg themeDir "$AW_THEME_ROOT/$slug" \
            --arg scheme "${scheme_name:-}" \
            --argjson applied "$([[ "$apply" == 1 ]] && echo true || echo false)" \
            '{slug:$slug,themeDir:$themeDir,scheme:$scheme,applied:$applied}'
    else
        printf '%s\n' "$slug"
    fi
}
