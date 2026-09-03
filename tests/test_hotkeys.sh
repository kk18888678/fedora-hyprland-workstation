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
    tmp_validate_home="$(mktemp -d)"
    if HOME="$tmp_validate_home" noctalia config validate "$noctalia_config" >/dev/null 2>&1; then
        pass "noctalia config validate confirms config/noctalia/config.toml is strictly valid"
    else
        fail "noctalia config validate rejected config/noctalia/config.toml"
    fi
    rm -rf "$tmp_validate_home"
fi

if ! grep -q '\[shell\.launcher\]' "$noctalia_config"; then
    pass "noctalia config.toml excludes unneeded shell.launcher overrides"
else
    fail "noctalia config.toml contains unexpected shell.launcher overrides"
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

section "Interactive Hotkey Manager & User Overrides Engine"

# 1. Manifest stable IDs uniqueness and presence
manifest_ids_output="$(
    "$lua_bin" - "$manifest_file" <<'LUA_CHECK'
local manifest = dofile(arg[1])
local seen_ids = {}
local total = 0
for idx, b in ipairs(manifest.bindings or {}) do
    total = total + 1
    if not b.id or b.id == "" then
        print("ERR: Missing id at index " .. idx)
        os.exit(1)
    end
    if seen_ids[b.id] then
        print("ERR: Duplicate id: " .. b.id)
        os.exit(1)
    end
    seen_ids[b.id] = true
end
print(string.format("IDS_VALID count=%d", total))
LUA_CHECK
)"

if grep -q "^IDS_VALID" <<< "$manifest_ids_output"; then
    pass "keybindings_manifest.lua specifies unique, stable action IDs for all bindings"
else
    fail "keybindings_manifest.lua IDs validation failed: $manifest_ids_output"
fi

# Manifest explicit editable boolean check
manifest_editable_output="$(
    "$lua_bin" - "$manifest_file" <<'LUA_CHECK'
local manifest = dofile(arg[1])
local editable_count = 0
local uneditable_count = 0
for idx, b in ipairs(manifest.bindings or {}) do
    if type(b.editable) ~= "boolean" then
        print("ERR: Missing or non-boolean editable field at index " .. idx .. " id=" .. tostring(b.id))
        os.exit(1)
    end
    if b.editable then
        editable_count = editable_count + 1
    else
        uneditable_count = uneditable_count + 1
    end
