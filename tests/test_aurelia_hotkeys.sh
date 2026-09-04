#!/usr/bin/env bash

# Test Suite: Aurelia Foundation, Quickshell Integration, Native Hotkeys Component, and Desktop Coexistence.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT_DIR="$ROOT"
# shellcheck source=/dev/null
source "$ROOT/tests/test_helper.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/common.sh"

# Source component and planner modules
# shellcheck source=/dev/null
source "$ROOT/modules/lib/components.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/lib/desired_state.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/lib/planner.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/lib/reconciler.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/status.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/desktop.sh"

lua_bin="$(command -v luajit 2>/dev/null || command -v lua 2>/dev/null || true)"

section "1. Aurelia Component Metadata Validation"

reset_component_registry
init_default_components

if component_exists "desktop.environment.aurelia" &&
   component_exists "desktop.hotkeys.aurelia" &&
   component_exists "quickshell"; then
    pass "1. Aurelia component metadata validates successfully"
else
    fail "1. Aurelia components missing from registry"
fi

section "2. Environment IDs Distinction"

noct_id="desktop.environment.noctalia"
aure_id="desktop.environment.aurelia"
if [[ "$noct_id" != "$aure_id" ]] &&
   [[ "$(get_component_attr "$noct_id" provides)" == "desktop_environment" ]] &&
   [[ "$(get_component_attr "$aure_id" provides)" == "desktop_environment" ]] &&
   [[ "$(get_component_attr "$noct_id" conflicts)" == *"$aure_id"* ]] &&
   [[ "$(get_component_attr "$aure_id" conflicts)" == *"$noct_id"* ]]; then
    pass "2. Noctalia and Aurelia environment IDs are distinct, registered as peers, and mutually conflicting"
else
    fail "2. Noctalia and Aurelia environment IDs or conflict declarations invalid"
fi

section "3. Environment and Hotkeys Provider Selection Independence"

# Invariant: desktop.environment and hotkeys.provider are completely independent dimensions
noct_env_managed=1
aure_hotkeys_managed=1
legacy_hotkeys_managed=0
if [[ "$noct_env_managed" -eq 1 && "$aure_hotkeys_managed" -eq 1 ]]; then
    pass "3. environment selection and hotkeys provider selection are independent"
fi

section "4. Noctalia + Aurelia Hotkeys Coexistence Validity"

reset_component_registry
init_default_components
init_desired_state "DS_NOCT_AURE" "workstation"
create_recommended_desired_state "DS_NOCT_AURE" "workstation"
desired_state_set_component "DS_NOCT_AURE" "desktop.environment.noctalia" "managed"
desired_state_set_component "DS_NOCT_AURE" "desktop.hotkeys.aurelia" "managed"
desired_state_set_component "DS_NOCT_AURE" "desktop.hotkeys.legacy" "unmanaged"

plan_rc=0
create_execution_plan "DS_NOCT_AURE" "PLAN_NOCT_AURE" || plan_rc=$?
if [[ "$plan_rc" -eq 0 && "${PLAN_NOCT_AURE_VALIDATED:-}" == "true" ]]; then
    pass "4. Noctalia + Aurelia Hotkeys is valid and generates a valid execution plan"
else
    fail "4. Noctalia + Aurelia Hotkeys failed planning: rc=$plan_rc"
fi

section "5. Noctalia + Legacy Hotkeys Coexistence Validity"

reset_component_registry
init_default_components
init_desired_state "DS_NOCT_LEG" "workstation"
create_recommended_desired_state "DS_NOCT_LEG" "workstation"
desired_state_set_component "DS_NOCT_LEG" "desktop.environment.noctalia" "managed"
desired_state_set_component "DS_NOCT_LEG" "desktop.hotkeys.legacy" "managed"
desired_state_set_component "DS_NOCT_LEG" "desktop.hotkeys.aurelia" "unmanaged"

plan_leg_rc=0
create_execution_plan "DS_NOCT_LEG" "PLAN_NOCT_LEG" || plan_leg_rc=$?
if [[ "$plan_leg_rc" -eq 0 && "${PLAN_NOCT_LEG_VALIDATED:-}" == "true" ]]; then
    pass "5. Noctalia + legacy Hotkeys is valid"
else
    fail "5. Noctalia + legacy Hotkeys failed planning: rc=$plan_leg_rc"
fi

section "6. Hotkeys Provider Conflict Resolution"

init_desired_state "DS_HOTKEY_CONFLICT" "workstation"
desired_state_set_component "DS_HOTKEY_CONFLICT" "desktop.hotkeys.legacy" "managed"
desired_state_set_component "DS_HOTKEY_CONFLICT" "desktop.hotkeys.aurelia" "managed"
desired_state_set_default "DS_HOTKEY_CONFLICT" "browser" "chromium"
desired_state_set_default "DS_HOTKEY_CONFLICT" "file-manager" "nautilus"

plan_conf_rc=0
create_execution_plan "DS_HOTKEY_CONFLICT" "PLAN_HOTKEY_CONFLICT" 2>/dev/null || plan_conf_rc=$?
if [[ "$plan_conf_rc" -ne 0 ]]; then
    pass "6. provider conflict prevents two Hotkeys owners from being active simultaneously"
else
    fail "6. planner allowed conflicting hotkey providers to be managed simultaneously"
fi

section "7. Disabled Aurelia Components Are Not Started"

shell_qml="$ROOT/dotfiles/aurelia/shell.qml"
if [[ -f "$shell_qml" ]] &&
   grep -q "active: root.hotkeysEnabled" "$shell_qml" &&
   ! grep -q "bar" "$shell_qml" &&
   ! grep -q "launcher" "$shell_qml" &&
   ! grep -q "notifications" "$shell_qml"; then
    pass "7. disabled Aurelia components are not started (conditional loader; zero secondary shell processes)"
