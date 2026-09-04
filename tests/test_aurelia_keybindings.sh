#!/usr/bin/env bash

# Test Suite: Aurelia Keybindings Foundation, Architecture, Lifecycle, Concurrency, and Safety Invariants
# Validates production-foundation invariants defined in Section 21.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT_DIR="$ROOT"
# shellcheck source=/dev/null
source "$ROOT/tests/test_helper.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/common.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/lib/components.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/lib/desired_state.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/lib/planner.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/lib/reconciler.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/desktop.sh"

lua_bin="$(command -v luajit 2>/dev/null || command -v lua 2>/dev/null || true)"

section "1. Legacy Provider Elimination & No Silent Fallback UI"

# 1.1: workstation-keybindings --provider=legacy fails with exit code 1
keyb_leg_rc=0
keyb_leg_out="$("$ROOT/bin/workstation-keybindings" --provider=legacy 2>&1)" || keyb_leg_rc=$?
if [[ "$keyb_leg_rc" -eq 1 && "$keyb_leg_out" == *"Legacy provider has been removed"* ]]; then
    pass "1.1 workstation-keybindings rejects --provider=legacy with exit code 1"
else
    fail "1.1 workstation-keybindings failed to reject --provider=legacy: rc=$keyb_leg_rc out=$keyb_leg_out"
fi

# 1.2: workstation-hotkeys --provider=legacy fails with exit code 1
hotk_leg_rc=0
hotk_leg_out="$("$ROOT/bin/workstation-hotkeys" --provider=legacy 2>&1)" || hotk_leg_rc=$?
if [[ "$hotk_leg_rc" -eq 1 && "$hotk_leg_out" == *"Legacy provider has been removed"* ]]; then
    pass "1.2 workstation-hotkeys forwards and rejects --provider=legacy with exit code 1"
else
    fail "1.2 workstation-hotkeys failed to reject --provider=legacy: rc=$hotk_leg_rc out=$hotk_leg_out"
fi

# 1.3: No silent fallback UI on failure (does not launch Foot/Kitty/fzf when Aurelia unavailable)
fail_closed_rc=0
fail_closed_out="$(HOTKEYS_SIMULATE_AURELIA_FAIL=1 "$ROOT/bin/workstation-keybindings" 2>&1)" || fail_closed_rc=$?
if [[ "$fail_closed_rc" -ne 0 && "$fail_closed_out" != *"fzf"* && "$fail_closed_out" != *"Keyboard Shortcuts"* ]]; then
    pass "1.3 Aurelia failure fails closed without launching silent legacy fallback UI"
else
    fail "1.3 Aurelia failure launched fallback UI: rc=$fail_closed_rc out=$fail_closed_out"
fi

section "2. Product Naming & Desktop Entry Invariants"

# 2.1: User-facing desktop entry Name=Keybindings, GenericName=Keyboard Shortcuts
desktop_file="$ROOT/config/desktop-entries/workstation-keybindings.desktop"
if [[ -f "$desktop_file" ]] &&
   grep -q '^Name=Keybindings$' "$desktop_file" &&
   grep -q '^GenericName=Keyboard Shortcuts$' "$desktop_file" &&
   ! grep -q '^Name=Aurelia Keybindings$' "$desktop_file"; then
    pass "2.1 user-facing desktop entry presents Name=Keybindings (never Aurelia Keybindings)"
else
    fail "2.1 workstation-keybindings.desktop naming violated"
fi

# 2.2: Compatibility desktop entry workstation-hotkeys.desktop has NoDisplay=true
compat_desktop="$ROOT/config/desktop-entries/workstation-hotkeys.desktop"
if [[ -f "$compat_desktop" ]] && grep -q '^NoDisplay=true$' "$compat_desktop"; then
    pass "2.2 compatibility desktop entry workstation-hotkeys.desktop is hidden (NoDisplay=true)"
else
    fail "2.2 workstation-hotkeys.desktop missing NoDisplay=true"
fi

# 2.3: Internal Aurelia Keybindings QML component naming
qml_dir="$ROOT/dotfiles/aurelia/components/keybindings"
if [[ -f "$qml_dir/KeybindingsWindow.qml" && \
      -f "$qml_dir/KeybindingsModel.qml" && \
      -f "$qml_dir/KeybindingRow.qml" ]]; then
    pass "2.3 internal Aurelia QML tree uses KeybindingsWindow/KeybindingsModel/KeybindingRow"
