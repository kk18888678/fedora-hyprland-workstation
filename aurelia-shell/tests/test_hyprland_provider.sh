#!/usr/bin/env bash

# Contract checks for the explicit Aurelia/Hyprland provider seam.

set -Eeuo pipefail

section "Aurelia Hyprland Provider"

provider_bin="$ROOT/bin/aurelia-enable-hyprland-provider"
parent_config="$ROOT/../dotfiles/hypr/hyprland.lua"
keybind_lua="$ROOT/dotfiles/hypr/keybind.lua"

if [[ -x "$provider_bin" ]] &&
   "$provider_bin" --help >/dev/null 2>&1 &&
   grep -q 'hyprland-provider.lua' "$provider_bin"; then
    pass "provider command exposes explicit enable/disable/status lifecycle"
else
    fail "provider command contract is incomplete"
fi

if grep -q 'aurelia_provider_path' "$parent_config" &&
   grep -q 'pcall(dofile, aurelia_provider_path)' "$parent_config" &&
   grep -q 'Aurelia Hyprland provider failed' "$parent_config"; then
    pass "parent Hyprland config has a fail-closed optional Aurelia provider seam"
else
    fail "parent Hyprland provider seam is missing"
fi

if grep -q 'debug.getinfo(1, "S")' "$keybind_lua" &&
   grep -q 'source_backend' "$keybind_lua" &&
   grep -q 'AURELIA_SHELL_KEYBINDINGS_BIN' "$ROOT/bin/aurelia-shell-keybindings"; then
    pass "standalone provider resolves its source backend without PATH shadowing"
else
    fail "standalone provider backend resolution is incomplete"
fi

if grep -q 'key = "SUPER + K"' "$ROOT/dotfiles/hypr/keybindings_manifest.lua" &&
   grep -q 'aurelia-shell-keybindings' "$ROOT/dotfiles/hypr/keybindings_manifest.lua"; then
    pass "Aurelia provider manifest contains the Super+K Keybindings action"
else
    fail "Aurelia provider manifest is missing Super+K"
fi

if [[ -f "$ROOT/plugins/aurelia.screenshot/keybindings.lua" &&
      -f "$ROOT/plugins/aurelia.launcher/keybindings.lua" ]] &&
   grep -q 'aurelia.screenshot.quick_region' "$ROOT/plugins/aurelia.screenshot/keybindings.lua" &&
   grep -q 'aurelia.screenshot.quick_screen' "$ROOT/plugins/aurelia.screenshot/keybindings.lua" &&
   grep -q 'method = "quickRegion"' "$ROOT/plugins/aurelia.screenshot/keybindings.lua" &&
   grep -q 'method = "quickScreen"' "$ROOT/plugins/aurelia.screenshot/keybindings.lua" &&
   grep -q 'id = "launcher"' "$ROOT/plugins/aurelia.launcher/keybindings.lua" &&
   grep -q 'load_aurelia_plugin_bindings' "$ROOT/dotfiles/hypr/keybindings_manifest.lua" &&
   grep -q 'keybindings.lua' "$ROOT/dotfiles/hypr/keybindings_manifest.lua" &&
   grep -q 'plugin_ipc' "$keybind_lua" &&
   grep -q 'quickRegion' "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotBarWidget.qml" &&
   grep -q 'quickScreen' "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotBarWidget.qml" &&
   grep -q 'key = "SUPER + SHIFT + R"' "$ROOT/plugins/aurelia.screenshot/keybindings.lua" &&
   grep -q 'key = "SUPER + SHIFT + S"' "$ROOT/plugins/aurelia.screenshot/keybindings.lua"; then
    pass "Aurelia plugins own provider-registered bindings"
else
    fail "Aurelia plugin keybinding declarations are incomplete"
fi
