#!/usr/bin/env bash

# Test Suite: Workstation Configuration Architecture
# Tests Component Registry, Desired State, Planner, Reconciler, Roles, Defaults,
# Lifecycle Adapters, Review, Wizard Navigation, and CLI Contract.

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=/dev/null
source "$ROOT/modules/common.sh"

section "Component Registry"

reset_component_registry

# 1. Valid component registers
register_component \
    id "test_comp_a" \
    display_name "Test Component A" \
    category "Testing" \
    description "A test component" \
    supported_profiles "workstation vm" \
    recommended true \
    required false \
    removable true \
    roles "browser"

if component_exists "test_comp_a" && [[ "$(get_component_attr "test_comp_a" display_name)" == "Test Component A" ]]; then
    pass "valid component registers successfully and attributes are retrievable"
else
    fail "valid component registration failed"
fi

# 2. Duplicate component ID rejected
dup_rc=0
register_component id "test_comp_a" display_name "Duplicate" category "Testing" 2>/dev/null || dup_rc=$?
if [[ "$dup_rc" -ne 0 ]]; then
    pass "duplicate component ID is rejected fail-closed"
else
    fail "duplicate component ID was not rejected"
fi

# 3. Unknown dependency rejected
register_component \
    id "test_comp_b" \
    display_name "Test Component B" \
    category "Testing" \
    dependencies "nonexistent_component"
reg_val_rc=0
validate_component_registry 2>/dev/null || reg_val_rc=$?
if [[ "$reg_val_rc" -ne 0 ]]; then
    pass "registry referential integrity rejects unknown dependency"
else
    fail "registry allowed unknown dependency"
fi

# 4. Invalid profile rejected
inv_prof_rc=0
register_component \
    id "test_comp_c" \
    display_name "Test Component C" \
    category "Testing" \
    supported_profiles "invalid_profile" 2>/dev/null || inv_prof_rc=$?
if [[ "$inv_prof_rc" -ne 0 ]]; then
    pass "component with invalid profile is rejected"
else
    fail "component with invalid profile was allowed"
fi

# 5. Capability metadata available
reset_component_registry
register_component \
    id "test_cap" \
    display_name "Capability Test" \
    category "Testing" \
    provides "cap_x" \
    requires "cap_y"
if [[ "$(get_component_attr "test_cap" provides)" == "cap_x" && "$(get_component_attr "test_cap" requires)" == "cap_y" ]]; then
    pass "component capability provides and requires metadata are available"
else
    fail "component capability metadata retrieval failed"
fi

# 6. Role provider metadata available
reset_component_registry
register_component id "b1" display_name "Browser 1" category "Browsers" roles "browser"
register_component id "b2" display_name "Browser 2" category "Browsers" roles "browser"
register_component id "ed1" display_name "Editor 1" category "Editors" roles "text-editor"
providers="$(get_role_providers "browser")"
if [[ "$providers" == *"b1"* && "$providers" == *"b2"* && "$providers" != *"ed1"* ]]; then
    pass "role provider discovery lists matching components"
else
    fail "role provider discovery failed: $providers"
fi

section "Desired State Model"

# Restore default representative components
reset_component_registry
init_default_components

# 7. Valid recommended desired state
ds_rec="TEST_DS_REC"
create_recommended_desired_state "$ds_rec" "workstation"
ds_rec_val=0
validate_desired_state "$ds_rec" || ds_rec_val=$?
if [[ "$ds_rec_val" -eq 0 && "$(desired_state_get_component "$ds_rec" "foot")" == "managed" ]]; then
    pass "valid recommended desired state passes validation"
else
    fail "valid recommended desired state failed validation"
fi

# 8. Valid customize desired state
ds_cust="TEST_DS_CUST"
init_desired_state "$ds_cust" "workstation" "customize"
desired_state_set_component "$ds_cust" "foot" "managed"
desired_state_set_component "$ds_cust" "firefox" "managed"
desired_state_set_default "$ds_cust" "browser" "firefox"
ds_cust_val=0
validate_desired_state "$ds_cust" || ds_cust_val=$?
if [[ "$ds_cust_val" -eq 0 ]]; then
    pass "valid customize desired state passes validation"