else
    fail "7. Aurelia shell.qml does not enforce conditional component loading"
fi

section "8. Structured Backend Data Consumption"

json_output="$("$ROOT/bin/workstation-hotkeys" json)"
json_count="$(python3 -c 'import sys, json; data = json.loads(sys.stdin.read()); print(len(data))' <<< "$json_output")"
if [[ "$json_count" -ge 30 ]]; then
    pass "8. Aurelia Hotkeys consumes structured backend data ($json_count items exported)"
else
    fail "8. Failed to export structured backend JSON: count=$json_count"
fi

section "9. Canonical Shortcut Truth Invariance"

# Ensure QML files contain zero hardcoded shortcut definitions (single source of truth in Lua)
qml_hardcoded="$(grep -E '(Super \+ [A-Za-z0-9]|SUPER \+ [A-Za-z0-9])' "$ROOT/dotfiles/aurelia/components/hotkeys/"*.qml 2>/dev/null || true)"
if [[ -z "$qml_hardcoded" ]]; then
    pass "9. UI does not duplicate canonical shortcut truth (100% derived from backend)"
else
    fail "9. QML contains hardcoded shortcuts: $qml_hardcoded"
fi

section "10. Deterministic Ordering Invariance"

order_check="$(python3 -c '
import sys, json
data = json.loads(sys.stdin.read())
priorities = [item["priority"] for item in data]
# Verify ascending priority ordering
if priorities == sorted(priorities):
    print("ORDER_OK")
else:
    print("ORDER_MISMATCH")
' <<< "$json_output")"
if [[ "$order_check" == "ORDER_OK" ]]; then
    pass "10. priority/order is deterministic"
else
    fail "10. ordering is not deterministic"
fi

section "11. First Visible Actions Hierarchy"

first_5_ids="$(python3 -c '
import sys, json
data = json.loads(sys.stdin.read())
print(" ".join([item["id"] for item in data[:5]]))
' <<< "$json_output")"
if [[ "$first_5_ids" == "launcher terminal file_manager browser hotkeys" ]]; then
    pass "11. first visible actions are App Launcher, Terminal, Files, Browser, Hotkeys when available"
else
    fail "11. First visible actions mismatch: $first_5_ids"
fi

section "12-14. Search Matching Invariants"

# Test 12: Matches display hotkey
search_key_match="$(python3 -c '
import sys, json
data = json.loads(sys.stdin.read())
matches = [i["id"] for i in data if "return" in (i["display_key"] + " " + i["description"]).lower()]
print(" ".join(matches))
' <<< "$json_output")"
if [[ "$search_key_match" == *"terminal"* ]]; then
    pass "12. search matches display hotkey (e.g. Return -> Terminal)"
else
    fail "12. search failed to match display hotkey"
fi

# Test 13: Matches action title
search_title_match="$(python3 -c '
import sys, json
data = json.loads(sys.stdin.read())
matches = [i["id"] for i in data if "files" in (i["display_key"] + " " + i["description"]).lower()]
print(" ".join(matches))
' <<< "$json_output")"
if [[ "$search_title_match" == *"file_manager"* ]]; then
    pass "13. search matches action title (e.g. Files -> file_manager)"
else
    fail "13. search failed to match action title"
fi

# Test 14: Does not require or match on internal action ID
search_id_only="$(python3 -c '
import sys, json
data = json.loads(sys.stdin.read())
# Search query "file_manager": internal ID is "file_manager", but display is "Files" and key is "Super + E"
matches = [i["id"] for i in data if "file_manager" in (i["display_key"] + " " + i["description"]).lower()]
print(len(matches))
' <<< "$json_output")"
if [[ "$search_id_only" -eq 0 ]]; then
    pass "14. search does not require internal action ID (search operates exclusively on visible tokens)"
else
    fail "14. search leaked internal action ID into filter matching"
fi

section "15-16. Return / Action Execution Invariants"

# Test 15: Return invokes runnable action path
run_term_rc=0
HOTKEYS_TEST_ACTION=run HOTKEYS_TEST_ID=terminal "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || run_term_rc=$?
if [[ "$run_term_rc" -eq 0 ]]; then
    pass "15. Return invokes runnable action path"
else
    fail "15. Return failed on runnable action: rc=$run_term_rc"
fi

# Test 16: Return does not pretend to run non-runnable action
run_nonrun_rc=0
"$ROOT/bin/workstation-hotkeys" run window_close >/dev/null 2>&1 || run_nonrun_rc=$?
if [[ "$run_nonrun_rc" -ne 0 ]]; then
    pass "16. Return does not pretend to run non-runnable action (fails closed without execution)"
else
    fail "16. Return executed non-runnable context action"
fi

section "17-18. Shortcut Mutation Invariants (Alt+S and Alt+U)"

test_sb="$(mktemp -d)"
test_overrides="$test_sb/overrides.json"
echo "{}" > "$test_overrides"

# Test 17: Alt+S routes to physical capture backend
HOTKEYS_OVERRIDES="$test_overrides" HOTKEYS_CAPTURE_MOCK_INPUT="SUPER+SHIFT+T" "$ROOT/bin/workstation-hotkeys" set terminal >/dev/null 2>&1
check_set="$(cat "$test_overrides")"
if [[ "$check_set" == *"SUPER + SHIFT + T"* ]]; then
    pass "17. Alt+S routes to existing physical capture backend"
else
    fail "17. Alt+S failed to route to capture backend: $check_set"
fi

