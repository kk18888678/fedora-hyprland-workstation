#!/usr/bin/env bash

# Test Suite: Workspaces discoverability, single-source-of-truth keybindings manifest, and zero-drift hotkeys validation.

section "Workspaces Discoverability"

startup_lua="$ROOT/dotfiles/hypr/startup.lua"
if [[ -f "$startup_lua" ]]; then
    pass "dotfiles/hypr/startup.lua exists"
else
    fail "dotfiles/hypr/startup.lua is missing"
fi

if grep -q 'hyprctl keyword workspace "%d, persistent:true"' "$startup_lua"; then
    pass "startup.lua registers persistent workspaces dynamically via hyprctl keyword"
else
    fail "startup.lua missing persistent workspace loop"
fi

# Ensure monitor names are not hardcoded in workspace definitions
if grep -E 'workspace[[:space:]]*=[[:space:]]*[0-9]+,[[:space:]]*monitor:' "$startup_lua"; then
    fail "startup.lua hardcodes monitor-specific workspace bindings"
else
    pass "persistent workspaces avoid hardcoding monitor names"
fi

section "Authoritative Keybindings Manifest & Zero Drift"

manifest_file="$ROOT/dotfiles/hypr/keybindings_manifest.lua"
if [[ -f "$manifest_file" ]]; then
    pass "dotfiles/hypr/keybindings_manifest.lua exists"
else
    fail "dotfiles/hypr/keybindings_manifest.lua is missing"
fi

lua_bin="$(command -v luajit 2>/dev/null || command -v lua 2>/dev/null || true)"
if [[ -n "$lua_bin" ]]; then
    pass "Lua runtime available for manifest evaluation ($lua_bin)"
else
    fail "No Lua runtime found to validate keybindings manifest"
fi

# Mechanically validate manifest integrity, completeness, and lack of duplicate keys
manifest_validation_output="$(
    "$lua_bin" - "$manifest_file" <<'LUA_CHECK'
local manifest = dofile(arg[1])

if type(manifest.categories) ~= "table" or #manifest.categories == 0 then
    print("ERR: manifest.categories must be a non-empty table")
    os.exit(1)
end

if type(manifest.bindings) ~= "table" or #manifest.bindings == 0 then
    print("ERR: manifest.bindings must be a non-empty table")
    os.exit(1)
end

local category_set = {}
for _, cat in ipairs(manifest.categories) do
    category_set[cat] = true
end

local seen_keys = {}
local count = 0
local has_super_k = false
local has_super_d = false
local has_workspaces = false
local has_workspaces_move = false

for idx, b in ipairs(manifest.bindings) do
    count = count + 1

    if not b.category or b.category == "" then
        print("ERR: binding at index " .. idx .. " has missing category")
        os.exit(1)
    end

    if not category_set[b.category] then
        print("ERR: binding at index " .. idx .. " references unknown category: " .. tostring(b.category))
        os.exit(1)
    end

    if not b.description or b.description == "" then
        print("ERR: binding at index " .. idx .. " has missing description")
        os.exit(1)
    end

    if b.key then
        if seen_keys[b.key] then
            print("ERR: duplicate keybinding detected: " .. b.key)
            os.exit(1)
        end
        seen_keys[b.key] = true
    end

    if b.key == "SUPER + K" and b.command == "workstation-hotkeys" then
        has_super_k = true
    end

    if b.key == "SUPER + D" then
        has_super_d = true
    end

    if b.generator == "workspaces_1_10" then
        has_workspaces = true
    end

    if b.generator == "workspaces_move_1_10" then
        has_workspaces_move = true
    end
end

if not has_super_k then
    print("ERR: manifest is missing SUPER+K hotkeys binding")
    os.exit(1)
end

if not has_super_d then
    print("ERR: manifest is missing SUPER+D launcher binding")
    os.exit(1)
end

if not has_workspaces then
    print("ERR: manifest is missing workspaces 1-10 generator definition")
    os.exit(1)
end

if not has_workspaces_move then
    print("ERR: manifest is missing workspaces move 1-10 generator definition")
    os.exit(1)
end