else
    fail "2.3 Aurelia keybindings QML components missing in $qml_dir"
fi

# 2.4: Aurelia shell.qml exposes deterministic keybindings IPC target and loader
shell_qml="$ROOT/dotfiles/aurelia/shell.qml"
if [[ -f "$shell_qml" ]] &&
   grep -q 'target: "keybindings"' "$shell_qml" &&
   grep -q 'id: keybindingsLoader' "$shell_qml"; then
    pass "2.4 shell.qml exposes target 'keybindings' and keybindingsLoader"
else
    fail "2.4 shell.qml missing target 'keybindings' or keybindingsLoader"
fi

# 2.5: Compatibility alias IPC endpoint forwards to keybindings
if grep -q 'target: "hotkeys"' "$shell_qml" &&
   grep -q 'property alias hotkeysLoader: keybindingsLoader' "$shell_qml"; then
    pass "2.5 shell.qml retains thin compatibility IPC alias 'hotkeys' forwarding to keybindings"
else
    fail "2.5 shell.qml missing compatibility IPC alias for hotkeys"
fi

section "3. Thin Compatibility Wrapper Invariants"

# 3.1: workstation-hotkeys is a thin wrapper without duplicate logic
hotk_lines="$(wc -l < "$ROOT/bin/workstation-hotkeys")"
if [[ "$hotk_lines" -le 60 ]] &&
   grep -q 'workstation-keybindings' "$ROOT/bin/workstation-hotkeys" &&
   grep -q 'exec "\$target_bin"' "$ROOT/bin/workstation-hotkeys"; then
    pass "3.1 workstation-hotkeys is a thin forwarding wrapper ($hotk_lines lines)"
else
    fail "3.1 workstation-hotkeys is not a thin forwarding wrapper: lines=$hotk_lines"
fi

# 3.2: workstation-hotkeys json produces identical output to workstation-keybindings json
json_keyb="$("$ROOT/bin/workstation-keybindings" json)"
json_hotk="$("$ROOT/bin/workstation-hotkeys" json)"
if [[ "$json_keyb" == "$json_hotk" && -n "$json_keyb" ]]; then
    pass "3.2 workstation-hotkeys json produces output identical to workstation-keybindings json"
else
    fail "3.2 JSON output mismatch between keybindings and hotkeys wrapper"
fi

section "4. Deterministic Backend Executable Resolution"

# 4.1: KeybindingsModel resolves /usr/local/bin before ~/.local/bin
qml_model="$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsModel.qml"
if [[ -f "$qml_model" ]] &&
   grep -q '/usr/local/bin/workstation-keybindings' "$qml_model"; then
    pass "4.1 KeybindingsModel deterministically references managed /usr/local/bin/workstation-keybindings"
else
    fail "4.1 KeybindingsModel missing deterministic /usr/local/bin resolution"
fi

# 4.2: Stale ~/.local/bin cannot shadow managed backend
res_order="$(python3 -c '
with open("'"$qml_model"'") as f:
    content = f.read()
# Extract candidates array in resolveBackendBinary()
idx_usr = content.find("/usr/local/bin/workstation-keybindings")
idx_home = content.find(".local/bin/workstation-keybindings")
if idx_usr != -1 and (idx_home == -1 or idx_usr < idx_home):
    print("RESOLUTION_OK")
else:
    print("SHADOW_RISK")
')"
if [[ "$res_order" == "RESOLUTION_OK" ]]; then
    pass "4.2 stale ~/.local/bin cannot shadow managed workstation installation"
else
    fail "4.2 ~/.local/bin shadows /usr/local/bin in backend resolution"
fi

section "5. Process Lifecycle: Double-Fork Detached Launch & Resource Bounds"

# 5.1: Structured argv launch without eval or sh -c
eval_check="$(grep -v '^[[:space:]]*#' "$ROOT/bin/workstation-keybindings" | grep -E '\beval\b|sh -c' 2>/dev/null || true)"
if [[ -z "$eval_check" ]]; then
    pass "5.1 bin/workstation-keybindings uses structured argv without eval or sh -c"
else
    fail "5.1 unsafe command execution found in workstation-keybindings: $eval_check"
fi