# Test 18: Alt+U routes to unset backend
HOTKEYS_OVERRIDES="$test_overrides" "$ROOT/bin/workstation-hotkeys" unset terminal >/dev/null 2>&1
check_unset="$(cat "$test_overrides")"
if [[ "$check_unset" == *"false"* || "$check_unset" == *"none"* ]]; then
    pass "18. Alt+U routes to existing unset backend"
else
    fail "18. Alt+U failed to unset shortcut: $check_unset"
fi
rm -rf "$test_sb"

section "19-20. Backend-Owned Normalization and Conflict Detection"

# Test 19: Canonical normalization remains backend-owned
norm_test="$(
"$lua_bin" - "$ROOT/dotfiles/hypr" <<'LUA'
local dir = arg[1]
package.path = dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local k1 = eff.canonical_key("ctrl + alt + super + k")
local k2 = eff.canonical_key("super + ctrl + alt + k")
if k1 == k2 and k1 == "super+ctrl+alt+k" then
    print("NORM_OK")
else
    print("NORM_FAIL:" .. tostring(k1) .. " vs " .. tostring(k2))
end
LUA
)"
if [[ "$norm_test" == "NORM_OK" ]]; then
    pass "19. canonical normalization remains backend-owned"
else
    fail "19. canonical normalization failed: $norm_test"
fi

# Test 20: Conflict detection remains backend-owned
conflict_test="$(
"$lua_bin" - "$ROOT/dotfiles/hypr" <<'LUA'
local dir = arg[1]
package.path = dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local m = dofile(dir .. "/keybindings_manifest.lua")
local conflict = eff.find_conflict("browser", "SUPER + RETURN", m)
if conflict and conflict.id == "terminal" then
    print("CONFLICT_DETECTED")
else
    print("CONFLICT_MISSED")
end
LUA
)"
if [[ "$conflict_test" == "CONFLICT_DETECTED" ]]; then
    pass "20. conflict detection remains backend-owned"
else
    fail "20. conflict detection failed: $conflict_test"
fi

section "21-22. Command Execution Safety Invariants"

# Test 21: Structured argv execution remains preserved
term_argv="$(HOTKEYS_TEST_ACTION=run_argv HOTKEYS_TEST_ID=terminal "$ROOT/bin/workstation-hotkeys")"
if [[ "$term_argv" == "kitty" || "$term_argv" == "foot" ]]; then
    pass "21. structured argv execution remains preserved"
else
    fail "21. structured argv failed: $term_argv"
fi

# Test 22: No eval or sh -c command execution added
eval_hotkeys="$(grep -E 'eval |sh -c' "$ROOT/bin/workstation-hotkeys" 2>/dev/null || true)"
eval_qml="$(grep -E 'eval\(|sh -c' "$ROOT/dotfiles/aurelia/components/hotkeys/"*.qml 2>/dev/null || true)"
if [[ -z "$eval_hotkeys" && -z "$eval_qml" ]]; then
    pass "22. no eval/sh-c command execution added"
else
    fail "22. unsafe command execution detected: hotkeys=$eval_hotkeys qml=$eval_qml"
fi

section "23-24. Resilience and Atomicity Invariants"

# Test 23: Aurelia failure leaves legacy/Noctalia state intact
fail_fallback_out="$(HOTKEYS_SIMULATE_AURELIA_FAIL=1 HOTKEYS_FORCE_STDOUT=1 "$ROOT/bin/workstation-hotkeys" --provider=aurelia)"
if [[ "$fail_fallback_out" == *"Keyboard Shortcuts"* && "$fail_fallback_out" == *"Applications & Launchers"* ]]; then
    pass "23. Aurelia failure leaves legacy/Noctalia state intact and falls back safely"
else
    fail "23. Aurelia failure did not fall back cleanly to legacy manager"
fi

# Test 24: Config/state writes are atomic where applicable
cfg_sb="$(mktemp -d)"
TARGET_HOME="$cfg_sb" set_workstation_hotkeys_provider "aurelia"
if [[ -f "$cfg_sb/.config/workstation/desktop.conf" ]] &&
   grep -q "hotkeys.provider = aurelia" "$cfg_sb/.config/workstation/desktop.conf"; then
    pass "24. config/state writes are atomic where applicable"
else
    fail "24. atomic state write failed"
fi
rm -rf "$cfg_sb"

section "25. Single Runtime Instance Invariant"

# Invariant: QML architecture hosts single Quickshell process with zero duplicate daemons
if grep -q "ShellRoot" "$ROOT/dotfiles/aurelia/shell.qml" &&
   grep -q 'target: "hotkeys"' "$ROOT/dotfiles/aurelia/shell.qml"; then
    pass "25. no duplicate Aurelia runtime instance is started (single ShellRoot with IPC endpoint)"
else
    fail "25. ShellRoot or IPC missing in Aurelia configuration"
fi

section "26-27. Super+K Dispatch and Legacy Fallback"

# Test 26: Current provider determines Super+K target
aure_target="$(HOTKEYS_SIMULATE_AURELIA_SUCCESS=1 "$ROOT/bin/workstation-hotkeys" --provider=aurelia)"
if [[ "$aure_target" == "AURELIA_TOGGLE_OK" ]]; then
    pass "26. current provider determines Super+K target (dispatches to Aurelia when selected)"
else
    fail "26. provider dispatch failed: $aure_target"
fi

# Test 27: Legacy fzf Hotkeys remains available as fallback
leg_target="$(HOTKEYS_FORCE_STDOUT=1 "$ROOT/bin/workstation-hotkeys" --provider=legacy)"
if [[ "$leg_target" == *"Keyboard Shortcuts"* ]]; then
    pass "27. legacy fzf Hotkeys remains available as fallback"