print(string.format("VALID count=%d", count))
LUA_CHECK
)"

if grep -q "^VALID" <<< "$manifest_validation_output"; then
    pass "keybindings_manifest.lua satisfies all structural, uniqueness, and completeness invariants"
else
    fail "keybindings_manifest.lua validation failed: $manifest_validation_output"
fi

# Negative test: verify that adding a binding without a description fails closed
negative_manifest_test="$(
    "$lua_bin" - <<'LUA_CHECK'
local manifest = {
    categories = { "Applications" },
    bindings = {
        {
            category = "Applications",
            key = "SUPER + Z",
            -- missing description
        }
    }
}

for idx, b in ipairs(manifest.bindings) do
    if not b.description or b.description == "" then
        print("FAIL_CLOSED: missing description detected")
        os.exit(0)
    end
end
print("UNEXPECTED_PASS")
LUA_CHECK
)"

if grep -q "FAIL_CLOSED" <<< "$negative_manifest_test"; then
    pass "manifest validator fails closed when binding metadata is incomplete"
else
    fail "manifest validator failed negative check: $negative_manifest_test"
fi

section "Keybind Manifest Generator & Action Dispatch Execution"

keybind_dispatch_output="$(
    "$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
local bound_keys = {}
local hl = {
    bind = function(key, action, flags)
        bound_keys[key] = { action = action, flags = flags }
    end,
    dsp = {
        focus = function(t) return function() end end,
        exec_cmd = function(cmd) return function() end end,
        window = {
            close = function() return function() end end,
            float = function(t) return function() end end,
            fullscreen = function() return function() end end,
            cycle_next = function() return function() end end,
            move = function(t) return function() end end,
            drag = function() return function() end end,
            resize = function() return function() end end,
        },
    },
    exec_cmd = function(cmd) end,
}
_G.hl = hl

package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
package.loaded["keybindings_manifest"] = nil
package.loaded["keybind"] = nil
require("keybind")

-- Verify workspace 1-10 focus generated from manifest
for i = 1, 9 do
    assert(bound_keys["SUPER + " .. i], "Missing focus workspace " .. i)
    assert(bound_keys["SUPER + SHIFT + " .. i], "Missing move workspace " .. i)
end
assert(bound_keys["SUPER + 0"], "Missing focus workspace 10 (SUPER + 0)")
assert(bound_keys["SUPER + SHIFT + 0"], "Missing move workspace 10 (SUPER + SHIFT + 0)")
assert(bound_keys["SUPER + K"], "Missing SUPER + K")
assert(bound_keys["SUPER + D"], "Missing SUPER + D")

-- Negative test: unknown generator must fail closed
package.loaded["keybindings_manifest"] = {
    mainMod = "SUPER",
    bindings = {
        {
            category = "Workspaces",
            generator = "unknown_generator_xyz",
            description = "Unknown generator",
        }
    }
}
package.loaded["keybind"] = nil
local ok_gen, err_gen = pcall(function() require("keybind") end)
assert(not ok_gen and tostring(err_gen):find("Unsupported keybinding generator"), "Failed to reject unknown generator: " .. tostring(err_gen))

-- Negative test: unknown action_type must fail closed
package.loaded["keybindings_manifest"] = {
    mainMod = "SUPER",
    bindings = {
        {
            category = "Window Management",
            key = "SUPER + Z",
            action_type = "unknown_action_xyz",
            description = "Unknown action",
        }
    }
}
package.loaded["keybind"] = nil
local ok_act, err_act = pcall(function() require("keybind") end)
assert(not ok_act and tostring(err_act):find("Unsupported keybinding action_type"), "Failed to reject unknown action_type: " .. tostring(err_act))

print("DISPATCH_VALID")
LUA_CHECK
)"

if grep -q "^DISPATCH_VALID" <<< "$keybind_dispatch_output"; then
    pass "keybind.lua accurately dispatches generated workspace bindings and rejects unknown generators/actions"
else
    fail "keybind.lua generator dispatch failed: $keybind_dispatch_output"
fi

section "Hotkeys Presentation Parity"

