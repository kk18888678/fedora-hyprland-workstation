section "37. Verification Matrix W: Browse Layer Mask & Suppression, Click Ownership, ALT+B Back Navigation, Preferences Shortcuts Registry, Form Tabs Isolation, and Gesture Model Filtering"

# 37.1: QML static check: Browse dismissal suppression & layer-shell mask with Region
if grep -q 'mask: windowRoot\.browseActive ? browseRegion : null' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'Region {' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'id: browseRegion' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'item: surfaceCard' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'enabled: !windowRoot\.browseActive' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'if (windowRoot\.browseActive)' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'if (!windowController\.browseActive)' "$qml_form"; then
    pass "37.1 layer-shell mask Region, outside dismissal guard, and form input preservation verified"
else
    fail "37.1 browse dismissal suppression or layer-shell mask check failed"
fi

# 37.2: QML static check: Single-click Add Action navigation and no double-click fallthrough
if grep -q 'viewAtClick === "add_action_type"' "$ROOT/components/keybindings/KeybindingRow.qml" && \
   grep -q 'windowRoot.activateSelected("mouse")' "$ROOT/components/keybindings/KeybindingRow.qml" && \
   grep -q 'viewAtClick' "$ROOT/components/keybindings/KeybindingRow.qml" && \
   ! grep -q 'onDoubleClicked: {' "$ROOT/components/keybindings/KeybindingRow.qml"; then
    pass "37.2 single-click activates add_action_type immediately with explicit click ownership"
else
    fail "37.2 single-click navigation check failed in KeybindingRow.qml"
fi

# 37.3: QML static check: ALT + B Back navigation & plain b text entry preservation in search and form fields
if grep -q 'eventMatchesShortcut(event, Theme\.shortcutBack)' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'windowController\.eventMatchesShortcut(event, Theme\.shortcutBack)' "$qml_form" && \
   ! grep -E -q 'event\.key === Qt\.Key_B([^A-Za-z_]|$)' "$qml_window" "$qml_header" "$qml_form"; then
    pass "37.3 Back navigation uses Theme.shortcutBack and eliminates bare Key_B interception"
else
    fail "37.3 Back navigation check failed in KeybindingsWindow.qml"
fi

# 37.4: Lua preferences unit check: UI control shortcuts schema, modifier requirement, and conflict rejection
test_37_4_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/core/?.lua;" .. package.path
local pref = require("preferences")

-- 1. Schema verification: defaults
assert(pref.SCHEMA["components.keybindings.shortcuts.add_action"].default == "ALT + A", "add_action default mismatch")
assert(pref.SCHEMA["components.keybindings.shortcuts.back"].default == "ALT + B", "back default mismatch")
assert(pref.SCHEMA["components.keybindings.shortcuts.set_binding"].default == "S", "set_binding default mismatch")
assert(pref.SCHEMA["components.keybindings.shortcuts.unset_binding"].default == "U", "unset_binding default mismatch")

-- 2. Normalization & modifier requirements
local ok1, val1 = pref.validate_key_and_value("components.keybindings.shortcuts.back", "alt + b")
assert(ok1 == true and val1 == "ALT + B", "Normalization to ALT + B failed")

local ok2, val2 = pref.validate_key_and_value("components.keybindings.shortcuts.back", "ctrl + alt + b")
assert(ok2 == true and val2 == "CTRL + ALT + B", "Normalization to CTRL + ALT + B failed")

-- Unadorned key for back/add_action must be rejected (requires modifier)
local ok_bare, err_bare = pref.validate_key_and_value("components.keybindings.shortcuts.back", "B")
assert(ok_bare == false, "Bare key B for back was accepted without modifier")

local ok_bare_a, _ = pref.validate_key_and_value("components.keybindings.shortcuts.add_action", "A")
assert(ok_bare_a == false, "Bare key A for add_action was accepted without modifier")

-- Unadorned key for set_binding/unset_binding is allowed
local ok_set, val_set = pref.validate_key_and_value("components.keybindings.shortcuts.set_binding", "s")
assert(ok_set == true and val_set == "S", "Unadorned key S for set_binding was rejected")

-- 3. Conflict detection
local tmp = os.tmpname()
local ok_conf, err_conf = pref.set_override("components.keybindings.shortcuts.back", "ALT + A", tmp)
assert(ok_conf == false, "Shortcut conflict (back = ALT + A) was accepted")
assert(err_conf:find("Conflict") ~= nil, "Missing conflict error message")
os.remove(tmp)