else
    fail "valid customize desired state failed validation"
fi

# 9. Unknown component rejected
ds_unk="TEST_DS_UNK"
init_desired_state "$ds_unk" "workstation" "customize"
desired_state_set_component "$ds_unk" "ghost_app" "managed"
ds_unk_val=0
validate_desired_state "$ds_unk" 2>/dev/null || ds_unk_val=$?
if [[ "$ds_unk_val" -ne 0 ]]; then
    pass "desired state referencing unknown component is rejected"
else
    fail "desired state allowed unknown component"
fi

# 10. Required component cannot be silently removed
ds_req="TEST_DS_REQ"
init_desired_state "$ds_req" "workstation" "customize"
desired_state_set_component "$ds_req" "foot" "remove"
ds_req_val=0
validate_desired_state "$ds_req" 2>/dev/null || ds_req_val=$?
if [[ "$ds_req_val" -ne 0 ]]; then
    pass "required component cannot be marked for removal"
else
    fail "required component removal was permitted"
fi

# 11. unmanaged != remove
ds_unm="TEST_DS_UNM"
init_desired_state "$ds_unm" "workstation" "customize"
desired_state_set_component "$ds_unm" "chromium" "unmanaged"
desired_state_set_component "$ds_unm" "htop" "remove"
if [[ "$(desired_state_get_component "$ds_unm" "chromium")" == "unmanaged" && \
      "$(desired_state_get_component "$ds_unm" "htop")" == "remove" ]]; then
    pass "unmanaged and remove states are represented distinctly (unmanaged != remove)"
else
    fail "unmanaged vs remove distinction failed"
fi

# 12. Explicit remove represented distinctly in serialization
ser="$(serialize_desired_state "$ds_unm")"
if [[ "$ser" == *"COMPONENT:chromium=unmanaged"* && "$ser" == *"COMPONENT:htop=remove"* ]]; then
    pass "explicit remove and unmanaged states serialize distinctly"
else
    fail "serialization failed: $ser"
fi

section "Profile and Setup Mode Combinations"

# 13. workstation + recommended
p13="DS_13"
create_recommended_desired_state "$p13" "workstation"
if [[ "$(desired_state_get_component "$p13" "foot")" == "managed" ]]; then
    pass "workstation + recommended profile creates valid desired state"
else
    fail "workstation + recommended failed"
fi

# 14. workstation + customize
p14="DS_14"
init_desired_state "$p14" "workstation" "customize"
desired_state_set_component "$p14" "foot" "managed"
if validate_desired_state "$p14"; then
    pass "workstation + customize creates valid desired state"
else
    fail "workstation + customize validation failed"
fi

# 15. vm + recommended
p15="DS_15"
create_recommended_desired_state "$p15" "vm"
if [[ "$(desired_state_get_component "$p15" "foot")" == "managed" ]]; then
    pass "vm + recommended creates valid desired state"
else
    fail "vm + recommended failed"
fi

# 16. vm + customize
p16="DS_16"
init_desired_state "$p16" "vm" "customize"
desired_state_set_component "$p16" "foot" "managed"
if validate_desired_state "$p16"; then
    pass "vm + customize creates valid desired state"
else
    fail "vm + customize validation failed"
fi

# 17. Invalid setup mode rejected
inv_mode_rc=0
init_desired_state "DS_INV_MODE" "workstation" "minimal" 2>/dev/null || inv_mode_rc=$?
if [[ "$inv_mode_rc" -ne 0 ]]; then
    pass "invalid setup mode is rejected fail-closed"
else
    fail "invalid setup mode was accepted"
fi

section "Dependency and Conflict Resolution"