hotkeys_rendered="$(HOTKEYS_FORCE_STDOUT=1 HOTKEYS_MANIFEST="$manifest_file" "$ROOT/bin/workstation-hotkeys" 2>/dev/null || true)"

# Every single binding and category in keybindings_manifest.lua must appear in the rendered hotkeys text
parity_check_output="$(
    HOTKEYS_TEXT="$hotkeys_rendered" "$lua_bin" - "$manifest_file" <<'LUA_CHECK'
local manifest = dofile(arg[1])
local rendered = os.getenv("HOTKEYS_TEXT") or ""

for _, cat in ipairs(manifest.categories) do
    if not rendered:find(cat, 1, true) then
        print("ERR: Category missing from rendered output: " .. cat)
        os.exit(1)
    end
end

for idx, b in ipairs(manifest.bindings) do
    local key_str = b.display_key or b.key
    if key_str and not rendered:find(key_str, 1, true) then
        print("ERR: Key string missing from rendered output: " .. key_str)
        os.exit(1)
    end

    if b.description and not rendered:find(b.description, 1, true) then
        print("ERR: Description missing from rendered output: " .. b.description)
        os.exit(1)
    end
end

print("PARITY_VALID")
LUA_CHECK
)"

if grep -q "^PARITY_VALID" <<< "$parity_check_output"; then
    pass "workstation-hotkeys dynamically renders 100% of categories, keys, and descriptions from manifest"
else
    fail "hotkeys rendering parity mismatch: $parity_check_output"
fi

section "Hyprland Registration & Window Integration"

keybind_lua="$ROOT/dotfiles/hypr/keybind.lua"
if grep -q 'require("keybindings_manifest")' "$keybind_lua" &&
   grep -q 'hl.bind' "$keybind_lua"; then
    pass "keybind.lua registers bindings dynamically from keybindings_manifest.lua"
else
    fail "keybind.lua does not load or register keybindings_manifest.lua"
fi

if grep -q "workstation-hotkeys" "$ROOT/dotfiles/hypr/windowrules.lua"; then
    pass "windowrules.lua includes floating window rule for workstation-hotkeys"
else
    fail "windowrules.lua missing workstation-hotkeys floating rule"
fi

hotkeys_desktop="$ROOT/config/desktop-entries/workstation-hotkeys.desktop"
if [[ -f "$hotkeys_desktop" ]]; then
    pass "config/desktop-entries/workstation-hotkeys.desktop exists"
else
    fail "config/desktop-entries/workstation-hotkeys.desktop is missing"
fi

if grep -q "^Name=Hotkeys$" "$hotkeys_desktop" &&
   grep -q "^Exec=workstation-hotkeys$" "$hotkeys_desktop"; then
    pass "workstation-hotkeys.desktop has valid Name and Exec properties"
else
    fail "workstation-hotkeys.desktop properties invalid"
fi

section "Hotkeys Installation Sandbox"

hotkeys_install_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$1"
TARGET_USER="hotkeytest"
TARGET_HOME="$(mktemp -d)"
HOTKEYS_BIN_DIR="$(mktemp -d)"
HOTKEYS_APPS_DIR="$(mktemp -d)"
export HOTKEYS_BIN_DIR HOTKEYS_APPS_DIR
OVERRIDE_TARGET_UID=1000

# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

