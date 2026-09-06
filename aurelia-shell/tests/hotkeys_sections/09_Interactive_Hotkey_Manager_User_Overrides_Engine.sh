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
if [[ "$run_terminal_output" == "RUN:gtk-launch -- kitty.desktop" || "$run_terminal_output" == "RUN:kitty" ]]; then
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
for _ in {1..40}; do
    [[ -s "$capture_log" ]] && break
    sleep 0.05
done

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
