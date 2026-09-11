#!/usr/bin/env bash

# Verify the checked-in stock theme catalog against the inspected Omarchy
# snapshot and exercise the data-only Aurelia resolver around it.

set -Eeuo pipefail

section "Omarchy stock theme catalog"

theme_root="$ROOT/themes"
color_bin="$ROOT/bin/aurelia-theme-color"
theme_bin="$ROOT/bin/aurelia-theme"
background_bin="$ROOT/bin/aurelia-theme-bg"

expected_themes=(
    catppuccin catppuccin-latte ethereal everforest flexoki-light gruvbox
    hackerman kanagawa last-horizon lumon lupine matte-black miasma nord
    osaka-jade retro-82 ristretto rose-pine solitude tokyo-night vantablack white
)

declare -A expected_file_counts=(
    [catppuccin]=11 [catppuccin-latte]=9 [ethereal]=8 [everforest]=9
    [flexoki-light]=10 [gruvbox]=13 [hackerman]=10 [kanagawa]=10
    [last-horizon]=13 [lumon]=13 [lupine]=11 [matte-black]=11 [miasma]=8
    [nord]=11 [osaka-jade]=11 [retro-82]=19 [ristretto]=10 [rose-pine]=12
    [solitude]=14 [tokyo-night]=17 [vantablack]=10 [white]=9
)

declare -A expected_background_counts=(
    [catppuccin]=4 [catppuccin-latte]=2 [ethereal]=3 [everforest]=2
    [flexoki-light]=2 [gruvbox]=6 [hackerman]=3 [kanagawa]=2
    [last-horizon]=4 [lumon]=3 [lupine]=6 [matte-black]=4 [miasma]=3
    [nord]=4 [osaka-jade]=4 [retro-82]=9 [ristretto]=5 [rose-pine]=4
    [solitude]=5 [tokyo-night]=8 [vantablack]=5 [white]=4
)

for slug in "${expected_themes[@]}"; do
    theme_dir="$theme_root/$slug"
    if [[ -d "$theme_dir" && -f "$theme_dir/colors.toml" &&
          -f "$theme_dir/icons.theme" && -f "$theme_dir/preview.png" &&
          -f "$theme_dir/preview-unlock.png" && -f "$theme_dir/unlock.png" &&
          "$(awk -v prefix="$slug/" '$2 ~ "^" prefix {count++} END {print count + 0}' "$theme_root/SHA256SUMS")" -eq "${expected_file_counts[$slug]}" &&
          "$(find "$theme_dir/backgrounds" -maxdepth 1 -type f | wc -l)" -eq "${expected_background_counts[$slug]}" ]]; then
        pass "$slug has the exact stock file and background inventory"
    else
        fail "$slug stock inventory is incomplete or changed"
    fi
done

checksum_output="$(mktemp)"
trap 'rm -f -- "$checksum_output"' RETURN
if (cd "$theme_root" && sha256sum -c SHA256SUMS) >"$checksum_output" 2>&1; then
    pass "all 249 copied stock files match the reference SHA-256 manifest"
else
    fail "one or more copied stock files differ from the reference" "$(sed -n '1,60p' "$checksum_output")"
fi
rm -f -- "$checksum_output"
trap - RETURN

for slug in "${expected_themes[@]}"; do
    palette="$theme_root/$slug/colors.toml"
    if [[ "$("$color_bin" --file "$palette" mode)" == light ||
          "$("$color_bin" --file "$palette" mode)" == dark ]] &&
       [[ -n "$("$color_bin" --file "$palette" foreground)" ]] &&
       [[ -n "$("$color_bin" --file "$palette" color15)" ]]; then
        :
    else
        fail "$slug palette does not resolve through the Omarchy-compatible aliases"
    fi
done
pass "all stock palettes resolve mode, foreground, and ANSI aliases without executing theme code"

test_tmp="$(mktemp -d)"
trap 'rm -rf -- "$test_tmp"' RETURN
mkdir -p "$test_tmp/home" "$test_tmp/config" "$test_tmp/state"
theme_env=(
    "AURELIA_THEMES_DIR=$theme_root"
    "HOME=$test_tmp/home"
    "XDG_CONFIG_HOME=$test_tmp/config"
    "XDG_STATE_HOME=$test_tmp/state"
    "WORKSTATION_TEST_MODE=1"
)