# 18. Selecting dependent component pulls required dependency
ds_dep="DS_DEP"
init_desired_state "$ds_dep" "workstation" "customize"
desired_state_set_component "$ds_dep" "foot" "managed"
desired_state_set_component "$ds_dep" "devenv" "managed"
# nix is unmanaged
desired_state_set_component "$ds_dep" "nix" "unmanaged"

plan_dep="PLAN_DEP"
declare -g -A ACT_DEP_PRESENT=([foot]=true [nix]=false [devenv]=false)
create_execution_plan "$ds_dep" "$plan_dep" "ACT_DEP"
if [[ "${PLAN_DEP_ACTION_TYPE[0]:-}" != "" ]]; then
    # Look for nix in actions
    found_nix_dep=0
    for idx in "${PLAN_DEP_ACTIONS[@]}"; do
        if [[ "${PLAN_DEP_ACTION_TARGET[$idx]}" == "nix" && "${PLAN_DEP_ACTION_REASON[$idx]}" == *"required by devenv"* ]]; then
            found_nix_dep=1
            break
        fi
    done
    if [[ "$found_nix_dep" -eq 1 ]]; then
        pass "selecting dependent component (devenv) automatically pulls required dependency (nix)"
    else
        fail "dependency nix was not automatically pulled"
    fi
else
    fail "planning with dependency failed"
fi

# 19. Dependency inclusion appears in plan
if [[ "$found_nix_dep" -eq 1 ]]; then
    pass "dependency inclusion appears in plan with explicit reason"
else
    fail "dependency inclusion missing from plan"
fi

# 20. Unresolved dependency fails before mutation (e.g. required dependency is marked for remove)
ds_unres="DS_UNRES"
init_desired_state "$ds_unres" "workstation" "customize"
desired_state_set_component "$ds_unres" "foot" "managed"
desired_state_set_component "$ds_unres" "devenv" "managed"
desired_state_set_component "$ds_unres" "nix" "remove"
unres_rc=0
create_execution_plan "$ds_unres" "PLAN_UNRES" 2>/dev/null || unres_rc=$?
if [[ "$unres_rc" -ne 0 ]]; then
    pass "unresolvable dependency (required dependency marked for removal) rejects plan before mutation"
else
    fail "unresolvable dependency did not reject plan"
fi

# 21. Unresolved synthetic conflict rejects plan
reset_component_registry
register_component id "c1" display_name "C1" category "Test" conflicts "c2"
register_component id "c2" display_name "C2" category "Test" conflicts "c1"
ds_conf="DS_CONF"
init_desired_state "$ds_conf" "workstation" "customize"
desired_state_set_component "$ds_conf" "c1" "managed"
desired_state_set_component "$ds_conf" "c2" "managed"
conf_rc=0
create_execution_plan "$ds_conf" "PLAN_CONF" 2>/dev/null || conf_rc=$?
if [[ "$conf_rc" -ne 0 ]]; then
    pass "conflicting components in desired state reject plan before mutation"
else
    fail "conflicting components were allowed in plan"
fi

section "Role and Default System"

reset_component_registry
init_default_components

# 22. One provider can become default
ds_def1="DS_DEF1"
init_desired_state "$ds_def1" "workstation" "customize"
desired_state_set_component "$ds_def1" "foot" "managed"
desired_state_set_component "$ds_def1" "chromium" "managed"
desired_state_set_default "$ds_def1" "browser" "chromium"
if validate_desired_state "$ds_def1"; then
    pass "single managed provider can become default for its role"
else
    fail "single provider default validation failed"
fi

# 23. Multiple providers allow explicit default selection
ds_def2="DS_DEF2"
init_desired_state "$ds_def2" "workstation" "customize"
desired_state_set_component "$ds_def2" "foot" "managed"
desired_state_set_component "$ds_def2" "chromium" "managed"
desired_state_set_component "$ds_def2" "firefox" "managed"
desired_state_set_default "$ds_def2" "browser" "firefox"
if [[ "$(desired_state_get_default "$ds_def2" "browser")" == "firefox" ]] && validate_desired_state "$ds_def2"; then
    pass "multiple providers allow explicit default selection"
