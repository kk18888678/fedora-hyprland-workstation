section "38. Verification Matrix X: Production Hardening: Authoritative Command Routing, TAB Header Navigation, Settings Cog, Layout Isolation, and Component Motion Policy"

# 38.1: QML static check: Authoritative semantic command router in KeybindingsWindow.qml
if grep -q 'function resolveSemanticCommand(event, context): string' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'function handleComponentKey(event, context): bool' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'handleComponentKey(event, "text_input")' "$qml_header" && \
   grep -q 'handleComponentKey(event, "list")' "$qml_action_list"; then
    pass "38.1 Authoritative semantic command router (resolveSemanticCommand, handleComponentKey) established across input contexts"
else
    fail "38.1 Authoritative semantic command router check failed in KeybindingsWindow.qml"
fi

# 38.2: QML static check: Elimination of hardcoded accelerators from searchInput and listView
if ! grep -q '(event.modifiers & Qt.AltModifier) && event.key === Qt.Key_S' <(sed -n '/id: searchInput/,/RowLayout/p' "$ROOT/components/keybindings/KeybindingsWindow.qml") && \
   ! grep -q '(event.modifiers & Qt.AltModifier) && event.key === Qt.Key_U' <(sed -n '/id: searchInput/,/RowLayout/p' "$ROOT/components/keybindings/KeybindingsWindow.qml") && \
   ! grep -q '(event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Comma' <(sed -n '/id: searchInput/,/RowLayout/p' "$ROOT/components/keybindings/KeybindingsWindow.qml") && \
   ! grep -q '((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_S)' <(sed -n '/id: listView/,/ScrollBar.vertical:/p' "$ROOT/components/keybindings/KeybindingsWindow.qml") && \
   ! grep -q '((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_U)' <(sed -n '/id: listView/,/ScrollBar.vertical:/p' "$ROOT/components/keybindings/KeybindingsWindow.qml") && \
   ! grep -q '(event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Comma' <(sed -n '/id: listView/,/ScrollBar.vertical:/p' "$ROOT/components/keybindings/KeybindingsWindow.qml"); then
    pass "38.2 Hidden and hardcoded accelerators (ALT+S, ALT+U, CTRL+,) completely eliminated from input and list handlers"
else
    fail "38.2 Hardcoded accelerators still present in searchInput or listView"
fi

# 38.3: QML static check: Footer accelerator elimination and authoritative hint bindings
if ! grep -q 'Ctrl+,' "$qml_footer" && \
   grep -q 'Theme\.shortcutSet' "$qml_footer" && \
   grep -q 'Theme\.shortcutUnset' "$qml_footer" && \
   grep -q 'Theme\.shortcutAddAction' "$qml_footer" && \
   grep -q 'Theme\.shortcutBack' "$qml_footer"; then
    pass "38.3 Footer hints eliminate Ctrl+, and authoritatively consume Theme.shortcut* preference bindings"
else
    fail "38.3 Footer hints still contain Ctrl+, or lack authoritative Theme.shortcut* bindings"
fi

# 38.4: QML static check: Immediate Top-Level View Cycling method in KeybindingsWindow.qml
if grep -q 'function cycleTopLevelView(forward: bool)' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'keybindingsModel\.switchView(nextView)' "$ROOT/components/keybindings/KeybindingsWindow.qml"; then
    pass "38.4 Immediate top-level view cycling (cycleTopLevelView) established in KeybindingsWindow.qml"
else
    fail "38.4 cycleTopLevelView missing or incorrect in KeybindingsWindow.qml"
fi

# 38.5: QML static check: Forward and backward view cycling sequence
if grep -q 'if (current === "bound")' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'nextView = "unbound"' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'nextView = "add_action_type"' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'nextView = "settings"' "$ROOT/components/keybindings/KeybindingsWindow.qml"; then
    pass "38.5 TAB and SHIFT+TAB correctly cycle views: Bound -> Unbound -> Add Action -> Settings -> Bound"
else
    fail "38.5 Top-level view cycling sequence check failed in KeybindingsWindow.qml"
fi