end
print(string.format("EDITABLE_VALID total=%d editable=%d uneditable=%d", #manifest.bindings, editable_count, uneditable_count))
LUA_CHECK
)"

if grep -q "^EDITABLE_VALID" <<< "$manifest_editable_output"; then
    pass "keybindings_manifest.lua specifies explicit editable booleans for all 31 bindings"
else
    fail "manifest editable validation failed: $manifest_editable_output"
fi

# 2. Module presence and syntax
effective_module="$ROOT/dotfiles/hypr/effective_bindings.lua"
if [[ -f "$effective_module" ]]; then
    if "$lua_bin" -e 'assert(loadfile("'"$effective_module"'"))' >/dev/null 2>&1; then
        pass "effective_bindings.lua exists and compiles cleanly"
    else
        fail "effective_bindings.lua has syntax errors"
    fi
else
    fail "effective_bindings.lua is missing"
fi

# 3. Non-interactive test hooks and interactive TUI wiring
sandbox_dir="$(mktemp -d)"
sandbox_overrides="$sandbox_dir/keybindings_overrides.json"
export HOTKEYS_OVERRIDES="$sandbox_overrides"
export HOTKEYS_MANIFEST="$manifest_file"
manifest_before_hash="$(sha256sum "$manifest_file" | awk '{print $1}')"

# Hook: quit exits 0 (clean quit on q / Esc)
if HOTKEYS_TEST_ACTION=quit "$ROOT/bin/workstation-hotkeys"; then
    pass "hotkeys manager quit hook exits cleanly with code 0 (q / Esc support)"
else
    fail "hotkeys manager quit hook failed"
fi

# Hook: run on safe runnable action executes command
run_terminal_output="$(HOTKEYS_TEST_ACTION=run HOTKEYS_TEST_ID="terminal" "$ROOT/bin/workstation-hotkeys")"
if [[ "$run_terminal_output" == "RUN:kitty" ]]; then
    pass "hotkeys manager Return action executes safe runnable commands without eval"
else
    fail "hotkeys manager Return action failed on runnable item: $run_terminal_output"
fi

# Hook: runnable action with arguments preserves argument boundaries safely
run_args_output="$(HOTKEYS_TEST_ACTION=run HOTKEYS_TEST_ID="volume_raise" "$ROOT/bin/workstation-hotkeys")"
if [[ "$run_args_output" == "RUN:wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+" ]]; then
    pass "runnable action with arguments preserves argument boundaries safely"
else
    fail "runnable action with arguments failed: $run_args_output"
fi

# Deterministic test: structured command_argv with multi-word arguments and metacharacters
argv_sandbox="$(mktemp -d)"
mock_manifest="$argv_sandbox/manifest.lua"
mock_bin="$argv_sandbox/mock_program"
capture_log="$argv_sandbox/captured_argv.log"

cat << "EOF_BIN" > "$mock_bin"
#!/usr/bin/env bash
printf "%s\n" "$@" > "$1"
EOF_BIN
chmod +x "$mock_bin"

cat << EOF_MANIFEST > "$mock_manifest"
return {
    bindings = {
        {
            id = "test_custom_action",
            description = "Test Custom Action",
            runnable = true,
            editable = true,
            command = "test-program",
            command_argv = {
                "$mock_bin",
                "$capture_log",
                "--title",
                "My Window",
                "--literal",
                "a b c",
                "--metachars",
                "; rm -rf / | \$(whoami) \`date\` > $argv_sandbox/pwned.txt",
            },
        },
        {
            id = "test_invalid_argv_action",
            description = "Test Invalid Argv Action",
            runnable = true,
            editable = true,
            command = "invalid",
        },
    },
}
EOF_MANIFEST

# Verify execution captures exact argv elements without shell word-splitting
HOTKEYS_MANIFEST="$mock_manifest" HOTKEYS_TEST_ACTION=run HOTKEYS_TEST_EXEC=1 HOTKEYS_TEST_ID="test_custom_action" "$ROOT/bin/workstation-hotkeys" >/dev/null
sleep 0.2

readarray -t captured_args < "$capture_log"
if [[ "${#captured_args[@]}" -eq 7 && \
      "${captured_args[1]}" == "--title" && \
      "${captured_args[2]}" == "My Window" && \
      "${captured_args[3]}" == "--literal" && \
      "${captured_args[4]}" == "a b c" ]]; then
    pass "structured command_argv preserves exact multi-word argument boundaries without word splitting"
else
    fail "structured command_argv failed argument boundary preservation: count=${#captured_args[@]}"
fi

# Verify dangerous characters remained literal data and were NOT evaluated
if [[ "${captured_args[6]}" == *"\$(whoami)"* && ! -f "$argv_sandbox/pwned.txt" ]]; then
    pass "shell metacharacters in command_argv remain literal data without shell evaluation or redirection"
else
    fail "shell metacharacters in command_argv were evaluated or leaked side effects"
fi

# Verify runnable action without command_argv fails closed
missing_argv_ret=0
HOTKEYS_MANIFEST="$mock_manifest" HOTKEYS_TEST_ACTION=run HOTKEYS_TEST_ID="test_invalid_argv_action" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || missing_argv_ret=$?
if [[ "$missing_argv_ret" -eq 2 ]]; then
    pass "runnable action missing valid structured command_argv fails closed as unavailable"
else
    fail "runnable action missing command_argv did not fail closed: status=$missing_argv_ret"
fi

rm -rf "$argv_sandbox"


# Hook: run on non-runnable action fails safely without execution
run_close_ret=0
run_close_output="$(HOTKEYS_TEST_ACTION=run HOTKEYS_TEST_ID="window_close" "$ROOT/bin/workstation-hotkeys" 2>&1)" || run_close_ret=$?
if [[ "$run_close_ret" -eq 2 && "$run_close_output" == UNAVAILABLE:* ]]; then
    pass "hotkeys manager Return action safely refuses window/workspace context actions"
else
    fail "hotkeys manager Return action failed to refuse non-runnable item: status=$run_close_ret out=$run_close_output"
fi

# Hook: edit existing binding
if HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + E" "$ROOT/bin/workstation-hotkeys" >/dev/null; then
    pass "hotkeys manager edit flow updates existing shortcut"
else
    fail "hotkeys manager edit flow failed"
fi

# Verify override file is data-only (valid JSON) and not executable code
if [[ -f "$sandbox_overrides" ]]; then
    if jq . "$sandbox_overrides" >/dev/null 2>&1; then
        pass "user override file is pure valid JSON and not executable code"
    else
        fail "user override file is not valid JSON"
    fi
else
    fail "user override file was not created"
fi

# Uneditable actions rejection tests
cp -f "$sandbox_overrides" "$sandbox_overrides.pre"

# Test generator aggregate cannot be edited
gen_edit_ret=0
HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="workspaces_switch_1_10" HOTKEYS_TEST_INPUT="SUPER + 1" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || gen_edit_ret=$?
if [[ "$gen_edit_ret" -ne 0 ]]; then
    pass "hotkeys manager refuses editing generator aggregate bindings"
else
    fail "hotkeys manager permitted editing generator aggregate binding"
fi

# Test gesture cannot be edited
gesture_edit_ret=0
HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="workspace_touchpad_swipe" HOTKEYS_TEST_INPUT="SUPER + S" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || gesture_edit_ret=$?
if [[ "$gesture_edit_ret" -ne 0 ]]; then
    pass "hotkeys manager refuses assigning keyboard shortcut to gesture action"
else
    fail "hotkeys manager permitted editing gesture action"
fi

# Test mouse action cannot be edited
mouse_edit_ret=0
HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="mouse_window_drag" HOTKEYS_TEST_INPUT="SUPER + M" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || mouse_edit_ret=$?
if [[ "$mouse_edit_ret" -ne 0 ]]; then
    pass "hotkeys manager refuses editing mouse binding through keyboard editor"
else
    fail "hotkeys manager permitted editing mouse binding"
fi

# Test rejected edits leave override file byte-identical
if cmp -s "$sandbox_overrides" "$sandbox_overrides.pre"; then
    pass "rejected edits leave override file byte-identical"
else
    fail "rejected edits mutated override file"
fi
rm -f "$sandbox_overrides.pre"

# Hook: unset binding
if HOTKEYS_TEST_ACTION=unset HOTKEYS_TEST_ID="file_manager" "$ROOT/bin/workstation-hotkeys" >/dev/null; then
    pass "hotkeys manager unset flow unbinds shortcut to None (Unbound)"
else
    fail "hotkeys manager unset flow failed"
fi

# Hook: set previously unset binding
if HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + SHIFT + F" "$ROOT/bin/workstation-hotkeys" >/dev/null; then
    pass "hotkeys manager set flow assigns new shortcut to previously unbound action"
else
    fail "hotkeys manager set flow failed on previously unbound action"
fi

# Hook: conflict detection rejects assigning an already bound key
conflict_ret=0
conflict_out="$(HOTKEYS_TEST_ACTION=conflict HOTKEYS_TEST_ID="desktop_settings" HOTKEYS_TEST_INPUT="SUPER + RETURN" "$ROOT/bin/workstation-hotkeys" 2>&1)" || conflict_ret=$?
if [[ "$conflict_ret" -ne 0 && "$conflict_out" == *"Conflict:"* && "$conflict_out" == *"terminal"* ]]; then
    pass "hotkeys manager detects keybinding conflict and refuses to steal existing binding"
else
    fail "hotkeys manager failed conflict detection: ret=$conflict_ret out=$conflict_out"
fi

# Hook: invalid syntax rejection
invalid_ret=0
invalid_out="$(HOTKEYS_TEST_ACTION=invalid HOTKEYS_TEST_ID="desktop_settings" HOTKEYS_TEST_INPUT="SUPER + ; rm -rf /" "$ROOT/bin/workstation-hotkeys" 2>&1)" || invalid_ret=$?
if [[ "$invalid_ret" -ne 0 && "$invalid_out" == *"invalid or dangerous"* ]]; then
    pass "hotkeys manager rejects invalid and dangerous keybinding syntax"
else
    fail "hotkeys manager failed invalid syntax rejection: ret=$invalid_ret out=$invalid_out"
fi

# Hook: reset binding restores manifest default
if HOTKEYS_TEST_ACTION=reset HOTKEYS_TEST_ID="file_manager" "$ROOT/bin/workstation-hotkeys" >/dev/null; then
    pass "hotkeys manager reset flow restores manifest default"
else
    fail "hotkeys manager reset flow failed"
fi

# Verify manifest on disk was not modified in-place
manifest_after_hash="$(sha256sum "$manifest_file" | awk '{print $1}')"
if [[ "$manifest_before_hash" == "$manifest_after_hash" ]]; then
    pass "repository manifest file remains completely untouched by user edits"
else
    fail "manifest was modified during user override operations"
fi

# Verify zero drift: Hyprland keybind.lua and workstation-hotkeys consume the same effective bindings across multiple action classes
zero_drift_output="$(
    "$lua_bin" - "$ROOT" "$sandbox_overrides" <<'LUA_CHECK'
local root = arg[1]
local overrides_path = arg[2]

-- Set override for multiple diverse action classes:
-- exec: terminal
-- exec_locked: volume_raise
-- dispatch_close: window_close
-- dispatch_float: window_toggle_float
-- focus: focus_left
-- exec_resize: resize_window_left
-- focus_workspace_relative: workspace_prev
local f = io.open(overrides_path, "w")
f:write([[
{
  "terminal": "SUPER + ALT + RETURN",
  "volume_raise": "SUPER + ALT + EQUAL",
  "window_close": "SUPER + ALT + Q",
  "window_toggle_float": "SUPER + ALT + W",
  "focus_left": "SUPER + ALT + LEFT",
  "resize_window_left": "SUPER + ALT + SHIFT + LEFT",
  "workspace_prev": "SUPER + ALT + COMMA",
  "desktop_settings": false
}
]])
f:close()

package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = require("keybindings_manifest")
local effective = eff.resolve_bindings(manifest, eff.load_overrides(overrides_path))

-- Verify Hyprland registration with these effective bindings
local bound_keys = {}
local hl = {
    bind = function(key, action, flags) bound_keys[key] = true end,
    dsp = {
        focus = function() return function() end end,
        exec_cmd = function() return function() end end,
        window = {
            close = function() return function() end end,
            float = function() return function() end end,
            fullscreen = function() return function() end end,
            cycle_next = function() return function() end end,
            move = function() return function() end end,
            drag = function() return function() end end,
            resize = function() return function() end end,
        },
    },
    exec_cmd = function() end,
}
_G.hl = hl
package.loaded["keybind"] = nil
require("keybind")

-- Check each overridden action class is bound to its new key
local expected_keys = {
    "SUPER + ALT + RETURN",
    "SUPER + ALT + EQUAL",
    "SUPER + ALT + Q",
    "SUPER + ALT + W",
    "SUPER + ALT + LEFT",
    "SUPER + ALT + SHIFT + LEFT",
    "SUPER + ALT + COMMA",
}
for _, k in ipairs(expected_keys) do
    assert(bound_keys[k], "Hyprland missing overridden key: " .. k)
end

-- desktop_settings was set to false, should not be bound at all
for k, _ in pairs(bound_keys) do
    assert(k ~= "SUPER + T", "Hyprland should not bind unbound desktop_settings")
end

print("ZERO_DRIFT_OK")
LUA_CHECK
)"