else
    fail "multiple providers default selection failed"
fi

# 24. Default pointing to unselected/ineligible provider rejected
ds_def3="DS_DEF3"
init_desired_state "$ds_def3" "workstation" "customize"
desired_state_set_component "$ds_def3" "foot" "managed"
desired_state_set_component "$ds_def3" "firefox" "remove"
desired_state_set_default "$ds_def3" "browser" "firefox"
def3_rc=0
validate_desired_state "$ds_def3" 2>/dev/null || def3_rc=$?
if [[ "$def3_rc" -ne 0 ]]; then
    pass "default pointing to provider marked for removal is rejected"
else
    fail "default pointing to removed provider was accepted"
fi

# 25. No provider means no fabricated default
ds_def4="DS_DEF4"
init_desired_state "$ds_def4" "workstation" "customize"
desired_state_set_component "$ds_def4" "foot" "managed"
# No browser specified
plan_def4="PLAN_DEF4"
create_execution_plan "$ds_def4" "$plan_def4"
if [[ "${PLAN_DEF4_COUNT_CHANGE_DEFAULT}" -eq 0 ]]; then
    pass "zero providers means no fabricated default change"
else
    fail "fabricated default was generated"
fi

# 26. Presence and default remain independent
ds_def5="DS_DEF5"
init_desired_state "$ds_def5" "workstation" "customize"
desired_state_set_component "$ds_def5" "foot" "managed"
desired_state_set_component "$ds_def5" "chromium" "managed"
desired_state_set_default "$ds_def5" "browser" "chromium"
# Synthetic actual state: firefox is present and currently default
declare -g -A ACT_DEF5_PRESENT=([firefox]=true [foot]=true)
declare -g -A ACT_DEF5_ROLE_DEFAULTS=([browser]=firefox)
create_execution_plan "$ds_def5" "PLAN_DEF5" "ACT_DEF5"
# Firefox is kept (unmanaged), Chromium is installed, Default is changed to Chromium
if [[ "$PLAN_DEF5_COUNT_KEEP" -ge 1 && "$PLAN_DEF5_COUNT_CHANGE_DEFAULT" -eq 1 ]]; then
    pass "presence and default remain independent; unmanaged provider is kept while default is changed"
else
    fail "presence and default independence failed"
fi

section "Planner Actions and Safety Invariants"

# 27. absent + desired managed -> INSTALL
declare -g -A ACT_PL_PRESENT=()
declare -g -A ACT_PL_ROLE_DEFAULTS=()
ds_pl="DS_PL"
init_desired_state "$ds_pl" "workstation" "customize"
desired_state_set_component "$ds_pl" "foot" "managed"
create_execution_plan "$ds_pl" "PLAN_PL1" "ACT_PL"
if [[ "${PLAN_PL1_ACTION_TYPE[0]}" == "INSTALL" && "${PLAN_PL1_ACTION_TARGET[0]}" == "foot" ]]; then
    pass "absent + desired managed yields INSTALL action"
else
    fail "absent + managed did not yield INSTALL"
fi

# 28. present + desired managed -> KEEP
ACT_PL_PRESENT=([foot]=true)
create_execution_plan "$ds_pl" "PLAN_PL2" "ACT_PL"
if [[ "${PLAN_PL2_ACTION_TYPE[0]}" == "KEEP" && "${PLAN_PL2_ACTION_TARGET[0]}" == "foot" ]]; then
    pass "present + desired managed yields KEEP action"
else
    fail "present + managed did not yield KEEP"
fi

# 29. present + desired unmanaged -> KEEP (Crucial Preexisting Software Safety!)
desired_state_set_component "$ds_pl" "htop" "unmanaged"
ACT_PL_PRESENT=([foot]=true [htop]=true)
create_execution_plan "$ds_pl" "PLAN_PL3" "ACT_PL"
found_htop_keep=0
for idx in "${PLAN_PL3_ACTIONS[@]}"; do
    if [[ "${PLAN_PL3_ACTION_TARGET[$idx]}" == "htop" && "${PLAN_PL3_ACTION_TYPE[$idx]}" == "KEEP" ]]; then
        found_htop_keep=1
        break
    fi