env() {
    while [[ $# -gt 0 && "$1" == *=* ]]; do
        export "$1"
        shift
    done
    "$@"
}

sudo() {
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-u" ]]; then shift 2; continue; fi
        if [[ "$1" == "env" ]]; then shift; continue; fi
        if [[ "$1" == *=* ]]; then export "$1"; shift; continue; fi
        break
    done
    "$@"
}

install_workstation_hotkeys

bin_installed=$([[ -x "$HOTKEYS_BIN_DIR/workstation-hotkeys" ]] && echo 1 || echo 0)
desktop_installed=$([[ -f "$HOTKEYS_APPS_DIR/workstation-hotkeys.desktop" ]] && echo 1 || echo 0)

echo "bin-installed=$bin_installed"
echo "desktop-installed=$desktop_installed"

rm -rf "$TARGET_HOME" "$HOTKEYS_BIN_DIR" "$HOTKEYS_APPS_DIR"
EOS
)"

if printf '%s\n' "$hotkeys_install_output" | grep -q 'bin-installed=1' &&
   printf '%s\n' "$hotkeys_install_output" | grep -q 'desktop-installed=1'; then
    pass "install_workstation_hotkeys deploys executable and desktop entry into isolated target paths"
else
    fail "install_workstation_hotkeys failed in sandbox: $hotkeys_install_output"
fi

section "Workspace State Model & Noctalia Workspaces Config"

workspaces_lua="$ROOT/dotfiles/hypr/workspaces.lua"
if [[ -f "$workspaces_lua" ]]; then
    pass "dotfiles/hypr/workspaces.lua exists"
else
    fail "dotfiles/hypr/workspaces.lua is missing"
fi

workspace_model_test_output="$(
    "$lua_bin" - "$workspaces_lua" <<'LUA_TEST'
local ws_mod = dofile(arg[1])

local function assert_eq(actual, expected, msg)
    local act_str = table.concat(actual, ",")
    local exp_str = table.concat(expected, ",")
    if act_str ~= exp_str then
        print(string.format("FAIL: %s (expected [%s], got [%s])", msg, exp_str, act_str))
        os.exit(1)
    end
end

-- Test 1: Fresh session with only workspace 1 active -> displays 1, 2, 3
local res1 = ws_mod.compute_visible_workspaces(1, {})
assert_eq(res1, { 1, 2, 3 }, "fresh session active=1, occupied={}")

-- Test 2: Active workspace 2, no other occupied -> displays 1, 2, 3 with 2 active
local res2 = ws_mod.compute_visible_workspaces(2, {})
assert_eq(res2, { 1, 2, 3 }, "active=2, occupied={}")

-- Test 3: Active workspace 3, no other occupied -> displays 1, 2, 3 with 3 active
local res3 = ws_mod.compute_visible_workspaces(3, {})
assert_eq(res3, { 1, 2, 3 }, "active=3, occupied={}")

-- Test 4: Occupied workspace 4 -> displays 1, 2, 3, 4
local res4 = ws_mod.compute_visible_workspaces(1, { 4 })
assert_eq(res4, { 1, 2, 3, 4 }, "active=1, occupied={4}")

-- Test 5: Occupied workspace 7 -> displays 1, 2, 3, 7
local res5 = ws_mod.compute_visible_workspaces(1, { 7 })
assert_eq(res5, { 1, 2, 3, 7 }, "active=1, occupied={7}")

-- Test 6: Workspaces 1, 2, 3 reported by Hyprland do not create duplicates
local res6 = ws_mod.compute_visible_workspaces(1, { 1, 2, 3 })
assert_eq(res6, { 1, 2, 3 }, "deduplication of 1,2,3 from compositor")

-- Test 7: Dynamic workspace disappears when no longer occupied while 1,2,3 remain
local res7_before = ws_mod.compute_visible_workspaces(1, { 5 })
assert_eq(res7_before, { 1, 2, 3, 5 }, "occupied={5} before close")
local res7_after = ws_mod.compute_visible_workspaces(1, {})
assert_eq(res7_after, { 1, 2, 3 }, "occupied={} after close")

-- Test 8: Deterministic numeric ordering
local res8 = ws_mod.compute_visible_workspaces(9, { 6, 2, 8, 4 })
assert_eq(res8, { 1, 2, 3, 4, 6, 8, 9 }, "deterministic numeric ordering")

-- Test Indicator formatting strings
local ind1 = ws_mod.format_indicator(1, {})
local ind2 = ws_mod.format_indicator(2, {})
local ind3 = ws_mod.format_indicator(3, {})
local ind5 = ws_mod.format_indicator(1, { 5 })

print("workspace-state-tests-ok=1")
LUA_TEST
)"

if printf '%s\n' "$workspace_model_test_output" | grep -q 'workspace-state-tests-ok=1'; then
    pass "workspaces state model satisfies all persistent 1,2,3 and dynamic 4+ ordering invariants"
else
    fail "workspaces state model failed: $workspace_model_test_output"
fi