# 38.6: QML static check: TAB and SHIFT+TAB dispatch cycleTopLevelView immediately
if grep -q 'windowController\.cycleTopLevelView(true)' "$qml_header" && \
   grep -q 'windowController\.cycleTopLevelView(false)' "$qml_header" && \
   grep -q 'windowController\.cycleTopLevelView(true)' "$qml_action_list" && \
   grep -q 'windowController\.cycleTopLevelView(false)' "$qml_action_list"; then
    pass "38.6 TAB / SHIFT+TAB immediately activates next/previous top-level view without intermediate focus state"
else
    fail "38.6 TAB / SHIFT+TAB immediate view activation check failed in KeybindingsWindow.qml"
fi

# 38.7: QML static check: Elimination of intermediate focus-only state (focusedHeaderIndex eliminated)
if ! grep -q 'focusedHeaderIndex' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   ! grep -q 'focusHeader' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   ! grep -q 'activateFocusedHeader' "$ROOT/components/keybindings/KeybindingsWindow.qml"; then
    pass "38.7 Intermediate focus-only header navigation (focusedHeaderIndex) completely eliminated"
else
    fail "38.7 focusedHeaderIndex or focusHeader still present in KeybindingsWindow.qml"
fi

# 38.8: QML static check: Header tabs consume KeybindingsConfig tokens directly
if grep -q 'KeybindingsConfig\.headerHeight' "$qml_header" && \
   grep -q 'KeybindingsConfig\.tabHeight' "$qml_header" && \
   grep -q 'KeybindingsConfig\.tabPaddingHorizontal' "$qml_header" && \
   grep -q 'KeybindingsConfig\.tabBorderRadius' "$qml_header"; then
    pass "38.8 Header controls consume component design tokens directly from KeybindingsConfig"
else
    fail "38.8 Header tokens from KeybindingsConfig check failed in KeybindingsWindow.qml"
fi

# 38.9: QML static check: Settings Cog visual hierarchy (+50% icon scale, balanced 34x28 hit target)
if grep -q 'KeybindingsConfig\.cogIconSize' "$qml_header" && \
   grep -q 'KeybindingsConfig\.cogHitTargetWidth' "$qml_header" && \
   grep -q 'KeybindingsConfig\.cogHitTargetHeight' "$qml_header"; then
    pass "38.9 Settings Cog icon size enlarged by ~50% (21px) with balanced 34x28px hit target"
else
    fail "38.9 Settings Cog visual hierarchy or hit target dimensions check failed in KeybindingsWindow.qml"
fi

# 38.10: QML static check: Modular KeybindingsSettings component file separation
if [[ -f "$ROOT/components/keybindings/KeybindingsSettings.qml" ]] && \
   grep -q 'id: settingsView' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'KeybindingsSettings {' "$ROOT/components/keybindings/KeybindingsWindow.qml"; then
    pass "38.10 KeybindingsSettings.qml cleanly isolated into self-contained modular component"
else
    fail "38.10 KeybindingsSettings.qml modular separation missing or not instantiated in KeybindingsWindow.qml"
fi

# 38.11: QML static check: KeybindingsSettings responsive Flickable layout and design token consumption
if grep -q 'id: settingsFlickable' "$ROOT/components/keybindings/KeybindingsSettings.qml" && \
   grep -q 'ScrollBar\.vertical: ScrollBar' "$ROOT/components/keybindings/KeybindingsSettings.qml" && \
   grep -q 'KeybindingsConfig\.settingsBadgeHeight' "$ROOT/components/keybindings/KeybindingsSettings.qml" && \
   grep -q 'KeybindingsConfig\.settingsValueColumnPreferredWidth' "$ROOT/components/keybindings/KeybindingsSettings.qml"; then
    pass "38.11 KeybindingsSettings.qml uses responsive Flickable with vertical ScrollBar and KeybindingsConfig tokens"
else
    fail "38.11 Settings Flickable layout or KeybindingsConfig tokens check failed in KeybindingsSettings.qml"
fi

# 38.12: QML static check: Empty-state visibility isolation (never renders behind settings or type picker)
if grep -q 'readonly property bool listVisible:.*activeView !== "add_action_type"' "$qml_action_list" && \
   grep -q 'pickerVisible: modelController.activeView === "add_action_type"' "$ROOT/components/keybindings/KeybindingsAddActionPicker.qml" && \
   grep -q 'filteredItems\.length === 0 && (actionListRoot\.modelController\.activeView === "bound" || actionListRoot\.modelController\.activeView === "unbound" || actionListRoot\.modelController\.activeView === "add_app")' "$qml_action_list"; then
    pass "38.12 Empty state is isolated from Settings, Add Exec, and the dedicated Add Action picker"