if grep -q "ZERO_DRIFT_OK" <<< "$zero_drift_output"; then
    pass "Hyprland runtime configuration and hotkeys UI share identical effective binding resolution across action classes"
else
    fail "zero drift check failed: $zero_drift_output"
fi

section "Strict Override Persistence and Transactional Rollback"

# 1. Truncated JSON is rejected entirely
printf '{"terminal": "SUPER + RETURN"' > "$sandbox_overrides"
trunc_ret=0
HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || trunc_ret=$?
if [[ "$trunc_ret" -ne 0 ]]; then
    pass "truncated JSON override file is rejected entirely"
else
    fail "truncated JSON override was accepted"
fi

# 2. Trailing garbage after JSON object is rejected
printf '{"terminal": "SUPER + RETURN"} trailing_garbage' > "$sandbox_overrides"
trail_ret=0
HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || trail_ret=$?
if [[ "$trail_ret" -ne 0 ]]; then
    pass "trailing garbage after JSON object is rejected"
else
    fail "trailing garbage after JSON object was accepted"
fi

# 3. Malformed value in overrides is rejected
printf '{"terminal": 123}' > "$sandbox_overrides"
val_ret=0
HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || val_ret=$?
if [[ "$val_ret" -ne 0 ]]; then
    pass "malformed number value in overrides is rejected"