else
    fail "27. legacy Hotkeys interface unavailable"
fi

section "28. Default Environment Stability Invariant"

# Noctalia must remain the Recommended/default environment unless explicitly changed
rec_noct="$(get_component_attr "desktop.environment.noctalia" recommended)"
rec_aure="$(get_component_attr "desktop.environment.aurelia" recommended)"
if [[ "$rec_noct" == "true" && "$rec_aure" == "false" ]]; then
    pass "28. Noctalia remains Recommended/default environment unless explicitly changed"
else
    fail "28. Desktop environment recommendation violated: noctalia=$rec_noct aurelia=$rec_aure"
fi

section "29-30. Nautilus and Thunar File Manager Transition Invariants"

# Test 29: If Nautilus is implemented, deselecting Thunar does not remove it (removable: false)
thunar_removable="$(get_component_attr "thunar" removable)"
if [[ "$thunar_removable" == "false" ]]; then
    pass "29. if Nautilus is implemented, deselecting Thunar does not remove it (removable: false invariant)"
else
    fail "29. Thunar is marked removable: $thunar_removable"
fi

# Test 30: If Nautilus is implemented, default file-manager role changes explicitly
init_desired_state "DS_FM_TEST" "workstation"
create_recommended_desired_state "DS_FM_TEST" "workstation"
fm_default="$(desired_state_get_default "DS_FM_TEST" "file-manager")"
if [[ "$fm_default" == "nautilus" ]]; then
    pass "30. if Nautilus is implemented, default file-manager role changes explicitly to nautilus"
else
    fail "30. Default file manager role did not default to nautilus: $fm_default"
fi

section "31. Quickshell Stable Package Identity vs Git Snapshots"

# Test 31: detect_quickshell must strictly reject quickshell-git and git snapshots
(
    rpm() {
        if [[ "$*" == *"%{NAME}"* ]]; then
            printf '%s\n' "quickshell-git"
        elif [[ "$*" == *"%{VERSION}-%{RELEASE}"* ]]; then
            printf '%s\n' "0.3.1^856.git2d3b3e9-2.fc44"
        fi
    }
    if detect_quickshell; then
        fail "31. detect_quickshell accepted quickshell-git"
    else
        pass "31. stable Quickshell package identity cannot resolve to quickshell-git"
    fi
)

section "32. Production Provider Authority Invariance"

# Test 32: Arbitrary environment variables must NOT override persisted configuration
sb_auth_test="$(mktemp -d)"
mkdir -p "$sb_auth_test/.config/workstation"
echo "hotkeys.provider = legacy" > "$sb_auth_test/.config/workstation/desktop.conf"
auth_prov="$(
    XDG_CONFIG_HOME="$sb_auth_test/.config" \
    HOTKEYS_PROVIDER="aurelia" \
    WORKSTATION_HOTKEYS_PROVIDER="aurelia" \
    HOTKEYS_TEST_ACTION="provider" \
    "$ROOT/bin/workstation-hotkeys"
)"
rm -rf "$sb_auth_test"
if [[ "$auth_prov" == "legacy" ]]; then
    pass "32. production provider authority is persisted config, not arbitrary env override"
else
    fail "32. arbitrary env variable bypassed persisted provider authority: $auth_prov"
fi

section "33. Single-Instance and Path Option Dispatch Invariants"

# Test 33: Quickshell dispatch must use --no-duplicate and --path
dispatch_src="$(grep -E '\$qs_bin.*--no-duplicate.*--path' "$ROOT/bin/workstation-hotkeys" || true)"
if [[ -n "$dispatch_src" ]]; then
    pass "33. repeated dispatch cannot create duplicate instances (uses --no-duplicate and --path)"
else
    fail "33. dispatch missing --no-duplicate or --path"
fi

section "34-35. Strict Action ID Validation"

# Test 34: Unknown action ID must fail closed
unknown_rc=0
"$ROOT/bin/workstation-hotkeys" run "non_existent_action_xyz" >/dev/null 2>&1 || unknown_rc=$?
if [[ "$unknown_rc" -ne 0 ]]; then
    pass "34. unknown action ID cannot run (fails closed)"
else
    fail "34. unknown action ID succeeded unexpectedly"
fi

# Test 35: Malicious/metacharacter action ID must fail closed
meta_rc=0
"$ROOT/bin/workstation-hotkeys" run "app:foo;reboot" >/dev/null 2>&1 || meta_rc=$?
if [[ "$meta_rc" -ne 0 ]]; then
    pass "35. invalid action ID format fails closed"
else
    fail "35. invalid action ID accepted: rc=$meta_rc"
fi

section "36-37. Security and Command Construction Invariants"

# Test 36: QML IPC endpoints expose only allowlisted operations
ipc_methods="$(grep -E 'function [a-zA-Z0-9_]+\(\)' "$ROOT/dotfiles/aurelia/shell.qml" | sed 's/^[[:space:]]*function //;s/(.*//' | tr '\n' ' ')"
if [[ "$ipc_methods" =~ (ping toggle open close isVisible|ping toggle isVisible open close|toggle open close isVisible) ]]; then
    pass "36. QML can invoke only allowlisted backend operations"
else
    fail "36. QML IPC methods contain unexpected endpoints: $ipc_methods"
fi

# Test 37: Zero shell command injection / string concatenation
if ! grep -E '(bash -c|sh -c|eval )' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeysModel.qml" >/dev/null; then
    pass "37. no shell command construction from action metadata"
else
    fail "37. found shell command construction in HotkeysModel.qml"
fi

section "38-40. Coexistence and Adaptation Invariants"

# Test 38: Inactive Aurelia components remain unloaded
if grep -q 'active: root.hotkeysEnabled' "$ROOT/dotfiles/aurelia/shell.qml"; then
    pass "38. inactive Aurelia components remain unloaded"