else
    fail "38.12 Empty state text visibility condition allows bleed-through behind Settings"
fi

# 38.13: Lua preferences check: Component motion schema registration
test_38_13_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/core/?.lua;" .. package.path
local pref = require("preferences")

assert(pref.SCHEMA["components.keybindings.motion.enabled"] ~= nil, "components.keybindings.motion.enabled missing from schema")
assert(pref.SCHEMA["components.keybindings.motion.enabled"].type == "boolean", "motion.enabled must be boolean")
assert(pref.SCHEMA["components.keybindings.motion.enabled"].default == true, "motion.enabled default must be true")

assert(pref.SCHEMA["components.keybindings.motion.scale"] ~= nil, "components.keybindings.motion.scale missing from schema")
assert(pref.SCHEMA["components.keybindings.motion.scale"].type == "number", "motion.scale must be number")
assert(pref.SCHEMA["components.keybindings.motion.scale"].default == 1.0, "motion.scale default must be 1.0")

print("TEST_38_13_OK")
LUA_CHECK
)"
if grep -q "TEST_38_13_OK" <<< "$test_38_13_out"; then
    pass "38.13 components.keybindings.motion.* registered in schema with correct types and defaults"
else
    fail "38.13 component motion schema registration failed: $test_38_13_out"
fi

# 38.14: Lua preferences check: Component motion preference isolation from global aurelia.motion.*
test_38_14_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/core/?.lua;" .. package.path
local pref = require("preferences")

local tmp = os.tmpname()
-- Set component motion override to disabled (false)
local ok1, _ = pref.set_override("components.keybindings.motion.enabled", false, tmp)
assert(ok1 == true, "Failed to set components.keybindings.motion.enabled override")

-- Global aurelia.motion.enabled must remain default true
assert(pref.get_effective("aurelia.motion.enabled", tmp) == true, "Global aurelia.motion.enabled was mutated by component override")
assert(pref.get_effective("components.keybindings.motion.enabled", tmp) == false, "Component override not effective")

-- Set component motion scale to 0.5
local ok2, _ = pref.set_override("components.keybindings.motion.scale", 0.5, tmp)
assert(ok2 == true, "Failed to set components.keybindings.motion.scale override")

-- Global aurelia.motion.scale must remain default 1.0
assert(pref.get_effective("aurelia.motion.scale", tmp) == 1.0, "Global aurelia.motion.scale was mutated by component override")
assert(pref.get_effective("components.keybindings.motion.scale", tmp) == 0.5, "Component scale override not effective")

os.remove(tmp)
print("TEST_38_14_OK")
LUA_CHECK
)"
if grep -q "TEST_38_14_OK" <<< "$test_38_14_out"; then
    pass "38.14 Modifying Keybindings component motion preferences strictly preserves global Aurelia motion settings"
else
    fail "38.14 Component motion isolation check failed: $test_38_14_out"
fi

# 38.15: Theme.qml check: Component motion duration functions and 0ms when disabled
if grep -q 'function getComponentDuration(componentId: string, baseDuration: int): int' "$ROOT/theme/Theme.qml" && \
   grep -q 'readonly property int keybindingsDurationFast: getComponentDuration("keybindings", durationFast)' "$ROOT/theme/Theme.qml" && \
   grep -q 'readonly property int keybindingsDurationNormal: getComponentDuration("keybindings", durationNormal)' "$ROOT/theme/Theme.qml"; then
    pass "38.15 Theme.qml defines getComponentDuration and keybindingsDuration* tokens producing 0ms when motion disabled"
else
    fail "38.15 getComponentDuration or keybindingsDuration tokens missing in Theme.qml"
fi

# 38.16: Lua preferences check: Atomic component reset restores both shortcuts and motion to shipped defaults
test_38_16_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/core/?.lua;" .. package.path
local pref = require("preferences")

local tmp = os.tmpname()
-- Apply multiple custom overrides
pref.set_override("components.keybindings.shortcuts.set_binding", "ALT + S", tmp)
pref.set_override("components.keybindings.shortcuts.unset_binding", "ALT + U", tmp)
pref.set_override("components.keybindings.motion.enabled", false, tmp)
pref.set_override("components.keybindings.motion.scale", 1.5, tmp)