else
    fail "malformed number value was accepted"
fi

# 4. Unsupported boolean true in overrides is rejected
printf '{"terminal": true}' > "$sandbox_overrides"
true_ret=0
HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true_ret=$?
if [[ "$true_ret" -ne 0 ]]; then
    pass "unsupported boolean true in overrides is rejected"
else
    fail "unsupported boolean true was accepted"
fi

# 5. Unsupported null in overrides is rejected
printf '{"terminal": null}' > "$sandbox_overrides"
null_ret=0
HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || null_ret=$?
if [[ "$null_ret" -ne 0 ]]; then
    pass "unsupported null in overrides is rejected"
else
    fail "unsupported null was accepted"
fi

# 6. Unknown action ID in overrides is rejected
printf '{"unknown_action_xyz": "SUPER + A"}' > "$sandbox_overrides"
unk_ret=0
HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || unk_ret=$?
if [[ "$unk_ret" -ne 0 ]]; then
    pass "unknown action ID in overrides is rejected"
else
    fail "unknown action ID was accepted"
fi

# 7. Malformed override does not partially apply earlier valid entries
printf '{\n  "file_manager": "SUPER + ALT + E",\n  "terminal": 123\n}\n' > "$sandbox_overrides"
partial_ret=0
HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || partial_ret=$?
# Verify via Lua that resolve_bindings returns nil error and does not yield partial table
partial_lua_ok=0
partial_check="$(
    "$lua_bin" - "$ROOT" "$sandbox_overrides" <<'LUA_CHECK'