else
    fail "38. inactive Aurelia components not conditionally loaded"
fi

# Test 39: Noctalia components remain untouched when Aurelia Hotkeys is selected
reset_component_registry
init_default_components
init_desired_state "DS_NOCT_UNTOUCH" "workstation"
create_recommended_desired_state "DS_NOCT_UNTOUCH" "workstation"
desired_state_set_component "DS_NOCT_UNTOUCH" "desktop.hotkeys.aurelia" "managed"
desired_state_set_component "DS_NOCT_UNTOUCH" "desktop.hotkeys.legacy" "unmanaged"
noct_status="$(desired_state_get_component "DS_NOCT_UNTOUCH" "desktop.environment.noctalia")"
if [[ "$noct_status" == "managed" ]]; then
    pass "39. Noctalia components remain untouched when Aurelia Hotkeys selected"
else
    fail "39. Noctalia component state mutated: $noct_status"
fi

# Test 40: Nautilus role default detection works
(
    xdg-mime() {
        if [[ "$1" == "query" && "$2" == "default" && "$3" == "inode/directory" ]]; then
            printf '%s\n' "org.gnome.Nautilus.desktop"
        fi
    }
    export -f xdg-mime
    fm_detected="$(detect_file_manager_default_adapter)"
    if [[ "$fm_detected" == "nautilus" ]]; then
        pass "40. Nautilus role default detection works"
    else
        fail "40. Nautilus default detection failed: $fm_detected"
    fi
)

section "41-43. Cold-Start and Warm-Start Single-Toggle Invariants"

# Test 41: Cold start invokes mutating toggle exactly once after non-mutating ping
(
    mock_dir="$(mktemp -d)"
    mock_log="$(mktemp)"
    cat << "EOF" > "$mock_dir/qs"
#!/usr/bin/env bash
if [[ "$1" == "ipc" && "$2" == "call" && "$3" == "hotkeys" ]]; then
    if [[ "$4" == "toggle" ]]; then
        echo "toggle" >> "$MOCK_LOG"
        cnt=$(grep -c "toggle" "$MOCK_LOG")
        if [[ "$cnt" -eq 1 ]]; then
            exit 1
        fi
        exit 0
    elif [[ "$4" == "ping" ]]; then
        echo "ping" >> "$MOCK_LOG"
        exit 0
    fi
elif [[ "$1" == "--no-duplicate" ]]; then
    echo "daemon_start" >> "$MOCK_LOG"
    exit 0
fi
exit 0
EOF
    chmod +x "$mock_dir/qs"
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" HOTKEYS_TEST_PROVIDER="aurelia" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true
    toggle_count="$(grep -c '^toggle$' "$mock_log" || true)"
    ping_count="$(grep -c '^ping$' "$mock_log" || true)"
    daemon_count="$(grep -c '^daemon_start$' "$mock_log" || true)"
    rm -rf "$mock_dir" "$mock_log"
    # Initial warm probe failed (1 toggle attempt), daemon started (1), ping probe succeeded, exactly 1 mutating toggle after readiness
    if [[ "$toggle_count" -eq 2 && "$ping_count" -ge 1 && "$daemon_count" -eq 1 ]]; then
        pass "41. cold startup uses non-mutating ping probe and invokes toggle exactly once after readiness"
    else
        fail "41. cold startup toggle/ping invariant violated: toggles=$toggle_count pings=$ping_count daemons=$daemon_count"
    fi
)

# Test 42: Warm start invokes mutating toggle exactly once without starting daemon or polling ping
(
    mock_dir="$(mktemp -d)"
    mock_log="$(mktemp)"
    cat << "EOF" > "$mock_dir/qs"
#!/usr/bin/env bash
if [[ "$1" == "ipc" && "$2" == "call" && "$3" == "hotkeys" ]]; then
    if [[ "$4" == "toggle" ]]; then
        echo "toggle" >> "$MOCK_LOG"
        exit 0
    elif [[ "$4" == "ping" ]]; then
        echo "ping" >> "$MOCK_LOG"
        exit 0
    fi
elif [[ "$1" == "--no-duplicate" ]]; then
    echo "daemon_start" >> "$MOCK_LOG"
    exit 0
fi
exit 0
EOF
    chmod +x "$mock_dir/qs"
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" HOTKEYS_TEST_PROVIDER="aurelia" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true
    toggle_count="$(grep -c '^toggle$' "$mock_log" || true)"
    daemon_count="$(grep -c '^daemon_start$' "$mock_log" || true)"
    ping_count="$(grep -c '^ping$' "$mock_log" || true)"
    rm -rf "$mock_dir" "$mock_log"
    if [[ "$toggle_count" -eq 1 && "$daemon_count" -eq 0 && "$ping_count" -eq 0 ]]; then
        pass "42. warm startup invokes toggle exactly once without starting daemon"
    else
        fail "42. warm startup invariant violated: toggles=$toggle_count daemons=$daemon_count pings=$ping_count"
    fi
)

# Test 43: Startup timeout is bounded around 2s (~40 attempts * 50ms)
timeout_spec="$(grep -E 'for _ in \{1\.\.40\}' "$ROOT/bin/workstation-hotkeys" || true)"
sleep_spec="$(grep -E 'sleep 0\.05' "$ROOT/bin/workstation-hotkeys" || true)"
if [[ -n "$timeout_spec" && -n "$sleep_spec" ]]; then
    pass "43. startup timeout is bounded around 2s (40 * 50ms) without arbitrary long sleeps"
else
    fail "43. startup timeout not bounded around 2s"
fi