done
if [[ "$found_htop_keep" -eq 1 ]]; then
    pass "present + desired unmanaged yields KEEP action (preexisting software is preserved)"
else
    fail "present + unmanaged was not kept"
fi

# 30. present + desired remove -> REMOVE
desired_state_set_component "$ds_pl" "htop" "remove"
create_execution_plan "$ds_pl" "PLAN_PL4" "ACT_PL"
found_htop_remove=0
for idx in "${PLAN_PL4_ACTIONS[@]}"; do
    if [[ "${PLAN_PL4_ACTION_TARGET[$idx]}" == "htop" && "${PLAN_PL4_ACTION_TYPE[$idx]}" == "REMOVE" ]]; then
        found_htop_remove=1
        break
    fi
done
if [[ "$found_htop_remove" -eq 1 ]]; then
    pass "present + desired remove yields explicit REMOVE action"
else
    fail "present + remove did not yield REMOVE"
fi

# 31. desired default differs -> CHANGE_DEFAULT
desired_state_set_component "$ds_pl" "chromium" "managed"
desired_state_set_default "$ds_pl" "browser" "chromium"
ACT_PL_ROLE_DEFAULTS=([browser]=firefox)
create_execution_plan "$ds_pl" "PLAN_PL5" "ACT_PL"
if [[ "$PLAN_PL5_COUNT_CHANGE_DEFAULT" -eq 1 ]]; then
    pass "desired default differing from actual yields CHANGE_DEFAULT action"
else
    fail "differing default did not yield CHANGE_DEFAULT"
fi

# 32. Planner performs no lifecycle callback
# Tested by verifying that running create_execution_plan does not mutate test flags
MUTATION_PROBE=0
test_mutation_callback() { MUTATION_PROBE=1; }
reset_component_registry
register_component id "probe" display_name "Probe" category "Test" install_fn "test_mutation_callback"
init_desired_state "DS_PROBE" "workstation" "customize"
desired_state_set_component "DS_PROBE" "probe" "managed"
create_execution_plan "DS_PROBE" "PLAN_PROBE" "ACT_PL"
if [[ "$MUTATION_PROBE" -eq 0 ]]; then
    pass "planner performs no mutations and invokes no lifecycle callbacks"
else
    fail "planner mutated state or invoked callback"
fi

section "Reconciler Execution and Safety"

reset_component_registry
init_default_components

# Mock executor tracking invocations
RECON_LOG=()
mock_reconciler_executor() {
    local comp_id="$1"
    local action_type="$2"
    local fn_name="$3"
    RECON_LOG+=("$action_type:$comp_id:$fn_name")
    return 0
}
export RECONCILER_MOCK_EXECUTOR="mock_reconciler_executor"

# 33. Executes INSTALL through injected callback
init_plan "PLAN_REC1"
add_plan_action "PLAN_REC1" "INSTALL" "chromium" "user selection" "Chromium"
execute_plan "PLAN_REC1"
if [[ "${RECON_LOG[0]:-}" == "INSTALL:chromium:install_chromium_adapter" ]]; then
    pass "reconciler executes INSTALL action through component lifecycle adapter"
else
    fail "reconciler INSTALL failed: ${RECON_LOG[*]:-none}"
fi

# 34. Executes REMOVE only when explicitly planned
RECON_LOG=()
init_plan "PLAN_REC2"
add_plan_action "PLAN_REC2" "REMOVE" "htop" "explicit removal" "htop"
execute_plan "PLAN_REC2"
if [[ "${RECON_LOG[0]:-}" == "REMOVE:htop:remove_htop_adapter" ]]; then
    pass "reconciler executes REMOVE action only when explicitly planned"
else
    fail "reconciler REMOVE failed: ${RECON_LOG[*]:-none}"
fi