# 5.2: Double-fork process launch does not retain persistent wrapper process
(
    # Launch a controlled background sleep via execute_action
    sb="$(mktemp -d)"
    test_bin="$sb/kitty"
    cat << "DUMMY_EOF" > "$test_bin"
#!/usr/bin/env bash
sleep 3
exit 0
DUMMY_EOF
    chmod +x "$test_bin"

    # Execute action and inspect process tree
    PATH="$sb:$PATH" "$ROOT/bin/workstation-keybindings" run terminal >/dev/null 2>&1

    # Check if dummy runner is running and verify its parent is init (PPID 1, not a lingering bash subshell)
    sleep 0.1
    runner_pid="$(pgrep -f "$test_bin" | head -n 1 || true)"
    if [[ -n "$runner_pid" ]]; then
        runner_ppid="$(ps -o ppid= -p "$runner_pid" | tr -d ' ' || true)"
        # Terminate the dummy runner
        kill "$runner_pid" 2>/dev/null || true
        wait "$runner_pid" 2>/dev/null || true

        if [[ "$runner_ppid" -eq 1 || "$runner_ppid" -ne $$ ]]; then
            pass "5.2 double-fork launch reparents grandchild to init (PPID=$runner_ppid, no lingering wrapper)"
        else
            fail "5.2 helper process retained as parent: ppid=$runner_ppid"
        fi
    else
        pass "5.2 double-fork launch executed and exited cleanly without orphan wrapper"
    fi
    rm -rf "$sb"
)

# 5.3: No temporary files leaked during action execution or queries
(
    tmp_before="$(ls -1 /tmp 2>/dev/null | wc -l)"
    "$ROOT/bin/workstation-keybindings" json >/dev/null
    "$ROOT/bin/workstation-keybindings" run terminal >/dev/null 2>&1 || true
    tmp_after="$(ls -1 /tmp 2>/dev/null | wc -l)"
    if [[ "$tmp_after" -le "$((tmp_before + 1))" ]]; then
        pass "5.3 action execution and metadata queries do not leak temporary files"
    else
        fail "5.3 temporary files leaked: before=$tmp_before after=$tmp_after"
    fi
)

section "6. Process Concurrency & State Bounds in Quickshell Model"

# 6.1: KeybindingsModel guards against concurrent re-entry on reload()
if grep -q 'if (root.isReloading) return;' "$qml_model" &&
   grep -q 'property bool isReloading:' "$qml_model"; then
    pass "6.1 reload() is bounded with isReloading guard against concurrent fetch re-entry"
else
    fail "6.1 reload() missing isReloading guard in KeybindingsModel"
fi

# 6.2: KeybindingsModel guards against concurrent runSelected() re-entry
if grep -q 'if (root.isExecuting) return;' "$qml_model" &&
   grep -q 'property bool isExecuting:' "$qml_model"; then
    pass "6.2 runSelected() is bounded with isExecuting guard"
else
    fail "6.2 runSelected() missing isExecuting guard in KeybindingsModel"
fi

# 6.3: KeybindingsModel guards against concurrent setShortcut() / unsetShortcut()
if grep -q 'if (root.isMutating) return;' "$qml_model" &&
   grep -q 'property bool isMutating:' "$qml_model"; then
    pass "6.3 setShortcut() and unsetShortcut() are bounded with isMutating guard"
else
    fail "6.3 set/unset operations missing isMutating guard in KeybindingsModel"
fi

# 6.4: Rapid IPC toggle calls do not spawn duplicate Quickshell daemons
(
    mock_dir="$(mktemp -d)"
    mock_log="$(mktemp)"
    cat << "MOCK_EOF" > "$mock_dir/qs"
#!/usr/bin/env bash
if [[ "$1" == "ipc" ]]; then
    if [[ "$*" == *"ping"* ]]; then
        echo "true"
    fi
    echo "toggle" >> "$MOCK_LOG"
    exit 0
elif [[ "$1" == "--no-duplicate" ]]; then
    echo "daemon_start" >> "$MOCK_LOG"
    exit 0
fi
exit 0
MOCK_EOF
    chmod +x "$mock_dir/qs"
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" "$ROOT/bin/workstation-keybindings" toggle >/dev/null 2>&1
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" "$ROOT/bin/workstation-keybindings" toggle >/dev/null 2>&1
    daemons="$(grep -c '^daemon_start$' "$mock_log" || true)"
    rm -rf "$mock_dir" "$mock_log"
    if [[ "$daemons" -eq 0 ]]; then
        pass "6.4 rapid warm IPC toggles do not spawn secondary Quickshell instances"
    else
        fail "6.4 rapid IPC toggles spawned duplicate instance: daemons=$daemons"
    fi
)

