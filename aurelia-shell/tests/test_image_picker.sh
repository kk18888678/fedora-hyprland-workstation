#!/usr/bin/env bash

# Contract tests for the resident Omarchy-style image picker and its
# read-only preview/cache provider. These tests never open the live overlay or
# change the workstation theme state.

set -Eeuo pipefail

picker_root="$ROOT/plugins/aurelia.image-picker"
preview_bin="$ROOT/bin/aurelia-theme-preview"

section "Aurelia Image Picker"

if [[ -f "$picker_root/manifest.json" &&
      -f "$picker_root/ImagePicker.qml" &&
      -f "$picker_root/ImagePickerModel.js" &&
      -f "$picker_root/keybindings.lua" &&
      -x "$preview_bin" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.image-picker" and
       .name == "Image Picker" and
       (.kinds == ["overlay"]) and
       .keepLoaded == true and
       .entryPoints.overlay == "ImagePicker.qml"
   ' "$picker_root/manifest.json" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$picker_root" >/dev/null 2>&1; then
    pass "image picker declares a validated resident overlay plugin"
else
    fail "image picker manifest or entry point is incomplete"
fi

if grep -q 'WlrLayershell.namespace: "aurelia-image-picker"' "$picker_root/ImagePicker.qml" &&
   grep -q 'WlrKeyboardFocus.Exclusive' "$picker_root/ImagePicker.qml" &&
   grep -q 'Keys.onPressed' "$picker_root/ImagePicker.qml" &&
   grep -q 'root.selectAdjacent' "$picker_root/ImagePicker.qml" &&
   grep -q 'root.updateFilter' "$picker_root/ImagePicker.qml" &&
   grep -q 'sourceActivated' "$picker_root/ImagePicker.qml" &&
   grep -q 'cache: true' "$picker_root/ImagePicker.qml"; then
    pass "picker provides exclusive keyboard navigation, filtering, and lazy image activation"
else
    fail "picker keyboard, filtering, or lazy-preview contract is incomplete"
fi

if grep -q 'aurelia-theme-preview' "$picker_root/ImagePicker.qml" &&
   grep -q 'mode === "background"' "$picker_root/ImagePicker.qml" &&
   grep -q '\[root.themeBin, "set", String(entry.id)\]' "$picker_root/ImagePicker.qml" &&
   grep -q '\[root.backgroundBin, "set", String(entry.filePath)\]' "$picker_root/ImagePicker.qml" &&
   grep -q '"aurelia.image-picker"' "$picker_root/keybindings.lua"; then
    pass "picker uses one discovery surface and delegates mutations to theme commands"
else
    fail "picker discovery or mutation-owner boundary is incomplete"
fi

model_output="$(node - "$picker_root/ImagePickerModel.js" <<'NODE'
const model = require(process.argv[2]);
const themes = model.loadRows(
  'tokyo-night\tTokyo Night\t/cache/tokyo-night.png\t/source/preview.png\t1\n' +
  'rose-pine\tRose Pine\t/cache/rose-pine.png\t/source/preview.png\t0\n',
  'theme'
);
const backgrounds = model.loadRows(
  '/wallpapers/one.webp\t/cache/one.jpg\tOne\t0\n' +
  '/wallpapers/two.webp\t/cache/two.jpg\tTwo\t1\n',
  'background'
);
if (themes.length !== 2 || model.indexForCurrent(themes) !== 0) process.exit(1);
if (model.filteredRows(themes, 'rose').length !== 1) process.exit(1);
if (backgrounds.length !== 2 || model.indexForCurrent(backgrounds) !== 1) process.exit(1);
if (!model.itemMatches(backgrounds[0], 'one')) process.exit(1);
console.log('ok');
NODE
)"
if [[ "$model_output" == "ok" ]]; then
    pass "image picker model parses theme/background rows and preserves current selection"
else
    fail "image picker model behavior is incorrect: $model_output"
fi

picker_keybindings="$(luajit - "$ROOT/dotfiles/hypr/keybindings_manifest.lua" <<'LUA'
local manifest = dofile(arg[1])
local found_theme = 0
local found_background = 0
for _, item in ipairs(manifest.bindings or {}) do
    if item.id == "aurelia.theme.switcher" then
        found_theme = found_theme + 1
        assert(item.key == "SUPER + SHIFT + CTRL + SPACE")
        assert(item.action_type == "plugin_ipc")
        assert(item.command_argv[#item.command_argv] == '{"mode":"theme"}')
    elseif item.id == "aurelia.background.switcher" then
        found_background = found_background + 1
        assert(item.key == "SUPER + CTRL + SPACE")
        assert(item.action_type == "plugin_ipc")
        assert(item.command_argv[#item.command_argv] == '{"mode":"background"}')
    end
end
assert(found_theme == 1 and found_background == 1)
print("ok")
LUA
)"
if [[ "$picker_keybindings" == "ok" ]]; then
    pass "theme and background selectors contribute the exact Omarchy shortcut pair"
else
    fail "theme/background shortcut declarations are missing or drifted"
fi

preview_tmp="$(mktemp -d)"
cleanup_preview_tmp() { rm -rf -- "$preview_tmp"; }
trap cleanup_preview_tmp RETURN
mkdir -p "$preview_tmp/themes/demo/backgrounds" \
    "$preview_tmp/home" "$preview_tmp/config" "$preview_tmp/state" "$preview_tmp/cache"
printf '%s\n' 'background = #101010' 'foreground = #eeeeee' >"$preview_tmp/themes/demo/colors.toml"
printf '%s\n' 'preview' >"$preview_tmp/themes/demo/preview.png"
printf '%s\n' 'wallpaper' >"$preview_tmp/themes/demo/backgrounds/one.png"

preview_env=(
    "AURELIA_THEMES_DIR=$preview_tmp/themes"
    "HOME=$preview_tmp/home"
    "XDG_CONFIG_HOME=$preview_tmp/config"
    "XDG_STATE_HOME=$preview_tmp/state"
    "XDG_CACHE_HOME=$preview_tmp/cache"
    "WORKSTATION_TEST_MODE=1"
)

theme_rows="$(env "${preview_env[@]}" "$preview_bin" themes)"
cached_preview="$(awk -F '\t' '$1 == "demo" { print $3; exit }' <<<"$theme_rows")"
if grep -q $'^demo\tDemo\t' <<<"$theme_rows" &&
   [[ -L "$cached_preview" ]] &&
   [[ "$(readlink -f -- "$cached_preview")" == "$preview_tmp/themes/demo/preview.png" ]]; then
    pass "theme preview provider emits a cached, safely linked preview row"
else
    fail "theme preview provider did not emit the expected cache link"
fi

background_rows="$(env "${preview_env[@]}" "$preview_bin" backgrounds demo)"
if awk -F '\t' -v expected_path="$preview_tmp/themes/demo/backgrounds/one.png" \
    '$1 == expected_path && NF == 4 { found = 1 } END { exit found ? 0 : 1 }' <<<"$background_rows"; then
    pass "background preview provider emits source, thumbnail, label, and current-state columns"
else
    fail "background preview provider row contract is incomplete"
fi

rm -rf -- "$preview_tmp"
trap - RETURN