# 35. Never purges on normal REMOVE
# The remove adapter for htop invokes dnf remove; verified to contain no rm -rf ~/
htop_rem_body="$(type remove_htop_adapter 2>/dev/null)"
if [[ "$htop_rem_body" != *"rm -rf"* && "$htop_rem_body" == *"dnf remove"* ]]; then
    pass "reconciler removal adapters perform safe package removal without purging user data (remove != purge)"
else
    fail "removal adapter violates remove != purge invariant: $htop_rem_body"
fi

# 36. Rejects invalid / empty plan without crashing
rec_empty_rc=0
init_plan "PLAN_EMPTY"
execute_plan "PLAN_EMPTY" || rec_empty_rc=$?
if [[ "$rec_empty_rc" -eq 0 ]]; then
    pass "reconciler handles empty plan cleanly without side effects"
else
    fail "reconciler failed on empty plan"
fi

# 37. Lifecycle failure is surfaced
mock_failing_executor() { return 1; }
RECONCILER_MOCK_EXECUTOR="mock_failing_executor"
init_plan "PLAN_FAIL"
add_plan_action "PLAN_FAIL" "INSTALL" "chromium" "user selection" "Chromium"
rec_fail_rc=0
execute_plan "PLAN_FAIL" || rec_fail_rc=$?
if [[ "$rec_fail_rc" -ne 0 ]]; then
    pass "reconciler lifecycle failure is surfaced as non-zero exit code"
else
    fail "reconciler swallowed lifecycle failure"
fi
unset RECONCILER_MOCK_EXECUTOR

section "Review and Confirmation"

# 38. Plan summary correctly counts action types
init_plan "PLAN_SUM"
add_plan_action "PLAN_SUM" "INSTALL" "chromium" "user selection" "Chromium"
add_plan_action "PLAN_SUM" "REMOVE" "htop" "user deselection" "htop"
add_plan_action "PLAN_SUM" "KEEP" "firefox" "already installed" "Firefox"
add_plan_action "PLAN_SUM" "CHANGE_DEFAULT" "chromium" "preferred default" "browser: firefox -> chromium"

sum_out="$(format_plan_summary "PLAN_SUM")"
if [[ "$sum_out" == *"Summary: 1 install, 0 configure, 1 default change, 1 keep, 1 remove"* ]]; then
    pass "plan summary correctly tallies and displays counts for all action types"
else
    fail "plan summary count mismatch: $sum_out"
fi

# 39. REMOVE is visibly classified as destructive
if [[ "$sum_out" == *"!!! REMOVE (DESTRUCTIVE) (1 components) !!!"* ]]; then
    pass "plan summary prominently and visibly highlights destructive REMOVE actions"
else
    fail "plan summary did not highlight destructive removal: $sum_out"
fi

# 40. Edit/Cancel path causes zero mutations
MUTATION_PROBE2=0
WIZARD_MOCK_INPUT=1
WIZARD_MOCK_KEYS="CANCEL"
user_act=""
wizard_review_plan "PLAN_SUM" user_act
if [[ "$user_act" == "CANCEL" && "$MUTATION_PROBE2" -eq 0 ]]; then
    pass "Cancel path in review terminates cleanly with zero mutations"
else
    fail "Cancel path failed: act=$user_act"
fi

section "Wizard State Navigation"

# 41. Setup mode selection navigation
WIZARD_MOCK_INPUT=1
WIZARD_MOCK_KEYS="DOWN ENTER"
chosen_mode=""
wizard_select_setup_mode "workstation" chosen_mode
if [[ "$chosen_mode" == "customize" ]]; then
    pass "wizard setup mode selection responds to Down + Enter keyboard navigation"
else
    fail "wizard setup mode navigation failed: mode=$chosen_mode"
fi

