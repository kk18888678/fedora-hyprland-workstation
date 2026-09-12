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
   grep -q 'defaultHiddenPath' "$services_root/AureliaAppLibrary.qml" &&
   grep -q 'isHiddenEntry(entry)' "$services_root/AureliaAppLibrary.qml" &&
   grep -q 'footclient' "$services_root/AureliaAppLibrary.qml" &&
   grep -q 'foot-server' "$services_root/AureliaAppLibrary.qml" &&
   [[ -f "$ROOT/config/command-center.hides" ]] &&
   grep -q '^footclient$' "$ROOT/config/command-center.hides" &&
   grep -q '^foot-server$' "$ROOT/config/command-center.hides" &&
   grep -q 'desktopIdFor(entry)' "$services_root/AureliaAppLibrary.qml" &&
   grep -q 'value + ".desktop"' "$services_root/AureliaAppLibrary.qml" &&
   grep -q 'appRows(query)' "$services_root/AureliaAppLibrary.qml" &&
   grep -q 'AureliaAppLibrary 1.0 AureliaAppLibrary.qml' "$services_root/qmldir" &&
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
   grep -q 'cursorVisible: activeFocus && text.length > 0' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'text.length === 0 && activeFocus' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'function globalRows' "$command_center_root/ui/CommandCenterModel.qml" &&
   grep -q 'sortRowsWithFilesLast' "$command_center_root/ui/CommandCenterModel.qml" &&
   grep -q 'moduleRegistry.moduleRows()' "$command_center_root/ui/CommandCenterModel.qml" &&
   grep -q 'PointerMoveGate {' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'referenceItem: card' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'function selectRowFromPointer' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'pointerGate.moved' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'function onQueryChanged() { pointerGate.reset() }' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'launch-app' "$command_center_root/ui/CommandCenterModel.qml" &&
   grep -q 'open-path' "$command_center_root/ui/CommandCenterModel.qml" &&
   grep -q 'property Timer fileRequestTimer: Timer' "$command_center_root/ui/CommandCenterModel.qml" &&
   grep -q 'property Process actionsProcess: Process' "$command_center_root/ui/CommandCenterModel.qml" &&
   grep -q 'property Connections appLibraryConnection: Connections' "$command_center_root/ui/CommandCenterModel.qml" &&
   ! grep -q 'Theme.fontSizeXxl' "$command_center_root/ui/CommandCenterPanel.qml" &&
   ! grep -Eq '(^|[[:space:];])eval([[:space:];]|$)' "$command_center_root/ui/CommandCenterModel.qml" "$command_center_root/ui/CommandCenterPanel.qml"; then
    pass "Keyboard-first navigation, type-to-search, and stable current-row highlighting are explicit"
else
    fail "Command Center keyboard or selection behavior is incomplete"
fi

if ! grep -q 'text: "ESC"' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'function iconGlyphForRow' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'modelData.kind !== "app"' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'visible: selected' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'onPositionChanged: function(mouse)' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'selectRowFromPointer(parent, index, mouse)' "$command_center_root/ui/CommandCenterPanel.qml" &&
   ! grep -q 'Theme.selectionHover' "$command_center_root/ui/CommandCenterPanel.qml" &&
   ! grep -q 'HoverHandler { id: rowHover }' "$command_center_root/ui/CommandCenterPanel.qml" &&
   ! grep -q 'readonly property bool hovered' "$command_center_root/ui/CommandCenterPanel.qml" &&
   ! grep -q 'readonly property bool highlighted' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'height: Theme.rowHeight' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'centerModel.results.length' "$command_center_root/ui/CommandCenterPanel.qml"; then
    pass "Command Center uses semantic glyph icons, one keyboard cursor highlight, no ESC header label, and content-driven card sizing"
else
    fail "Command Center icon or single-highlight visual contract is incomplete"
fi

escape_handler="$(sed -n '/if (event.key === Qt.Key_Escape)/,/^[[:space:]]*}/p' "$command_center_root/ui/CommandCenterPanel.qml")"
if [[ "$escape_handler" == *'panelRoot.close()'* ]] &&
   [[ "$escape_handler" != *'centerModel.setQuery'* ]] &&
   [[ "$escape_handler" != *'centerModel.resetModule'* ]] &&
   grep -q 'Qt.Key_Backspace' "$command_center_root/ui/CommandCenterPanel.qml"; then
    pass "Escape closes the Command Center while Backspace remains the back-navigation key"
else
    fail "Command Center Escape dismissal or Backspace navigation contract is incomplete"
fi

card_input_block="$(sed -n '/id: card/,/id: keyCatcher/p' "$command_center_root/ui/CommandCenterPanel.qml")"
key_input_block="$(sed -n '/id: keyCatcher/,/Keys.priority/p' "$command_center_root/ui/CommandCenterPanel.qml")"
if [[ "$card_input_block" == *$'z: 0'* ]] &&
   [[ "$key_input_block" == *$'z: 1'* ]] &&
   grep -q 'required property int index' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'acceptedButtons: Qt.LeftButton' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'centerModel.activateSelected()' "$command_center_root/ui/CommandCenterPanel.qml"; then
    pass "Command Center keeps the card click blocker behind rows and activates the clicked result"
else
    fail "Command Center result-row click ownership or activation contract is incomplete"
fi