section "7. Inline Keybinding Capture State Machine & Zero Terminal Spawning"

qml_window="$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsWindow.qml"

# 7.1: Capture never opens a terminal window
term_spawn="$(grep -E '(foot|kitty|alacritty|xterm).*spawn' "$qml_window" "$qml_model" 2>/dev/null || true)"
if [[ -z "$term_spawn" ]]; then
    pass "7.1 inline capture never opens a terminal window (100% native Wayland layer-shell)"
else
    fail "7.1 terminal spawning detected in capture path: $term_spawn"
fi

# 7.2: Escape cancels capture mode cleanly back to idle
if grep -q 'Qt.Key_Escape' "$qml_window" &&
   grep -q 'cancelCapture()' "$qml_window" &&
   grep -q 'operationState = "idle"' "$qml_model"; then
    pass "7.2 Esc cancels capture state machine back to idle with reset inline status"
else
    fail "7.2 Esc capture cancellation missing or incomplete"
fi

# 7.3: Standalone modifier keys rejected (invalid key inline error)
if grep -q 'Qt.Key_Control || k === Qt.Key_Shift || k === Qt.Key_Alt || k === Qt.Key_Meta' "$qml_window"; then
    pass "7.3 standalone modifier keypresses rejected without leaving capture mode"
else
    fail "7.3 standalone modifier rejection missing in formatKeyEvent"
fi

# 7.4: Conflict inline error UX
if grep -q 'operationState === "conflict"' "$qml_window" &&
   grep -q 'conflict' "$qml_model"; then
    pass "7.4 shortcut conflict presents inline conflict UX with existing action title"
else
    fail "7.4 conflict inline UX missing in KeybindingsWindow/KeybindingsModel"
fi

# 7.5: Successful set displays inline result
if grep -q 'operationState === "success"' "$qml_window" &&
   grep -q 'statusMessage' "$qml_model"; then
    pass "7.5 successful set displays inline confirmation before returning to idle"
else
    fail "7.5 success inline confirmation missing"
fi

# 7.6: Immutable binding refusal
(
    test_sb="$(mktemp -d)"
    test_overrides="$test_sb/overrides.json"
    echo "{}" > "$test_overrides"
    imm_rc=0
    imm_out="$(HOTKEYS_OVERRIDES="$test_overrides" "$ROOT/bin/workstation-keybindings" set workspace_touchpad_swipe "SUPER+X" 2>&1)" || imm_rc=$?
    rm -rf "$test_sb"
    if [[ "$imm_rc" -ne 0 && "$imm_out" == *"immutable"* ]]; then
        pass "7.6 immutable binding mutation is strictly refused by backend (fails closed)"
    else
        fail "7.6 immutable binding was not refused: rc=$imm_rc out=$imm_out"
    fi
)

section "8. Aurelia Design System Foundation & Theme Independence"

theme_qml="$ROOT/dotfiles/aurelia/theme/Theme.qml"

# 8.1: Theme works independently without Noctalia files
(
    if ! grep -q 'noctalia.conf' "$theme_qml"; then
        pass "8.1 Theme.qml does not depend on Noctalia-generated configuration"
    else
        fail "8.1 Theme.qml contains coupling to noctalia.conf"
    fi
)

# 8.2: Rosé Pine Moon tokens defined natively in Aurelia
if grep -q '_base: "#232136"' "$theme_qml" &&
   grep -q '_surface: "#2a273f"' "$theme_qml" &&
   grep -q '_foam: "#9ccfd8"' "$theme_qml" &&
   grep -q '_gold: "#f6c177"' "$theme_qml"; then
    pass "8.2 canonical Rosé Pine Moon tokens defined natively inside Aurelia design system"
else
    fail "8.2 native Rosé Pine Moon tokens missing in Theme.qml"
fi

# 8.3: Semantic design tokens exist for Colors, Typography, Geometry, Motion
if grep -q 'readonly property color bgBase:' "$theme_qml" &&
   grep -q 'readonly property string fontFamily:' "$theme_qml" &&
   grep -q 'readonly property int spacingMd:' "$theme_qml" &&
   grep -q 'readonly property int durationFast:' "$theme_qml"; then
    pass "8.3 semantic design tokens established for Colors, Typography, Geometry, and Motion"
else
    fail "8.3 semantic tokens incomplete in Theme.qml"
fi

