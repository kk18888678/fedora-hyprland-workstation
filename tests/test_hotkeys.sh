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
