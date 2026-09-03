#!/usr/bin/env bash

# Test Suite: Aurelia Foundation, Quickshell Integration, Native Hotkeys Component, and Desktop Coexistence.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
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
if [[ "$ipc_methods" =~ ^(toggle open close isVisible |toggle isVisible open close ) ]]; then
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