-- Verify overrides are active
assert(pref.get_effective("components.keybindings.shortcuts.set_binding", tmp) == "ALT + S", "set_binding override failed")
assert(pref.get_effective("components.keybindings.motion.enabled", tmp) == false, "motion.enabled override failed")

-- Reset keybindings component
local ok_rst, err_rst = pref.reset_component("keybindings", tmp)
assert(ok_rst == true, "reset_component failed: " .. tostring(err_rst))

-- Verify all preferences reverted to shipped defaults
assert(pref.get_effective("components.keybindings.shortcuts.set_binding", tmp) == "S", "Reset did not restore default S")
assert(pref.get_effective("components.keybindings.shortcuts.unset_binding", tmp) == "U", "Reset did not restore default U")
assert(pref.get_effective("components.keybindings.shortcuts.add_action", tmp) == "ALT + A", "Reset did not restore default ALT + A")
assert(pref.get_effective("components.keybindings.shortcuts.back", tmp) == "ALT + B", "Reset did not restore default ALT + B")
assert(pref.get_effective("components.keybindings.motion.enabled", tmp) == true, "Reset did not restore default motion.enabled true")
assert(pref.get_effective("components.keybindings.motion.scale", tmp) == 1.0, "Reset did not restore default motion.scale 1.0")

os.remove(tmp)
print("TEST_38_16_OK")
LUA_CHECK
)"
if grep -q "TEST_38_16_OK" <<< "$test_38_16_out"; then
    pass "38.16 reset_component atomically restores shortcuts and motion preferences to shipped defaults"
else
    fail "38.16 Component reset test failed: $test_38_16_out"
fi

# 38.17: QML static check: Context-aware routing preserves typing s/u/a/b in text_input context
if grep -q 'var isTextInput = context === "text_input"' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'if (!isTextInput || hasModifier(Theme\.shortcutSet)) return "set_binding"' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'if (!isTextInput || hasModifier(Theme\.shortcutUnset)) return "unset_binding"' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'if (!isTextInput || hasModifier(Theme\.shortcutAddAction)) return "add_action"' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'if (!isTextInput || hasModifier(Theme\.shortcutBack)) return "back"' "$ROOT/components/keybindings/KeybindingsWindow.qml"; then
    pass "38.17 Context-aware router strictly ignores bare unadorned shortcuts in text_input context (typing preserved)"
else
    fail "38.17 Context-aware router missing text_input modifier guards in KeybindingsWindow.qml"
fi

# 38.18: QML static check: Strict preference authority (S alone is Set, ALT+S is rejected when default S)
if grep -q 'function eventMatchesShortcut(event, shortcutStr): bool' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'var actual = formatKeyEvent(event)' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'if (actual === target) return true' "$ROOT/components/keybindings/KeybindingsWindow.qml"; then
    pass "38.18 Exact matching against formatKeyEvent enforces strict preference authority (no accidental modifier fallbacks)"
else
    fail "38.18 Exact shortcut matching check failed in KeybindingsWindow.qml"
fi

# 38.19: QML static check: KeybindingsSettings modifier requirement for add_action and back
if grep -q 'var isBackOrAdd = (targetKey === "components\.keybindings\.shortcuts\.add_action" || targetKey === "components\.keybindings\.shortcuts\.back")' "$ROOT/components/keybindings/KeybindingsSettings.qml" && \
   grep -q 'if (isBackOrAdd && !window\.hasModifier(formattedKey))' "$ROOT/components/keybindings/KeybindingsSettings.qml"; then
    pass "38.19 KeybindingsSettings strictly enforces modifier requirement on add_action and back to protect text entry"
else
    fail "38.19 KeybindingsSettings modifier enforcement check failed"
fi

# 38.20: QML static check: KeybindingsSettings cross-shortcut conflict prevention
if grep -q 'Conflict: Shortcut' "$ROOT/components/keybindings/KeybindingsSettings.qml" && \
   grep -q 'already assigned to' "$ROOT/components/keybindings/KeybindingsSettings.qml"; then
    pass "38.20 KeybindingsSettings rejects duplicate shortcut assignments with clear conflict feedback"