catalog_json="$(env "${theme_env[@]}" "$theme_bin" catalog --json)"
for slug in "${expected_themes[@]}"; do
    if jq -e --arg slug "$slug" '[.themes[] | select(.id == $slug)] | length == 1' <<<"$catalog_json" >/dev/null; then
        :
    else
        fail "catalog omits stock theme $slug"
    fi
done
if jq -e '
    ([.themes[] | select(.id == "tokyo-night")][0].preview | endswith("/tokyo-night/preview.png")) and
    ([.themes[] | select(.id == "tokyo-night")][0].previewUnlock | endswith("/tokyo-night/preview-unlock.png")) and
    ([.themes[] | select(.id == "tokyo-night")][0].iconSet == "Yaru-magenta") and
    ([.themes[] | select(.id == "tokyo-night")][0].backgrounds | length == 8)
' <<<"$catalog_json" >/dev/null; then
    pass "catalog exposes preview, unlock preview, icon-set metadata, and all Tokyo Night backgrounds"
else
    fail "catalog metadata does not preserve the reference theme assets"
fi

if env "${theme_env[@]}" "$theme_bin" set "Tokyo Night" >/dev/null &&
   cmp -s "$test_tmp/state/aurelia/current/colors.toml" "$theme_root/tokyo-night/colors.toml" &&
   cmp -s "$test_tmp/state/aurelia/current/theme.conf" "$theme_root/tokyo-night/colors.toml" &&
   [[ "$(sed -n '1p' "$test_tmp/state/aurelia/current/theme.name")" == tokyo-night ]] &&
   [[ "$(sed -n '1p' "$test_tmp/state/aurelia/current/background.path")" == *"/0-winding-road.webp" ]]; then
    pass "setting a stock theme preserves its exact palette and first sorted background"
else
    fail "setting a stock theme did not preserve the reference palette/background contract"
fi

if env "${theme_env[@]}" "$background_bin" next >/dev/null &&
   [[ "$(sed -n '1p' "$test_tmp/state/aurelia/current/background.path")" == *"/1-quattro.webp" ]]; then
    pass "stock background cycling advances in sorted reference order"
else
    fail "stock background cycling did not advance to the next reference asset"
fi

mkdir -p "$test_tmp/config/aurelia/themes/tokyo-night"
cp -- "$theme_root/tokyo-night/colors.toml" "$test_tmp/config/aurelia/themes/tokyo-night/colors.toml"
overlay_catalog="$(env "${theme_env[@]}" "$theme_bin" catalog --json)"
if jq -e '
    ([.themes[] | select(.id == "tokyo-night")][0].preview | endswith("/tokyo-night/preview.png")) and
    ([.themes[] | select(.id == "tokyo-night")][0].backgrounds | length == 8)
' <<<"$overlay_catalog" >/dev/null; then
    pass "a palette-only user overlay inherits stock previews and backgrounds"
else
    fail "a user overlay replaced rather than layered over stock theme metadata"
fi

mkdir -p "$test_tmp/config/aurelia/themes/background-only/backgrounds"
printf '%s\n' 'mode = "dark"' 'background = "#101010"' 'foreground = "#eeeeee"' \
    >"$test_tmp/config/aurelia/themes/background-only/colors.toml"
printf '%s\n' 'background-only-preview' \
    >"$test_tmp/config/aurelia/themes/background-only/backgrounds/1-custom.png"
fallback_catalog="$(env "${theme_env[@]}" "$theme_bin" catalog --json)"
if jq -e '
    ([.themes[] | select(.id == "background-only")][0].preview | endswith("/background-only/backgrounds/1-custom.png"))
' <<<"$fallback_catalog" >/dev/null; then
    pass "themes without a dedicated preview fall back to the first sorted background"
else
    fail "preview discovery did not fall back to a custom theme background"
fi

rm -rf -- "$test_tmp"
trap - RETURN