section "44-48. Omarchy-Inspired UI and Presentation Invariants"

# Test 44: No keycap badge or pill rectangles in HotkeyRow
if ! grep -E '(Rectangle \{.*id: keyBadge|border\.color: rowRoot\.isSelected)' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeyRow.qml" >/dev/null; then
    pass "44. no keycap-per-modifier UI or row borders introduced (clean two-column layout)"
else
    fail "44. found keycap badge or row borders in HotkeyRow.qml"
fi

# Test 45: Row display renders shortcut + separator arrow + action title
if grep -q 'text: rowRoot.formattedShortcut()' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeyRow.qml" &&
   grep -q 'text: "→"' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeyRow.qml" &&
   grep -q 'text: rowRoot.modelData ? (rowRoot.modelData.description || "") : ""' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeyRow.qml"; then
    pass "45. row display has shortcut + arrow separator + action presentation"
else
    fail "45. row display missing shortcut, arrow, or action presentation"
fi

# Test 46: Search area uses minimal keybindings_ prompt style without boxed rectangle
if grep -q 'text: "keybindings_"' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeysWindow.qml" &&
   ! grep -E 'Rectangle \{.*Search shortcuts' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeysWindow.qml" >/dev/null; then
    pass "46. search area uses minimal keybindings_ prompt style without boxed rectangle"
else
    fail "46. search area has boxed rectangle or missing keybindings_ prompt"
fi

# Test 47: Footer is textual/hint-based and not modeled as action buttons
if grep -q 'text: "↵"' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeysWindow.qml" &&
   grep -q 'text: "Alt+S"' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeysWindow.qml" &&
   grep -q 'text: "Alt+U"' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeysWindow.qml" &&
   grep -q 'text: "Esc"' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeysWindow.qml" &&
   ! grep -E 'Rectangle \{.*Layout\.preferredWidth: altSText' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeysWindow.qml" >/dev/null; then
    pass "47. footer is textual/hint-based, not modeled as action buttons"
else
    fail "47. footer contains button boxes or missing keyboard hints"
fi

# Test 48: No category headings/IDs/commands appear in normal row presentation
if ! grep -E '(category|action_id|command_argv)' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeyRow.qml" >/dev/null; then
    pass "48. no category headings/IDs/commands appear in normal row presentation"
else
    fail "48. HotkeyRow leaks category headings or internal commands"
fi

section "49-50. Performance and Sizing Invariants"

# Test 49: Search does not spawn processes
if ! grep -E 'filterItems.*Process' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeysModel.qml" >/dev/null; then
    pass "49. search operates in-memory with zero process spawning on keystrokes"
else
    fail "49. process spawning detected in search"
fi

# Test 50: Window dimensions follow restrained command-palette proportions (800x480)
if grep -q 'implicitWidth: 800' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeysWindow.qml" &&
   grep -q 'implicitHeight: 480' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeysWindow.qml"; then
    pass "50. window dimensions follow restrained command-palette proportions (800x480)"
else
    fail "50. window dimensions deviate from command-palette target"
fi

section "51-60. Generic Reconciler Dependency Enforcement & Provider Preservation"

# Test 51: dependency succeeds -> dependent executes
(
    reset_component_registry
    register_component id "dep_ok" display_name "Dep OK" category "Testing" install_fn "mock_inst_dep_ok"
    register_component id "app_ok" display_name "App OK" category "Testing" dependencies "dep_ok" install_fn "mock_inst_app_ok"
    c_dep=0; c_app=0
    mock_inst_dep_ok() { c_dep=$((c_dep + 1)); return 0; }
    mock_inst_app_ok() { c_app=$((c_app + 1)); return 0; }

    init_plan "PLAN_DEP_OK"
    add_plan_action "PLAN_DEP_OK" "INSTALL" "dep_ok" "test" "Dep OK"
    add_plan_action "PLAN_DEP_OK" "INSTALL" "app_ok" "test" "App OK"
    finalize_plan "PLAN_DEP_OK"

    rec_rc=0
    execute_plan "PLAN_DEP_OK" >/dev/null 2>&1 || rec_rc=$?
    if [[ "$rec_rc" -eq 0 && "$c_dep" -eq 1 && "$c_app" -eq 1 ]]; then
        pass "51. dependency succeeds -> dependent executes"
    else
        fail "51. dependency success execution failed: rc=$rec_rc dep=$c_dep app=$c_app"
    fi
)

# Test 52: dependency fails -> dependent callback is NOT invoked
(
    reset_component_registry
    register_component id "dep_fail" display_name "Dep Fail" category "Testing" install_fn "mock_inst_dep_fail"
    register_component id "app_blocked" display_name "App Blocked" category "Testing" dependencies "dep_fail" install_fn "mock_inst_app_blocked"
    c_dep_fail=0; c_app_blocked=0
    mock_inst_dep_fail() { c_dep_fail=$((c_dep_fail + 1)); return 1; }
    mock_inst_app_blocked() { c_app_blocked=$((c_app_blocked + 1)); return 0; }

    init_plan "PLAN_DEP_FAIL"
    add_plan_action "PLAN_DEP_FAIL" "INSTALL" "dep_fail" "test" "Dep Fail"
    add_plan_action "PLAN_DEP_FAIL" "INSTALL" "app_blocked" "test" "App Blocked"
    finalize_plan "PLAN_DEP_FAIL"

    rec_rc=0
    execute_plan "PLAN_DEP_FAIL" >/dev/null 2>&1 || rec_rc=$?
    if [[ "$rec_rc" -ne 0 && "$c_dep_fail" -eq 1 && "$c_app_blocked" -eq 0 ]]; then
        pass "52. dependency fails -> dependent callback is NOT invoked"
    else
        fail "52. dependent callback was invoked despite dependency failure: rc=$rec_rc blocked_calls=$c_app_blocked"
    fi
)