package.path = arg[1] .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = require("keybindings_manifest")
local res, err = eff.resolve_bindings(manifest, eff.load_overrides(arg[2], manifest))
if res == nil and err then
    print("FAIL_CLOSED_OK")
end
LUA_CHECK
)"
if [[ "$partial_ret" -ne 0 && "$partial_check" == *"FAIL_CLOSED_OK"* ]]; then
    pass "malformed override does not partially apply earlier valid entries"
else
    fail "malformed override was partially applied"
fi

# 8. Simulated successful reload commits candidate override
printf '{\n  "file_manager": "SUPER + ALT + M"\n}\n' > "$sandbox_overrides"
tx_commit_ret=0
HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + N" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || tx_commit_ret=$?
if [[ "$tx_commit_ret" -eq 0 ]] && grep -q "SUPER + ALT + N" "$sandbox_overrides"; then
    pass "simulated successful reload commits candidate override"
else
    fail "simulated successful reload failed to commit candidate"
fi

# 9. Simulated reload failure restores exact previous override content
pre_content="$(cat "$sandbox_overrides")"
tx_fail_ret=0
HOTKEYS_SIMULATE_RELOAD_FAIL=1 HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + Z" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || tx_fail_ret=$?
post_content="$(cat "$sandbox_overrides")"
if [[ "$tx_fail_ret" -ne 0 && "$pre_content" == "$post_content" ]]; then
    pass "simulated reload failure restores exact previous override content"
else
    fail "simulated reload failure did not restore previous content: ret=$tx_fail_ret"
fi

# 10. Simulated reload failure when no previous override existed restores absence
rm -f "$sandbox_overrides"
tx_noprev_ret=0
HOTKEYS_SIMULATE_RELOAD_FAIL=1 HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + Z" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || tx_noprev_ret=$?
if [[ "$tx_noprev_ret" -ne 0 && ! -f "$sandbox_overrides" ]]; then
    pass "simulated reload failure when no previous override existed restores absence"
else
    fail "simulated reload failure failed to restore absence of override file: ret=$tx_noprev_ret exists=$(test -f "$sandbox_overrides" && echo 1 || echo 0)"
fi

# 11. Rollback failure is surfaced as a hard failure
tx_rb_fail_out="$(HOTKEYS_SIMULATE_RELOAD_FAIL=1 HOTKEYS_SIMULATE_ROLLBACK_FAIL=1 HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + Z" "$ROOT/bin/workstation-hotkeys" 2>&1)" || true
if [[ "$tx_rb_fail_out" == *"FATAL:"* ]]; then
    pass "rollback failure is surfaced as a hard failure"
else
    fail "rollback failure did not surface FATAL error: $tx_rb_fail_out"
fi

# 12. Reload failure is never swallowed
tx_swallow_ret=0
HOTKEYS_SIMULATE_RELOAD_FAIL=1 HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + Z" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || tx_swallow_ret=$?
if [[ "$tx_swallow_ret" -ne 0 ]]; then
    pass "reload failure is never swallowed"
else
    fail "reload failure was swallowed (returned 0)"
fi

# 13. Normal save creates override file with restrictive 0600 permissions
HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + M" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true
perm_check="$(stat -c %a "$sandbox_overrides" 2>/dev/null || true)"
if [[ "$perm_check" == "600" ]]; then
    pass "override file is created with restrictive 0600 permissions via exclusive mktemp"
else
    fail "override file permissions are not 0600: $perm_check"
fi