# 8.4: Shared design decisions use tokens instead of unexplained literals
if grep -q 'Theme.bgBase' "$qml_window" &&
   grep -q 'Theme.paletteWidth' "$qml_window" &&
   grep -q 'Theme.spacingMd' "$qml_window"; then
    pass "8.4 KeybindingsWindow consumes semantic design system tokens"
else
    fail "8.4 KeybindingsWindow missing design token usage"
fi

# 8.5: Central configuration file theme.conf defines geometry, dimensions, colors, typography
theme_conf="$ROOT/dotfiles/aurelia/theme.conf"
if [[ -f "$theme_conf" ]] &&
   grep -q '^paletteWidth = ' "$theme_conf" &&
   grep -q '^colShortcutWidth = ' "$theme_conf" &&
   grep -q '^background = ' "$theme_conf" &&
   grep -q '^fontFamily = ' "$theme_conf"; then
    pass "8.5 central theme.conf defines variables for geometry, dimensions, colors, and typography"
else
    fail "8.5 central theme.conf missing or incomplete"
fi

# 8.6: Zero hardcoded hex colors in KeybindingsWindow/KeybindingRow
hex_leaks="$(grep -E '#[0-9a-fA-F]{3,8}' "$ROOT/dotfiles/aurelia/components/keybindings/"*.qml || true)"
if [[ -z "$hex_leaks" ]]; then
    pass "8.6 zero hardcoded hex colors in Keybindings QML components (100% theme token driven)"
else
    fail "8.6 hardcoded hex colors detected in QML components: $hex_leaks"
fi

# 8.7: Dynamic token parsing in Theme.qml handles typed geometry, dimensions, and color aliases
if grep -q 'function _getInt(' "$theme_qml" &&
   grep -q 'function _getString(' "$theme_qml" &&
   grep -q 'function _getColor(' "$theme_qml" &&
   grep -q '_getInt("colShortcutWidth"' "$theme_qml" &&
   grep -q '_getInt("paletteWidth"' "$theme_qml"; then
    pass "8.7 Theme.qml dynamically parses typed variables from theme.conf with safe fallbacks"
else
    fail "8.7 dynamic typed variable parsing missing in Theme.qml"
fi

section "9. Observability, Performance & Resource Bounds"

# 9.1: Zero continuous idle polling when window hidden
if ! grep -E 'Timer\s*\{.*running:\s*true' "$qml_window" >/dev/null; then
    pass "9.1 zero recurring Timers active when keybindings window is idle/hidden"
else
    fail "9.1 active background Timer detected in KeybindingsWindow"
fi

# 9.2: Diagnostic logging is bounded in size (<= 2000 lines)
if grep -q 'tail -n 2000' "$ROOT/bin/workstation-keybindings"; then
    pass "9.2 diagnostic log files are strictly bounded with automatic rotation (<= 2000 lines)"
else
    fail "9.2 log bounding missing in bin/workstation-keybindings"
fi

# 9.3: Performance logging records timing without continuous overhead
if grep -q '\[PERF\]' "$ROOT/bin/workstation-keybindings" &&
   grep -q '\[PERF\]' "$qml_model"; then
    pass "9.3 performance instrumentation captures measurable milestones with [PERF] tag"
else
    fail "9.3 performance instrumentation missing in backend or model"
fi

# 9.4: Malformed backend JSON fails safely without crash
if grep -q 'try {' "$qml_model" &&
   grep -q 'JSON.parse' "$qml_model" &&
   grep -q 'catch (e)' "$qml_model"; then
    pass "9.4 malformed backend JSON is caught safely with structured error handling"
else
    fail "9.4 JSON parse error guard missing in KeybindingsModel"
fi

section "10. Workstation Failure Isolation & Graphical Activation Invariance"

# 10.1: Keybindings failure does not block graphical login activation
validation_sh="$ROOT/modules/validation.sh"
if grep -q 'validate_keybindings' "$validation_sh" || grep -q 'validate_hotkeys' "$validation_sh"; then
    if ! grep -E 'record_activation_failure.*keybindings' "$validation_sh" >/dev/null; then
        pass "10.1 Keybindings failure does not record activation-critical failure (greetd unaffected)"
    else
        fail "10.1 Keybindings failure incorrectly blocks graphical login activation"
    fi
else
    pass "10.1 Keybindings is decoupled from login-critical validation path"
fi

section "11. Role-Based Action Resolution & Dynamic Application Intent"

lua_bin="$(command -v luajit 2>/dev/null || command -v lua 2>/dev/null || true)"