print("TEST_37_4_OK")
LUA_CHECK
)"
if grep -q "TEST_37_4_OK" <<< "$test_37_4_out"; then
    pass "37.4 UI control shortcuts schema, modifier requirement, and conflict rejection verified"
else
    fail "37.4 UI control shortcuts schema validation failed: $test_37_4_out"
fi

# 37.5: Lua preferences unit check: Component reset restores default UI control shortcuts
test_37_5_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/core/?.lua;" .. package.path
local pref = require("preferences")

local tmp = os.tmpname()
-- Apply valid override
local ok_set, _ = pref.set_override("components.keybindings.shortcuts.back", "CTRL + B", tmp)
assert(ok_set == true, "Failed to set valid override")
assert(pref.get_effective("components.keybindings.shortcuts.back", tmp) == "CTRL + B", "Override not effective")

-- Reset component
local ok_rst, err_rst = pref.reset_component("keybindings", tmp)
assert(ok_rst == true, "reset_component failed: " .. tostring(err_rst))
assert(pref.get_effective("components.keybindings.shortcuts.back", tmp) == "ALT + B", "Reset did not restore default ALT + B")
assert(pref.get_effective("components.keybindings.shortcuts.add_action", tmp) == "ALT + A", "Reset did not restore default ALT + A")

os.remove(tmp)
print("TEST_37_5_OK")
LUA_CHECK
)"
if grep -q "TEST_37_5_OK" <<< "$test_37_5_out"; then
    pass "37.5 reset_component restores keybindings UI control shortcuts to shipped defaults"
else
    fail "37.5 component reset check failed: $test_37_5_out"
fi

# 37.6: QML static check: Settings surface in KeybindingsWindow.qml with modular KeybindingsSettings component and reset
if grep -q 'id: settingsView' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'KeybindingsSettings' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'resetComponentPreferences' "$ROOT/components/keybindings/KeybindingsModel.qml" && \
   grep -q 'setComponentPreference' "$ROOT/components/keybindings/KeybindingsModel.qml" && \
   grep -q 'reloadPreferences' "$ROOT/theme/Theme.qml"; then
    pass "37.6 settings surface, modular KeybindingsSettings component, and preference update methods verified"
else
    fail "37.6 settings surface check failed"
fi

# 37.7: QML static check: Executable form tabs and search header suppression
if grep -q 'headerVisible' "$qml_header" && \
   grep -q 'Add Custom Executable / Script' "$qml_form"; then
    pass "37.7 add_exec and settings views cleanly hide search bar and tabs header"
else
    fail "37.7 form tabs or search suppression check failed"
fi

# 37.8: Lua manifest and model check: Gesture and mouse actions excluded from Bound/Unbound lists
test_37_8_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local manifest = require("keybindings_manifest")
local eff = require("effective_bindings")

-- Check manifest declarations
local swipe = nil
local m_drag = nil
for _, item in ipairs(manifest.bindings) do
    if item.id == "workspace_touchpad_swipe" then
        swipe = item
    elseif item.id == "mouse_window_drag" then
        m_drag = item
    end
end

assert(swipe ~= nil, "workspace_touchpad_swipe not found in manifest")
assert(swipe.trigger_type == "gesture", "workspace_touchpad_swipe trigger_type is not gesture")
assert(swipe.keyboard_bindable == false, "workspace_touchpad_swipe keyboard_bindable is not false")

assert(m_drag ~= nil, "mouse_window_drag not found in manifest")
assert(m_drag.trigger_type == "mouse", "mouse_window_drag trigger_type is not mouse")
assert(m_drag.keyboard_bindable == false, "mouse_window_drag keyboard_bindable is not false")

-- Check effective bindings: non-keyboard-bindable actions must never have unbound = true
local eff_list = eff.resolve_bindings(manifest, {})
for _, it in ipairs(eff_list) do
    if it.keyboard_bindable == false then
        assert(it.unbound == false or it.unbound == nil, "Item " .. it.id .. " with keyboard_bindable=false has unbound=true")
    end
end

print("TEST_37_8_OK")
LUA_CHECK
)"
if grep -q "TEST_37_8_OK" <<< "$test_37_8_out" && \
   grep -q 'it\.keyboard_bindable === false || it\.trigger_type === "gesture"' "$ROOT/components/keybindings/KeybindingsModel.qml"; then
    pass "37.8 gesture and mouse actions are strictly excluded from keyboard Bound and Unbound lists"
else
    fail "37.8 gesture model isolation check failed: $test_37_8_out"
fi