if jq -e '
    .version == 1 and
    ([.modules | sort_by(.order) | .[].id] == [
        "apps", "files", "actions", "calculator", "package-manager", "updates",
        "weather", "currency", "metals", "stocks", "aurelia-shell", "about", "plugins"
    ]) and
    ([.modules[].id] | index("apps")) != null and
    ([.modules[].id] | index("actions")) != null and
    ([.modules[].id] | index("updates")) != null and
    ([.modules[].id] | index("about")) != null and
    ([.modules[].id] | index("package-manager")) != null and
    ([.modules[].id] | index("files")) != null and
    ([.modules[].id] | index("calculator")) != null and
    ([.modules[].id] | index("weather")) != null and
    ([.modules[].id] | index("currency")) != null and
    ([.modules[].id] | index("metals")) != null and
    ([.modules[].id] | index("stocks")) != null
   ' "$command_center_root/modules.json" >/dev/null &&
   grep -q 'id: "apps".*order: 10' "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'id: "files".*order: 20' "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'id: "actions".*order: 30' "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'id: "calculator".*order: 40' "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'id: "package-manager".*order: 50' "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'id: "updates".*order: 60' "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'id: "aurelia-shell".*order: 110' "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'id: "about".*order: 120' "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'id: "plugins".*order: 130' "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'userModulesPath' "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'setModuleEnabled' "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'implemented' "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'property FileView defaultFile: FileView' "$command_center_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'property FileView userFile: FileView' "$command_center_root/ui/CommandCenterModuleRegistry.qml"; then
    pass "Command Center has a logically ordered declarative module catalog with user enablement state"
else
    fail "Command Center module catalog or enablement persistence contract is incomplete"
fi

if [[ -x "$ROOT/bin/workstation-updates" ]] &&
   [[ -x "$ROOT/bin/workstation-about" ]] &&
   [[ -x "$ROOT/bin/aurelia-branding-about" ]] &&
   [[ -x "$ROOT/bin/workstation-packages" ]] &&
   [[ -f "$ROOT/config/fastfetch/config.jsonc" ]] &&
   [[ -f "$ROOT/config/branding/aurelia-mark.svg" ]] &&
   [[ -f "$ROOT/config/branding/aurelia-mark.png" ]] &&
   [[ -f "$ROOT/config/branding/aurelia-wordmark.txt" ]] &&
   jq -e '.logo.type == "kitty-direct" and .logo.source == "$AURELIA_ABOUT_IMAGE" and .logo.width == 54 and .logo.height == 26 and .logo.preserveAspectRatio == true' "$ROOT/config/fastfetch/config.jsonc" >/dev/null &&
   grep -q 'kitty-direct' "$ROOT/bin/workstation-about" &&
   grep -q 'sixel' "$ROOT/bin/workstation-about" &&
   grep -q 'resizewindowpixel' "$ROOT/bin/workstation-about" &&
   grep -q 'initial_window_width' "$ROOT/bin/workstation-about" &&
   grep -q 'initial_window_height' "$ROOT/bin/workstation-about" &&
   ! grep -q -- '--logo-type file' "$ROOT/bin/workstation-about" &&
   ! grep -q 'AURELIA_ABOUT_GRAPHICS' "$ROOT/bin/workstation-about" &&
   grep -q 'render_updates_brand()' "$ROOT/bin/workstation-updates" &&
   ! grep -q 'MENU_DETAILS' "$ROOT/bin/workstation-updates" &&
   ! grep -q 'fastfetch' "$ROOT/bin/workstation-updates" &&
   grep -q 'aboutBin' "$command_center_root/CommandCenterPlugin.qml" &&
   grep -q 'aboutBin: panelRoot.aboutBin' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'function openAbout' "$command_center_root/ui/CommandCenterModel.qml" &&
   grep -q 'row.moduleId === "about"' "$command_center_root/ui/CommandCenterModel.qml" &&
   grep -q 'updatesBin' "$command_center_root/CommandCenterPlugin.qml" &&
   grep -q 'updatesBin: panelRoot.updatesBin' "$command_center_root/ui/CommandCenterPanel.qml" &&
   grep -q 'function openUpdates' "$command_center_root/ui/CommandCenterModel.qml" &&
   grep -q 'row.moduleId === "updates"' "$command_center_root/ui/CommandCenterModel.qml" &&
   grep -q 'packagesBin' "$command_center_root/CommandCenterPlugin.qml" &&
   grep -q 'function openPackageManager' "$command_center_root/ui/CommandCenterModel.qml" &&
   grep -q 'row.moduleId === "package-manager"' "$command_center_root/ui/CommandCenterModel.qml" &&
   ! grep -q 'updateProviderId' "$command_center_root/ui/CommandCenterModel.qml"; then
    pass "Updates and Package Manager are terminal-owned Command Center workflows without nested provider UI"
else
    fail "Command Center Updates or Package Manager module/backend boundary is incomplete"
fi

if [[ ! -e "$command_center_root/LauncherPlugin.qml" &&
      ! -e "$command_center_root/ui/LauncherPanel.qml" &&
      ! -e "$command_center_root/ui/LauncherModel.qml" ]]; then
    pass "Obsolete single-purpose launcher implementation is removed from the loadable package"
else
    fail "Obsolete launcher implementation remains alongside Command Center"
fi

if grep -Fq 'class = "^org\\.aurelia\\.updates$"' "$ROOT/../dotfiles/hypr/windowrules.lua" &&
   grep -Fq 'class = "^org\\.aurelia\\.packages$"' "$ROOT/../dotfiles/hypr/windowrules.lua" &&
   grep -q 'float = true' "$ROOT/../dotfiles/hypr/windowrules.lua" &&
   grep -q 'center = true' "$ROOT/../dotfiles/hypr/windowrules.lua"; then
    pass "Updates and Package Manager terminals share centered floating window rules"
else
    fail "Updates or Package Manager floating terminal window rule is missing"
fi
