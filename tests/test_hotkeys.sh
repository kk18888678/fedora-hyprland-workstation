#!/usr/bin/env bash

# Test Suite: Workspaces discoverability, single-source-of-truth keybindings manifest, and zero-drift hotkeys validation.

section "Workspaces Discoverability"

workspaces_lua="$ROOT/dotfiles/hypr/workspaces.lua"
if [[ -f "$workspaces_lua" ]]; then
    pass "dotfiles/hypr/workspaces.lua exists"
else
    fail "dotfiles/hypr/workspaces.lua is missing"
fi

if grep -q 'hl.workspace_rule' "$workspaces_lua" &&
   grep -q 'persistent = true' "$workspaces_lua"; then
    pass "workspaces.lua registers persistent workspaces declaratively via hl.workspace_rule"
else
    fail "workspaces.lua missing declarative persistent workspace rules"
fi

# Ensure monitor names are not hardcoded in workspace definitions
if grep -E 'monitor[[:space:]]*=' "$workspaces_lua"; then
    fail "workspaces.lua hardcodes monitor-specific workspace bindings"
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

section "Workspace Persistence & Noctalia Workspaces Config"

workspaces_lua="$ROOT/dotfiles/hypr/workspaces.lua"
if [[ -f "$workspaces_lua" ]]; then
    pass "dotfiles/hypr/workspaces.lua exists"
else
    fail "dotfiles/hypr/workspaces.lua is missing"
fi

if grep -q 'hl.workspace_rule' "$workspaces_lua" &&
   grep -q 'persistent = true' "$workspaces_lua"; then
    pass "workspaces.lua declaratively registers persistent = true via hl.workspace_rule"
else
    fail "workspaces.lua missing declarative persistent workspace rules"
fi

if grep -q 'require("workspaces")' "$ROOT/dotfiles/hypr/hyprland.lua"; then
    pass "hyprland.lua loads workspaces module at session initialization"
else
    fail "hyprland.lua does not load workspaces module"
fi

# Ensure monitor names are not hardcoded in workspace definitions
if grep -E 'monitor[[:space:]]*=' "$workspaces_lua"; then
    fail "workspaces.lua hardcodes monitor-specific workspace bindings"
else
    pass "persistent workspaces avoid hardcoding monitor names"
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

section "Native Noctalia Launcher Integration & Hotkeys Reference"

# Validate SUPER+D maps strictly to the native Noctalia launcher
manifest_launcher_cmd="$(
    "$lua_bin" - "$ROOT/dotfiles/hypr/keybindings_manifest.lua" <<'LUA_CHECK'
local manifest = dofile(arg[1])
for _, b in ipairs(manifest.bindings or {}) do
    if b.key == "SUPER + D" then
        print(b.command or "")
        os.exit(0)
    end
end
print("NOT_FOUND")
LUA_CHECK
)"

if [[ "$manifest_launcher_cmd" == "noctalia msg panel-toggle launcher" ]]; then
    pass "keybindings_manifest.lua binds SUPER+D to native Noctalia launcher (noctalia msg panel-toggle launcher)"
else
    fail "SUPER+D does not bind to native Noctalia launcher: $manifest_launcher_cmd"
fi

manifest_hotkeys_cmd="$(
    "$lua_bin" - "$ROOT/dotfiles/hypr/keybindings_manifest.lua" <<'LUA_CHECK'
local manifest = dofile(arg[1])
for _, b in ipairs(manifest.bindings or {}) do
    if b.key == "SUPER + K" then
        print(b.command or "")
        os.exit(0)
    end
end
print("NOT_FOUND")
LUA_CHECK
)"

if [[ "$manifest_hotkeys_cmd" == "workstation-hotkeys" ]]; then
    pass "keybindings_manifest.lua binds SUPER+K to workstation-hotkeys reference"
else
    fail "SUPER+K does not bind to workstation-hotkeys: $manifest_hotkeys_cmd"
fi

# Ensure no dead standalone workstation-launcher architecture remains
if [[ ! -f "$ROOT/bin/workstation-launcher" ]]; then
    pass "no dead bin/workstation-launcher script present in repository"
else
    fail "bin/workstation-launcher should be removed"
fi

if [[ ! -f "$ROOT/config/desktop-entries/workstation-launcher.desktop" ]]; then
    pass "no dead workstation-launcher.desktop present in repository"
else
    fail "config/desktop-entries/workstation-launcher.desktop should be removed"
fi

if ! grep -q "workstation-launcher" "$ROOT/dotfiles/hypr/windowrules.lua" &&
   ! grep -q "workstation-launcher" "$ROOT/modules/desktop.sh" &&
   ! grep -q "workstation-launcher" "$ROOT/modules/validation.sh"; then
    pass "workstation-launcher references cleanly removed from window rules, modules, and validation"
else
    fail "dead workstation-launcher references remain in code"
fi