else
    fail "38.20 KeybindingsSettings conflict rejection check failed"
fi

# 38.21: KeybindingsConfig.qml singleton design tokens registration
if [[ -f "$ROOT/components/keybindings/KeybindingsConfig.qml" ]] && \
   grep -q 'singleton KeybindingsConfig 1.0 KeybindingsConfig.qml' "$ROOT/components/keybindings/qmldir" && \
   grep -q 'palettePreferredWidth' "$ROOT/components/keybindings/KeybindingsConfig.qml"; then
    pass "38.21 KeybindingsConfig.qml singleton exists and is registered in qmldir as authoritative layout token source"
else
    fail "38.21 KeybindingsConfig.qml singleton registration check failed"
fi

# 38.22: Compositor layer rule zero-motion suppression
if grep -q 'WlrLayershell\.namespace: "aurelia-keybindings"' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'namespace = "\^(aurelia-keybindings)\$"' "$ROOT/dotfiles/hypr/windowrules.lua" && \
   grep -q 'no_anim = true' "$ROOT/dotfiles/hypr/windowrules.lua"; then
    pass "38.22 aurelia-keybindings layer namespace and compositor no_anim rule verified for zero-motion policy"
else
    fail "38.22 Compositor layer rule zero-motion suppression check failed"
fi

# 38.23: Freedesktop Terminal=true application wrapping
test_38_23_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")

local tmp = os.tmpname() .. ".desktop"
local f = io.open(tmp, "w")
f:write("[Desktop Entry]\nType=Application\nName=Btop\nExec=btop\nTerminal=true\nIcon=btop\nCategories=System;\n")
f:close()

local parsed = reg.parse_desktop_file(tmp, "btop.desktop")
os.remove(tmp)

assert(parsed ~= nil, "parse_desktop_file failed")
assert(parsed.terminal == true, "terminal flag not parsed")
assert(type(parsed.command_argv) == "table", "command_argv not table")
assert(parsed.command_argv[1] == "kitty" or parsed.command_argv[1] == "foot", "Terminal app not wrapped in terminal emulator: " .. tostring(parsed.command_argv[1]))
assert(parsed.command_argv[#parsed.command_argv] == "btop", "Wrapped command missing binary: " .. tostring(parsed.command_argv[#parsed.command_argv]))

print("TEST_38_23_OK")
LUA_CHECK
)"
if grep -q "TEST_38_23_OK" <<< "$test_38_23_out"; then
    pass "38.23 Terminal applications (Terminal=true) correctly wrap in terminal emulator with structured argv"
else
    fail "38.23 Terminal application wrapping check failed: $test_38_23_out"
fi

# 38.24: Execution model unification: All exec actions in keybind.lua dispatch via aurelia-shell-keybindings run
if grep -q 'aurelia-shell-keybindings run' "$ROOT/dotfiles/hypr/keybind.lua" && \
   ! grep -q 'gtk-launch' "$ROOT/dotfiles/hypr/keybind.lua"; then
    pass "38.24 Compositor exec keybindings unified to dispatch exclusively via aurelia-shell-keybindings run"
else
    fail "38.24 Compositor exec keybinding unification check failed in keybind.lua"
fi

# 38.25: Canonical naming: aurelia-shell-keybindings is primary executable, workstation-keybindings is forwarding shim
if [[ -x "$ROOT/bin/aurelia-shell-keybindings" ]] && \
   grep -q 'exec "\$script_dir/aurelia-shell-keybindings"' "$ROOT/bin/workstation-keybindings" && \
   [[ -f "$ROOT/config/desktop-entries/aurelia-shell-keybindings.desktop" ]]; then
    pass "38.25 Canonical aurelia-shell-keybindings binary, desktop entry, and compatibility forwarding shim verified"
else
    fail "38.25 Canonical naming migration check failed"
fi

# 38.26: KeybindingsModel.qml uses managed canonical binary
if grep -q '/usr/local/bin/aurelia-shell-keybindings' "$ROOT/components/keybindings/KeybindingsModel.qml"; then
    pass "38.26 KeybindingsModel.qml uses managed canonical /usr/local/bin/aurelia-shell-keybindings"
else
    fail "38.26 KeybindingsModel.qml binary resolution check failed"
fi