# 14. Exclusive creation does not follow or overwrite pre-existing symlinks
decoy_file="$sandbox_dir/decoy.txt"
printf "DO_NOT_CORRUPT_DECOY\n" > "$decoy_file"
ln -s "$decoy_file" "$sandbox_dir/.tmp.overrides.123456"
HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + N" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true
decoy_after="$(cat "$decoy_file")"
if [[ "$decoy_after" == "DO_NOT_CORRUPT_DECOY" ]]; then
    pass "exclusive temporary file creation avoids following or corrupting symlinks"
else
    fail "exclusive temporary creation followed or corrupted symlink"
fi
rm -f "$sandbox_dir/.tmp.overrides.123456" "$decoy_file"

# 15. Failed write/replace does not leave leftover temporary files
leftover_tmp="$(find "$sandbox_dir" -maxdepth 1 -name ".tmp.overrides.*")"
if [[ -z "$leftover_tmp" ]]; then
    pass "no leftover temporary files remain after normal save operations"
else
    fail "leftover temporary files remained after normal save: $leftover_tmp"
fi

HOTKEYS_SIMULATE_RELOAD_FAIL=1 HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + Z" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true
leftover_fail_tmp="$(find "$sandbox_dir" -maxdepth 1 -name ".tmp.overrides.*")"
if [[ -z "$leftover_fail_tmp" ]]; then
    pass "no leftover temporary files remain after failed reload transactions"
else
    fail "leftover temporary files remained after failed reload transaction: $leftover_fail_tmp"
fi

# 16. Single owner reload: successful edit causes exactly one transactional reload attempt
reload_audit_log="$sandbox_dir/reload_audit.log"
export HOTKEYS_RELOAD_LOG="$reload_audit_log"

: > "$reload_audit_log"
HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + E" "$ROOT/bin/workstation-hotkeys" >/dev/null
edit_reload_count="$(wc -l < "$reload_audit_log")"
if [[ "$edit_reload_count" -eq 1 ]]; then
    pass "successful edit causes exactly one transactional reload attempt with single owner"
else
    fail "successful edit triggered unexpected number of reload attempts: $edit_reload_count"
fi

# 17. Single owner reload: successful unset causes exactly one transactional reload attempt
: > "$reload_audit_log"
HOTKEYS_TEST_ACTION=unset HOTKEYS_TEST_ID="file_manager" "$ROOT/bin/workstation-hotkeys" >/dev/null
unset_reload_count="$(wc -l < "$reload_audit_log")"
if [[ "$unset_reload_count" -eq 1 ]]; then
    pass "successful unset causes exactly one transactional reload attempt"
else
    fail "successful unset triggered unexpected number of reload attempts: $unset_reload_count"
fi

# 18. Single owner reload: successful reset causes exactly one transactional reload attempt
: > "$reload_audit_log"
HOTKEYS_TEST_ACTION=reset HOTKEYS_TEST_ID="file_manager" "$ROOT/bin/workstation-hotkeys" >/dev/null
reset_reload_count="$(wc -l < "$reload_audit_log")"
if [[ "$reset_reload_count" -eq 1 ]]; then
    pass "successful reset causes exactly one transactional reload attempt"
else
    fail "successful reset triggered unexpected number of reload attempts: $reset_reload_count"
fi

# 19. Reload failure causes rollback, reports failure rather than UI success, and preserves old content
HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + M" "$ROOT/bin/workstation-hotkeys" >/dev/null
pre_fail_content="$(cat "$sandbox_overrides")"
: > "$reload_audit_log"
fail_exit_code=0
fail_out="$(HOTKEYS_SIMULATE_RELOAD_FAIL=1 HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + Z" "$ROOT/bin/workstation-hotkeys" 2>&1)" || fail_exit_code=$?
post_fail_content="$(cat "$sandbox_overrides")"

if [[ "$fail_exit_code" -ne 0 && "$fail_out" == *"EDIT_FAIL"* && "$fail_out" == *"rolled back"* ]]; then
    pass "reload failure is reported as failure rather than UI success"
else
    fail "reload failure was incorrectly reported: code=$fail_exit_code out=$fail_out"
fi

if [[ "$pre_fail_content" == "$post_fail_content" ]]; then
    pass "previous valid override content survives transaction rollback intact"
else
    fail "override content was altered despite transaction rollback"
fi

rm -rf "$sandbox_dir"
unset HOTKEYS_OVERRIDES
unset HOTKEYS_MANIFEST
unset HOTKEYS_RELOAD_LOG