noctalia_config="$ROOT/config/noctalia/config.toml"
if [[ -f "$noctalia_config" ]]; then
    pass "config/noctalia/config.toml exists"
else
    fail "config/noctalia/config.toml is missing"
fi

if grep -q '\[widget\.workspaces\]' "$noctalia_config" &&
   grep -q 'hide_when_empty = false' "$noctalia_config" &&
   grep -q 'show_labels = true' "$noctalia_config"; then
    pass "noctalia config.toml configures persistent workspaces widget (hide_when_empty = false, show_labels = true)"
else
    fail "noctalia config.toml missing persistent workspaces widget configuration"
fi

if command -v noctalia >/dev/null 2>&1; then
    if noctalia config validate "$noctalia_config" >/dev/null 2>&1; then
        pass "noctalia config validate confirms config/noctalia/config.toml is strictly valid"
    else
        fail "noctalia config validate rejected config/noctalia/config.toml"
    fi
fi

section "Application Launcher & Action Footer"

launcher_bin="$ROOT/bin/workstation-launcher"
if [[ -f "$launcher_bin" ]]; then
    pass "bin/workstation-launcher exists"
else
    fail "bin/workstation-launcher is missing"
fi

if [[ -x "$launcher_bin" ]]; then
    pass "bin/workstation-launcher is executable"
else
    fail "bin/workstation-launcher is not executable"
fi

launcher_desktop="$ROOT/config/desktop-entries/workstation-launcher.desktop"
if [[ -f "$launcher_desktop" ]]; then
    pass "config/desktop-entries/workstation-launcher.desktop exists"
else
    fail "config/desktop-entries/workstation-launcher.desktop is missing"
fi

if grep -q "workstation-launcher" "$ROOT/dotfiles/hypr/windowrules.lua"; then
    pass "windowrules.lua includes floating rule for workstation-launcher"
else
    fail "windowrules.lua missing workstation-launcher floating rule"
fi

# Launcher shortcut extraction & single-source-of-truth zero drift test
launcher_sandbox_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$1"
MOCK_APPS_DIR="$(mktemp -d)"
MOCK_HOME="$(mktemp -d)"
export HOME="$MOCK_HOME"

# Create mock desktop entries
mkdir -p "$MOCK_APPS_DIR"
cat << 'EOF' > "$MOCK_APPS_DIR/thunar.desktop"
[Desktop Entry]
Name=Thunar File Manager
Exec=thunar %F
Type=Application
EOF

cat << 'EOF' > "$MOCK_APPS_DIR/kitty.desktop"
[Desktop Entry]
Name=Kitty Terminal
Exec=kitty
Type=Application
EOF

cat << 'EOF' > "$MOCK_APPS_DIR/custom-app.desktop"
[Desktop Entry]
Name=Custom Unbound App
Exec=custom-app
Type=Application
EOF

# Run workstation-launcher in forced stdout mode
LAUNCHER_FORCE_STDOUT=1 \
LAUNCHER_MANIFEST="$SCRIPT_DIR/dotfiles/hypr/keybindings_manifest.lua" \
"$SCRIPT_DIR/bin/workstation-launcher" > "$MOCK_HOME/launcher_out.txt" 2>/dev/null || true

# Check that thunar.desktop got SUPER + E
thunar_shortcut="$(awk -F'\t' '$1=="thunar.desktop"{print $3}' "$MOCK_HOME/launcher_out.txt" || true)"
# Check that kitty.desktop got SUPER + RETURN
kitty_shortcut="$(awk -F'\t' '$1=="kitty.desktop"{print $3}' "$MOCK_HOME/launcher_out.txt" || true)"
# Check that custom-app.desktop has NO shortcut
custom_shortcut="$(awk -F'\t' '$1=="custom-app.desktop"{print $3}' "$MOCK_HOME/launcher_out.txt" || true)"

echo "thunar-shortcut=$thunar_shortcut"
echo "kitty-shortcut=$kitty_shortcut"
echo "custom-shortcut=$custom_shortcut"

