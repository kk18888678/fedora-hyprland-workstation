#!/usr/bin/env bash

# Contract tests for the first Aurelia application launcher slice.

set -Eeuo pipefail

launcher_root="$ROOT/plugins/aurelia.launcher"

section "Application Launcher Plugin"

if [[ -f "$launcher_root/manifest.json" && -f "$launcher_root/LauncherPlugin.qml" && -f "$launcher_root/ui/LauncherPanel.qml" && -f "$launcher_root/ui/LauncherModel.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.launcher" and .icon == "system-search" and (.kinds == ["panel"]) and .entryPoints.panel == "LauncherPlugin.qml"' "$launcher_root/manifest.json" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$launcher_root" >/dev/null 2>&1; then
    pass "Application Launcher declares a validated first-party panel plugin"
else
    fail "Application Launcher manifest or entry points are incomplete"
fi

if grep -q 'workstation-keybindings' "$launcher_root/LauncherPlugin.qml" &&
   grep -q 'function reload()' "$launcher_root/ui/LauncherModel.qml" &&
   grep -q 'command = \["gtk-launch", desktopId\]' "$launcher_root/ui/LauncherModel.qml" &&
   grep -q 'target: "aurelia.launcher"' "$launcher_root/LauncherPlugin.qml" &&
   grep -q 'shell.summon("aurelia.launcher"' "$ROOT/plugins/aurelia.bar/AureliaLogo.qml" &&
   [[ -f "$launcher_root/keybindings.lua" ]] &&
   grep -q 'id = "launcher"' "$launcher_root/keybindings.lua" &&
   grep -q 'SUPER + SPACE' "$launcher_root/keybindings.lua" &&
   grep -q '"shell", "toggle", "aurelia.launcher"' "$launcher_root/keybindings.lua" &&
   grep -q 'plugin_ipc' "$launcher_root/keybindings.lua"; then
    pass "Logo-to-launcher IPC and structured desktop application launch are separated from UI"
else
    fail "Application Launcher runtime boundary is incomplete"
fi

if grep -q 'io.popen' "$ROOT/dotfiles/hypr/keybindings_manifest.lua" &&
   grep -q -- "-name 'keybindings.lua'" "$ROOT/dotfiles/hypr/keybindings_manifest.lua" &&
   grep -q 'known_ids' "$ROOT/dotfiles/hypr/keybindings_manifest.lua" &&
   command -v luajit >/dev/null 2>&1 &&
   launcher_binding="$(
       luajit - "$ROOT/dotfiles/hypr/keybindings_manifest.lua" <<'LUA'
local manifest = dofile(arg[1])
local found = 0
local rendered = ""
for _, item in ipairs(manifest.bindings or {}) do
    if item.id == "launcher" then
        found = found + 1
        rendered = (item.description or "") .. "\t" .. (item.key or "")
    end
end
assert(found == 1, "expected one launcher binding, found " .. found)
print(rendered)
LUA
   )" &&
   [[ "$launcher_binding" == $'Aurelia App Launcher\tSUPER + SPACE' ]]; then
    pass "Launcher-owned shortcut is discovered into the same Keybindings registry"
else
    fail "Launcher-owned shortcut was not discovered by the Keybindings registry"
fi

if grep -q 'filteredApplications' "$launcher_root/ui/LauncherModel.qml" &&
   grep -q 'Search applications' "$launcher_root/ui/LauncherPanel.qml" &&
   grep -q 'leftPadding: Theme.spacingMd' "$launcher_root/ui/LauncherPanel.qml" &&
   grep -q 'calculatedCardHeight' "$launcher_root/ui/LauncherPanel.qml" &&
   grep -q 'Key_Down' "$launcher_root/ui/LauncherPanel.qml" &&
   grep -q 'Key_Return' "$launcher_root/ui/LauncherPanel.qml" &&
   ! grep -Eq '(^|[[:space:];])eval([[:space:];]|$)' "$launcher_root/ui/LauncherModel.qml"; then
    pass "Launcher provides keyboard-first filtering and no shell eval path"
else
    fail "Application Launcher keyboard or safety contract is incomplete"
fi