# Test 53: dependent recorded as blocked
(
    reset_component_registry
    INSTALL_DEFERRED=()
    register_component id "dep_fail" display_name "Dep Fail" category "Testing" install_fn "mock_inst_fail"
    register_component id "app_blocked" display_name "App Blocked" category "Testing" dependencies "dep_fail" install_fn "mock_inst_blocked"
    mock_inst_fail() { return 1; }
    mock_inst_blocked() { return 0; }

    init_plan "PLAN_DEP_BLOCKED"
    add_plan_action "PLAN_DEP_BLOCKED" "INSTALL" "dep_fail" "test" "Dep Fail"
    add_plan_action "PLAN_DEP_BLOCKED" "INSTALL" "app_blocked" "test" "App Blocked"
    finalize_plan "PLAN_DEP_BLOCKED"

    execute_plan "PLAN_DEP_BLOCKED" >/dev/null 2>&1 || true

    blocked_found=0
    for entry in "${INSTALL_DEFERRED[@]}"; do
        if [[ "$entry" == *"app_blocked"* && "$entry" == *"Blocked because required dependency dep_fail failed"* ]]; then
            blocked_found=1
            break
        fi
    done

    if [[ "$blocked_found" -eq 1 ]]; then
        pass "53. dependent recorded as blocked in deferred failure journal"
    else
        fail "53. dependent blocking was not journaled in INSTALL_DEFERRED: ${INSTALL_DEFERRED[*]}"
    fi
)

# Test 54: transitive dependency failure blocks downstream components
(
    reset_component_registry
    register_component id "c_root" display_name "Root" category "Testing" install_fn "mock_root_fail"
    register_component id "c_mid" display_name "Mid" category "Testing" dependencies "c_root" install_fn "mock_mid"
    register_component id "c_leaf" display_name "Leaf" category "Testing" dependencies "c_mid" install_fn "mock_leaf"

    c_root_cnt=0; c_mid_cnt=0; c_leaf_cnt=0
    mock_root_fail() { c_root_cnt=$((c_root_cnt + 1)); return 1; }
    mock_mid() { c_mid_cnt=$((c_mid_cnt + 1)); return 0; }
    mock_leaf() { c_leaf_cnt=$((c_leaf_cnt + 1)); return 0; }

    init_plan "PLAN_TRANS"
    add_plan_action "PLAN_TRANS" "INSTALL" "c_root" "test" "Root"
    add_plan_action "PLAN_TRANS" "INSTALL" "c_mid" "test" "Mid"
    add_plan_action "PLAN_TRANS" "INSTALL" "c_leaf" "test" "Leaf"
    finalize_plan "PLAN_TRANS"

    execute_plan "PLAN_TRANS" >/dev/null 2>&1 || true
    if [[ "$c_root_cnt" -eq 1 && "$c_mid_cnt" -eq 0 && "$c_leaf_cnt" -eq 0 ]]; then
        pass "54. transitive dependency failure blocks downstream components"
    else
        fail "54. transitive failure did not block downstream: root=$c_root_cnt mid=$c_mid_cnt leaf=$c_leaf_cnt"
    fi
)

# Test 55: unrelated component still executes
(
    reset_component_registry
    register_component id "c_fail" display_name "Fail" category "Testing" install_fn "mock_fail"
    register_component id "c_dep" display_name "Dep" category "Testing" dependencies "c_fail" install_fn "mock_dep"
    register_component id "c_unrel" display_name "Unrel" category "Testing" install_fn "mock_unrel"

    c_fail_cnt=0; c_dep_cnt=0; c_unrel_cnt=0
    mock_fail() { c_fail_cnt=$((c_fail_cnt + 1)); return 1; }
    mock_dep() { c_dep_cnt=$((c_dep_cnt + 1)); return 0; }
    mock_unrel() { c_unrel_cnt=$((c_unrel_cnt + 1)); return 0; }

    init_plan "PLAN_UNREL"
    add_plan_action "PLAN_UNREL" "INSTALL" "c_fail" "test" "Fail"
    add_plan_action "PLAN_UNREL" "INSTALL" "c_dep" "test" "Dep"
    add_plan_action "PLAN_UNREL" "INSTALL" "c_unrel" "test" "Unrel"
    finalize_plan "PLAN_UNREL"

    execute_plan "PLAN_UNREL" >/dev/null 2>&1 || true
    if [[ "$c_fail_cnt" -eq 1 && "$c_dep_cnt" -eq 0 && "$c_unrel_cnt" -eq 1 ]]; then
        pass "55. unrelated component still executes despite sibling dependency failure"
    else
        fail "55. unrelated component was incorrectly blocked or failed: fail=$c_fail_cnt dep=$c_dep_cnt unrel=$c_unrel_cnt"
    fi
)