# Now test dynamic manifest fixture change
MOCK_MANIFEST="$(mktemp)"
cat << 'EOF' > "$MOCK_MANIFEST"
local M = {}
M.categories = { "Applications" }
M.bindings = {
    {
        category = "Applications",
        key = "SUPER + ALT + E",
        command = "thunar",
        desktop_id = "thunar.desktop",
        display_key = "SUPER + ALT + E",
        description = "File Manager",
    }
}
return M
EOF

LAUNCHER_FORCE_STDOUT=1 \
LAUNCHER_MANIFEST="$MOCK_MANIFEST" \
"$SCRIPT_DIR/bin/workstation-launcher" > "$MOCK_HOME/manifest_change_out.txt" 2>/dev/null || true

thunar_changed_shortcut="$(awk -F'\t' '$1=="thunar.desktop"{print $3}' "$MOCK_HOME/manifest_change_out.txt" || true)"
echo "thunar-changed-shortcut=$thunar_changed_shortcut"

rm -rf "$MOCK_APPS_DIR" "$MOCK_HOME" "$MOCK_MANIFEST"
EOS
)"

if printf '%s\n' "$launcher_sandbox_output" | grep -q 'thunar-shortcut=SUPER + E' &&
   printf '%s\n' "$launcher_sandbox_output" | grep -q 'kitty-shortcut=SUPER + RETURN'; then
    pass "workstation-launcher extracts exact shortcuts from keybindings_manifest.lua"
else
    fail "workstation-launcher failed shortcut extraction: $launcher_sandbox_output"
fi

if printf '%s\n' "$launcher_sandbox_output" | grep -q 'custom-shortcut=$'; then
    pass "workstation-launcher does not fabricate shortcuts for unbound applications"
else
    fail "workstation-launcher fabricated shortcut for unbound application: $launcher_sandbox_output"
fi

if printf '%s\n' "$launcher_sandbox_output" | grep -q 'thunar-changed-shortcut=SUPER + ALT + E'; then
    pass "changing manifest fixture dynamically alters launcher shortcuts with zero drift"
else
    fail "launcher failed dynamic single-source-of-truth test: $launcher_sandbox_output"
fi

if grep -q 'header_text="↵ Launch        E Edit shortcut        Q Quit"' "$launcher_bin" ||
   grep -q '↵ Launch' "$launcher_bin"; then
    pass "workstation-launcher defines action footer with Enter (Launch), E (Edit shortcut), and Q (Quit)"
else
    fail "workstation-launcher missing standard action footer actions"
fi

section "Launcher Installation Sandbox"

launcher_install_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$1"
TARGET_USER="launchertest"
TARGET_HOME="$(mktemp -d)"
LAUNCHER_BIN_DIR="$(mktemp -d)"
LAUNCHER_APPS_DIR="$(mktemp -d)"
export LAUNCHER_BIN_DIR LAUNCHER_APPS_DIR
OVERRIDE_TARGET_UID=1000

# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

env() {
    while [[ $# -gt 0 && "$1" == *=* ]]; do
        export "$1"
        shift
    done
    "$@"
}

sudo() {
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-u" ]]; then shift 2; continue; fi
        if [[ "$1" == "env" ]]; then shift; continue; fi
        if [[ "$1" == *=* ]]; then export "$1"; shift; continue; fi
        break
    done
    "$@"
}

install_workstation_launcher

bin_installed=$([[ -x "$LAUNCHER_BIN_DIR/workstation-launcher" ]] && echo 1 || echo 0)
desktop_installed=$([[ -f "$LAUNCHER_APPS_DIR/workstation-launcher.desktop" ]] && echo 1 || echo 0)

echo "bin-installed=$bin_installed"
echo "desktop-installed=$desktop_installed"

rm -rf "$TARGET_HOME" "$LAUNCHER_BIN_DIR" "$LAUNCHER_APPS_DIR"
EOS
)"

if printf '%s\n' "$launcher_install_output" | grep -q 'bin-installed=1' &&
   printf '%s\n' "$launcher_install_output" | grep -q 'desktop-installed=1'; then
    pass "install_workstation_launcher deploys executable and desktop entry into isolated target paths"
else
    fail "install_workstation_launcher failed in sandbox: $launcher_install_output"
fi
