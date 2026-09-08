#!/usr/bin/env bash

# Contract tests for Aurelia's Raycast-style Command Center. The historical
# aurelia.launcher id is retained as an IPC/configuration compatibility id;
# all user-facing terminology and implementation now belongs to Command Center.

set -Eeuo pipefail

command_center_root="$ROOT/plugins/aurelia.launcher"
services_root="$ROOT/services"

section "Aurelia Command Center Plugin"

if [[ -f "$command_center_root/manifest.json" &&
      -f "$command_center_root/CommandCenterPlugin.qml" &&
      -f "$command_center_root/ui/CommandCenterPanel.qml" &&
      -f "$command_center_root/ui/CommandCenterModel.qml" &&
      -f "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
      -f "$command_center_root/modules.json" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.launcher" and
       .name == "Command Center" and
       .icon == "system-search" and
       (.kinds == ["panel"]) and
       .keepLoaded == true and
       .entryPoints.panel == "CommandCenterPlugin.qml"
   ' "$command_center_root/manifest.json" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$command_center_root" >/dev/null 2>&1; then
    pass "Command Center declares a validated first-party panel plugin"
else
    fail "Command Center manifest or entry points are incomplete"
fi

if grep -q 'property string aureliaPath' "$command_center_root/CommandCenterPlugin.qml" &&
   grep -q 'aureliaPath + "/bin/aurelia-shell-keybindings"' "$command_center_root/CommandCenterPlugin.qml" &&
   grep -q 'property var appLibrary' "$command_center_root/CommandCenterPlugin.qml" &&
   grep -q 'CommandCenterModuleRegistry {' "$command_center_root/CommandCenterPlugin.qml" &&
   grep -q 'CommandCenterPanel {' "$command_center_root/CommandCenterPlugin.qml" &&
   grep -q 'target: "aurelia.launcher"' "$command_center_root/CommandCenterPlugin.qml" &&
   ! grep -Eq '/home/[A-Za-z0-9_./-]+|Projects/fedora-hyprland-workstation|/usr/bin/uwsm-app|/usr/bin/gtk-launch' \
       "$command_center_root/CommandCenterPlugin.qml" "$command_center_root/ui/CommandCenterModel.qml" "$command_center_root/ui/CommandCenterPanel.qml"; then
    pass "Plugin execution is checkout-relative, injected, and free of QML-side launcher hardcoding"
else
    fail "Command Center runtime boundary contains brittle paths or incomplete injection"
fi

if [[ -f "$command_center_root/keybindings.lua" ]] &&
   grep -q 'id = "launcher"' "$command_center_root/keybindings.lua" &&
   grep -q 'description = "Aurelia Command Center"' "$command_center_root/keybindings.lua" &&
   grep -q 'SUPER + SPACE' "$command_center_root/keybindings.lua" &&
   grep -q '"shell", "toggle", "aurelia.launcher"' "$command_center_root/keybindings.lua" &&
   grep -q 'plugin_ipc' "$command_center_root/keybindings.lua" &&
   grep -q 'shell.summon("aurelia.launcher"' "$ROOT/plugins/aurelia.bar/AureliaLogo.qml"; then
    pass "Existing logo/keybinding IPC identities forward to the Command Center"
else
    fail "Command Center compatibility IPC or shortcut registration is incomplete"
fi

if command -v luajit >/dev/null 2>&1 &&
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
   [[ "$launcher_binding" == $'Aurelia Command Center\tSUPER + SPACE' ]]; then
    pass "Command Center shortcut remains discoverable through the authoritative binding registry"
else
    fail "Command Center shortcut metadata drifted from the authoritative registry"
fi

if grep -q 'DesktopEntries.applications.values' "$services_root/AureliaAppLibrary.qml" &&
   grep -q 'desktopIdFor(entry)' "$services_root/AureliaAppLibrary.qml" &&
   grep -q 'value + ".desktop"' "$services_root/AureliaAppLibrary.qml" &&
   grep -q 'appRows(query)' "$services_root/AureliaAppLibrary.qml" &&
   grep -q 'AureliaAppLibrary {' "$ROOT/shell.qml" &&
   grep -q 'appLibrary: aureliaAppLibrary' "$ROOT/shell.qml" &&
   grep -q 'if ("appLibrary" in target)' "$services_root/PluginHost.qml"; then
    pass "Native XDG application discovery is a shared host service injected into plugins"
else
    fail "Shared native application library wiring is incomplete"
fi

if grep -q 'ListView.isCurrentItem' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'currentIndex: centerModel.selectedIndex' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'keyCatcher.forceActiveFocus' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'focus: false' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'appendQueryText' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'searchInput.forceActiveFocus' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'launch-app' "$command_center_root/ui/CommandCenterModel.qml" &&
   grep -q 'open-path' "$command_center_root/ui/CommandCenterModel.qml" &&
   ! grep -Eq '(^|[[:space:];])eval([[:space:];]|$)' "$command_center_root/ui/CommandCenterModel.qml" "$command_center_root/ui/CommandCenterPanel.qml"; then
    pass "Keyboard-first navigation, type-to-search, and stable current-row highlighting are explicit"
else
    fail "Command Center keyboard or selection behavior is incomplete"
fi

if jq -e '
    .version == 1 and
    ([.modules[].id] | index("apps")) != null and
    ([.modules[].id] | index("actions")) != null and
    ([.modules[].id] | index("files")) != null and
    ([.modules[].id] | index("calculator")) != null and
    ([.modules[].id] | index("weather")) != null and
    ([.modules[].id] | index("currency")) != null and
    ([.modules[].id] | index("metals")) != null and
    ([.modules[].id] | index("stocks")) != null
   ' "$command_center_root/modules.json" >/dev/null &&
   grep -q 'userModulesPath' "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'setModuleEnabled' "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'implemented' "$command_center_root/ui/CommandCenterModuleRegistry.qml"; then
    pass "Command Center has a declarative module catalog with user enablement state"
else
    fail "Command Center module catalog or enablement persistence contract is incomplete"
fi

if [[ ! -e "$command_center_root/LauncherPlugin.qml" &&
      ! -e "$command_center_root/ui/LauncherPanel.qml" &&
      ! -e "$command_center_root/ui/LauncherModel.qml" ]]; then
    pass "Obsolete single-purpose launcher implementation is removed from the loadable package"
else
    fail "Obsolete launcher implementation remains alongside Command Center"
fi