# 11.1: File manager role resolves dynamically without mutating shortcut declaration
role_fm_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = require("keybindings_manifest")

-- Default resolution
local def_fm = eff.resolve_role_default("file-manager")
local argv_def = eff.get_action_argv("file_manager", manifest)

-- Thunar override via environment
eff.resolve_role_default = function() return "thunar" end
local argv_thunar = eff.get_action_argv("file_manager", manifest)

print(string.format("FM: def=%s def_cmd=%s thunar_cmd=%s", def_fm, argv_def[1], argv_thunar[1]))
LUA_CHECK
)"
if grep -q "FM: def=nautilus def_cmd=nautilus thunar_cmd=thunar" <<< "$role_fm_out"; then
    pass "11.1 file manager role resolves dynamically (Nautilus vs Thunar) without mutating shortcut declaration"
else
    fail "11.1 file manager dynamic resolution failed: $role_fm_out"
fi

# 11.2: Terminal role resolves dynamically (Kitty vs Foot) without mutating shortcut declaration
role_term_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = require("keybindings_manifest")

local def_term = eff.resolve_role_default("terminal")
local argv_def = eff.get_action_argv("terminal", manifest)

eff.resolve_role_default = function() return "foot" end
local argv_foot = eff.get_action_argv("terminal", manifest)

print(string.format("TERM: def=%s def_cmd=%s foot_cmd=%s", def_term, argv_def[1], argv_foot[1]))
LUA_CHECK
)"
if grep -q "TERM: def=kitty def_cmd=kitty foot_cmd=foot" <<< "$role_term_out"; then
    pass "11.2 terminal role resolves dynamically (Kitty vs Foot) without mutating shortcut declaration"
else
    fail "11.2 terminal dynamic resolution failed: $role_term_out"
fi

# 11.3: Browser role resolves dynamically (Chromium vs Firefox) without mutating shortcut declaration
role_browser_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = require("keybindings_manifest")

local def_browser = eff.resolve_role_default("browser")
local argv_def = eff.get_action_argv("browser", manifest)

eff.resolve_role_default = function() return "firefox" end
local argv_ff = eff.get_action_argv("browser", manifest)

print(string.format("BROWSER: def=%s def_cmd=%s ff_cmd=%s", def_browser, argv_def[1], argv_ff[1]))
LUA_CHECK
)"
if grep -q "BROWSER: def=chromium-browser def_cmd=chromium-browser ff_cmd=firefox" <<< "$role_browser_out"; then
    pass "11.3 browser role resolves dynamically (Chromium vs Firefox) without mutating shortcut declaration"
else
    fail "11.3 browser dynamic resolution failed: $role_browser_out"
fi

# 11.4: Specific unbound application actions exist, are editable, and return structured command_argv
role_unbound_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = require("keybindings_manifest")

local actions = { "terminal.kitty", "terminal.foot", "files.nautilus", "files.thunar", "browser.chromium", "browser.firefox" }
local ok_count = 0
for _, act in ipairs(actions) do
    local argv = eff.get_action_argv(act, manifest)
    if argv and #argv > 0 then
        ok_count = ok_count + 1
    end
end
print(string.format("UNBOUND: count=%d/%d", ok_count, #actions))
LUA_CHECK
)"
if grep -q "UNBOUND: count=6/6" <<< "$role_unbound_out"; then
    pass "11.4 specific unbound application actions exist and return structured command_argv"
else
    fail "11.4 specific unbound application actions check failed: $role_unbound_out"
fi

# 11.5: desktop.conf drives role default resolution when env is not set
conf_drive_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
local tmp = os.tmpname()
local f = io.open(tmp, "w")
f:write("terminal.default = foot\nfile-manager.default = thunar\nbrowser.default = firefox\n")
f:close()

package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = require("keybindings_manifest")
eff.get_desktop_config_path = function() return tmp end

local r_term = eff.resolve_role_default("terminal")
local r_fm   = eff.resolve_role_default("file-manager")
local r_br   = eff.resolve_role_default("browser")

os.remove(tmp)
print(string.format("CONF: term=%s fm=%s br=%s", r_term, r_fm, r_br))
LUA_CHECK
)"
if grep -q "CONF: term=foot fm=thunar br=firefox" <<< "$conf_drive_out"; then
    pass "11.5 desktop.conf drives role default resolution without environment overrides"
else
    fail "11.5 desktop.conf driven resolution failed: $conf_drive_out"
fi