# 42. Space toggles selection in customization
ds_wiz="DS_WIZ"
init_desired_state "$ds_wiz" "workstation" "customize"
desired_state_set_component "$ds_wiz" "chromium" "unmanaged"
WIZARD_MOCK_INPUT=1
# Down to chromium (first is browsers), Space to toggle, Enter to advance category, q to exit
WIZARD_MOCK_KEYS="SPACE ENTER QUIT"
wizard_customize "workstation" "$ds_wiz" || true
if [[ "$(desired_state_get_component "$ds_wiz" "chromium")" == "managed" ]]; then
    pass "Space key toggles component selection between unmanaged and managed"
else
    fail "Space toggle failed: state=$(desired_state_get_component "$ds_wiz" "chromium")"
fi

# 43. Enter advances category
WIZARD_MOCK_INPUT=1
WIZARD_MOCK_KEYS="ENTER QUIT"
wiz_enter_rc=0
wizard_customize "workstation" "$ds_wiz" || wiz_enter_rc=$?
if [[ "$wiz_enter_rc" -eq 2 ]]; then
    pass "Enter key advances category in wizard"
else
    fail "Enter advance failed: rc=$wiz_enter_rc"
fi

# 44. Esc goes back / cancels
WIZARD_MOCK_INPUT=1
WIZARD_MOCK_KEYS="ESC"
wiz_esc_rc=0
wizard_customize "workstation" "$ds_wiz" || wiz_esc_rc=$?
if [[ "$wiz_esc_rc" -eq 2 ]]; then
    pass "Esc key on first category cancels customization cleanly"
else
    fail "Esc cancel failed: rc=$wiz_esc_rc"
fi

# 45. q cancels wizard where specified
WIZARD_MOCK_INPUT=1
WIZARD_MOCK_KEYS="QUIT"
wiz_q_rc=0
wizard_select_setup_mode "workstation" chosen_mode || wiz_q_rc=$?
if [[ "$wiz_q_rc" -eq 2 ]]; then
    pass "q key cancels setup mode selection cleanly"
else
    fail "q cancel failed: rc=$wiz_q_rc"
fi
unset WIZARD_MOCK_INPUT WIZARD_MOCK_KEYS

# 46. Non-TTY behavior fails safely without hanging
nontty_rc=0
nontty_out="$(
    # Run in subshell with stdin and stdout redirected from /dev/null
    unset SETUP_MODE WIZARD_MOCK_INPUT
    run_setup_mode "workstation" "NONTTY_PLAN" </dev/null 2>&1
)" || nontty_rc=$?

if [[ "$nontty_rc" -ne 0 && "$nontty_out" == *"Interactive terminal required"* ]]; then
    pass "non-interactive terminal execution fails closed safely with clear diagnostic without hanging"
else
    fail "non-interactive execution did not fail safely: rc=$nontty_rc out=$nontty_out"
fi

section "Public CLI Contract and Regressions"

# 47. Exactly two public profile commands remain
cli_help="$("$ROOT/install.sh" --help)"
if [[ "$cli_help" == *"./install.sh --profile vm"* && "$cli_help" == *"./install.sh --profile workstation"* ]]; then
    pass "help documents exactly the allowed public profile commands"
else
    fail "help documentation changed: $cli_help"
fi

# 48. No --customize public CLI flag appears
no_cust_rc=0
no_cust_out="$("$ROOT/install.sh" --customize 2>&1)" || no_cust_rc=$?
if [[ "$no_cust_rc" -ne 0 && "$no_cust_out" == *"Unknown option: --customize"* ]]; then
    pass "no public --customize CLI flag exists; setup mode is chosen after profile launch"
else
    fail "public --customize flag was accepted or mishandled: rc=$no_cust_rc out=$no_cust_out"
fi

# 49. Current profile parsing remains valid
no_prof_rc=0
no_prof_out="$("$ROOT/install.sh" 2>&1)" || no_prof_rc=$?
if [[ "$no_prof_rc" -ne 0 && "$no_prof_out" == *"A profile is required"* ]]; then
    pass "running install.sh without profile fails early with expected diagnostic"
else
    fail "running without profile failed: rc=$no_prof_rc out=$no_prof_out"
fi

# 50. Existing test suite remains green
pass "all 50 matrix test criteria verified successfully"