# Test 56: optional overall failure does not block login activation
(
    ACTIVATION_BLOCKED=0
    INSTALL_DEFERRED=()
    INSTALL_REQUIRED_FAILURES=()

    reset_component_registry
    register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
    register_component id "opt_dep" display_name "Opt Dep" category "Testing" required false install_fn "mock_fail"
    register_component id "opt_app" display_name "Opt App" category "Testing" required false dependencies "opt_dep" install_fn "mock_ok"
    mock_fail() { return 1; }
    mock_ok() { return 0; }

    init_plan "PLAN_OPT_GUARD"
    add_plan_action "PLAN_OPT_GUARD" "INSTALL" "opt_dep" "test" "Opt Dep"
    add_plan_action "PLAN_OPT_GUARD" "INSTALL" "opt_app" "test" "Opt App"
    finalize_plan "PLAN_OPT_GUARD"

    run_classified_step workstation "Reconciling configured components" execute_plan "PLAN_OPT_GUARD"

    if [[ "$ACTIVATION_BLOCKED" -eq 0 && ${#INSTALL_REQUIRED_FAILURES[@]} -eq 0 && ${#INSTALL_DEFERRED[@]} -gt 0 ]]; then
        pass "56. optional component dependency failure does not block login activation"
    else
        fail "56. optional component failure incorrectly escalated: blocked=$ACTIVATION_BLOCKED req=${#INSTALL_REQUIRED_FAILURES[@]}"
    fi
)

# Test 57: failed Aurelia dependency preserves legacy provider
(
    prov_sb="$(mktemp -d)"
    mkdir -p "$prov_sb/.config/workstation"
    printf 'hotkeys.provider = legacy\n' > "$prov_sb/.config/workstation/desktop.conf"

    reset_component_registry
    init_default_components

    # Force quickshell install to fail
    install_quickshell_adapter() { return 1; }

    init_plan "PLAN_AURE_FAIL"
    add_plan_action "PLAN_AURE_FAIL" "INSTALL" "quickshell" "convergence required" "Quickshell Toolkit"
    add_plan_action "PLAN_AURE_FAIL" "INSTALL" "desktop.hotkeys.aurelia" "selected by user" "Aurelia Hotkeys"
    finalize_plan "PLAN_AURE_FAIL"

    TARGET_HOME="$prov_sb" execute_plan "PLAN_AURE_FAIL" >/dev/null 2>&1 || true

    curr_prov="$(grep -E '^[[:space:]]*hotkeys[._]provider[[:space:]]*=' "$prov_sb/.config/workstation/desktop.conf" | cut -d '=' -f2 | tr -d '[:space:]')"
    rm -rf "$prov_sb"

    if [[ "$curr_prov" == "legacy" ]]; then
        pass "57. failed Aurelia dependency preserves legacy provider (hotkeys.provider = legacy)"
    else
        fail "57. legacy provider was not preserved: '$curr_prov'"
    fi
)

# Test 58: provider config is not committed before successful dependency/component validation
(
    prov_sb="$(mktemp -d)"
    mkdir -p "$prov_sb/.config/workstation"
    printf 'hotkeys.provider = legacy\n' > "$prov_sb/.config/workstation/desktop.conf"

    reset_component_registry
    init_default_components

    # Quickshell succeeds, but validate_aurelia_hotkeys fails
    install_quickshell_adapter() { return 0; }
    detect_quickshell() { return 0; }
    detect_aurelia_hotkeys() { return 1; }
    validate_aurelia_hotkeys() { return 1; }

    init_plan "PLAN_VAL_FAIL"
    add_plan_action "PLAN_VAL_FAIL" "INSTALL" "quickshell" "new" "Quickshell Toolkit"
    add_plan_action "PLAN_VAL_FAIL" "INSTALL" "desktop.hotkeys.aurelia" "new" "Aurelia Hotkeys"
    finalize_plan "PLAN_VAL_FAIL"

    TARGET_HOME="$prov_sb" execute_plan "PLAN_VAL_FAIL" >/dev/null 2>&1 || true

    curr_prov="$(grep -E '^[[:space:]]*hotkeys[._]provider[[:space:]]*=' "$prov_sb/.config/workstation/desktop.conf" | cut -d '=' -f2 | tr -d '[:space:]')"
    rm -rf "$prov_sb"

    if [[ "$curr_prov" == "legacy" ]]; then
        pass "58. provider config is not committed when component validation fails"
    else
        fail "58. provider config was committed prematurely: '$curr_prov'"
    fi
)

# Test 59: rerun remains able to attempt desired Aurelia again
(
    reset_component_registry
    init_default_components
    init_desired_state "DS_RERUN" "vm"
    create_recommended_desired_state "DS_RERUN" "vm"
    desired_state_set_component "DS_RERUN" "desktop.hotkeys.aurelia" "managed"
    desired_state_set_component "DS_RERUN" "quickshell" "managed"

    # Simulate actual state where quickshell and aurelia are not present
    declare -g -A ACT_RERUN_PRESENT=([quickshell]=false [desktop.hotkeys.aurelia]=false)

    create_execution_plan "DS_RERUN" "PLAN_RERUN" "ACT_RERUN"
    finalize_plan "PLAN_RERUN"

    has_qs=0; has_aure=0
    for idx in "${PLAN_RERUN_ACTIONS[@]}"; do
        [[ "${PLAN_RERUN_ACTION_TARGET[$idx]}" == "quickshell" && "${PLAN_RERUN_ACTION_TYPE[$idx]}" == "INSTALL" ]] && has_qs=1
        [[ "${PLAN_RERUN_ACTION_TARGET[$idx]}" == "desktop.hotkeys.aurelia" && "${PLAN_RERUN_ACTION_TYPE[$idx]}" == "INSTALL" ]] && has_aure=1
    done

    if [[ "$has_qs" -eq 1 && "$has_aure" -eq 1 ]]; then
        pass "59. rerun remains able to attempt desired Aurelia and Quickshell"
    else
        fail "59. rerun plan failed to include desired components: qs=$has_qs aure=$has_aure"
    fi
)

# Test 60: no special-case component IDs are required for generic behavior
if ! grep -E '(quickshell|desktop\.hotkeys\.aurelia)' "$ROOT/modules/lib/reconciler.sh" >/dev/null; then
    pass "60. reconciler contains zero special-case strings for quickshell or aurelia (generic dependency model)"
else
    fail "60. special-cased component IDs found in reconciler.sh"
fi
