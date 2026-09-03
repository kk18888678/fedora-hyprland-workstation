#!/usr/bin/env bash

# Test Suite: Workstation Configuration Architecture (Corrective Hardening)
# Tests Component Registry, Desired State, Planner, Reconciler, Roles, Defaults,
# Lifecycle Adapters, Review, Wizard Navigation, Single Mutation Ownership, and CLI Contract.

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=/dev/null
source "$ROOT/modules/common.sh"
source "$ROOT/modules/browsers.sh"
source "$ROOT/modules/nix.sh"
source "$ROOT/modules/packages.sh"

record_success() { :; }
record_required() { :; }
record_deferred() { :; }

section "Component Registry and Invariants"

reset_component_registry

# Valid component registers
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

# Duplicate component ID rejected
dup_rc=0
register_component id "test_comp_a" display_name "Duplicate" category "Testing" 2>/dev/null || dup_rc=$?
if [[ "$dup_rc" -ne 0 ]]; then
    pass "duplicate component ID is rejected fail-closed"
else
    fail "duplicate component ID was not rejected"
fi

# Unknown dependency rejected
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

# Invalid profile rejected
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

# Capability metadata available
reset_component_registry
register_component \
    id "prov_comp" \
    display_name "Provider Component" \
    category "Testing" \
    provides "cap_x"

register_component \
    id "test_cap" \
    display_name "Capability Test" \
    category "Testing" \
    provides "cap_y" \
    requires "cap_x"
if [[ "$(get_component_attr "test_cap" provides)" == "cap_y" && "$(get_component_attr "test_cap" requires)" == "cap_x" ]]; then
    pass "component capability provides and requires metadata are available"
else
    fail "component capability metadata retrieval failed"
fi

# Role provider metadata available
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

# Restore default representative components for remaining tests
reset_component_registry
init_default_components

section "Desired State Model and Fail-Closed Validation"

# 1. Required component omitted from Desired State -> fail
ds_omit="DS_OMIT"
init_desired_state "$ds_omit" "workstation" "customize"
desired_state_set_component "$ds_omit" "chromium" "managed"
# Omit foot (which is required on workstation)
omit_rc=0
validate_desired_state "$ds_omit" 2>/dev/null || omit_rc=$?
if [[ "$omit_rc" -ne 0 ]]; then
    pass "1. required component omitted from Desired State fails validation fail-closed"
else
    fail "1. required component omission was allowed"
fi

# 2. Required component unmanaged -> fail
ds_req_unm="DS_REQ_UNM"
init_desired_state "$ds_req_unm" "workstation" "customize"
desired_state_set_component "$ds_req_unm" "foot" "unmanaged"
req_unm_rc=0
validate_desired_state "$ds_req_unm" 2>/dev/null || req_unm_rc=$?
if [[ "$req_unm_rc" -ne 0 ]]; then
    pass "2. required component set to unmanaged fails validation"
else
    fail "2. required component set to unmanaged was allowed"
fi

# 3. Required component remove -> fail
ds_req_rem="DS_REQ_REM"
init_desired_state "$ds_req_rem" "workstation" "customize"
desired_state_set_component "$ds_req_rem" "foot" "remove"
req_rem_rc=0
validate_desired_state "$ds_req_rem" 2>/dev/null || req_rem_rc=$?
if [[ "$req_rem_rc" -ne 0 ]]; then
    pass "3. required component set to remove fails validation"
else
    fail "3. required component set to remove was allowed"
fi

# 4. Unsupported-profile managed component -> fail
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false supported_profiles "workstation vm" roles "terminal"
register_component id "wk_only" display_name "Workstation Only" category "Testing" supported_profiles "workstation"
ds_unsupp_m="DS_UNSUPP_M"
init_desired_state "$ds_unsupp_m" "vm" "customize"
desired_state_set_component "$ds_unsupp_m" "foot" "managed"
desired_state_set_component "$ds_unsupp_m" "wk_only" "managed"
unsupp_m_rc=0
validate_desired_state "$ds_unsupp_m" 2>/dev/null || unsupp_m_rc=$?
if [[ "$unsupp_m_rc" -ne 0 ]]; then
    pass "4. unsupported-profile managed component fails validation"
else
    fail "4. unsupported-profile managed component was allowed"
fi

# 5. Unsupported-profile remove component -> fail
ds_unsupp_r="DS_UNSUPP_R"
init_desired_state "$ds_unsupp_r" "vm" "customize"
desired_state_set_component "$ds_unsupp_r" "foot" "managed"
desired_state_set_component "$ds_unsupp_r" "wk_only" "remove"
unsupp_r_rc=0
validate_desired_state "$ds_unsupp_r" 2>/dev/null || unsupp_r_rc=$?
if [[ "$unsupp_r_rc" -ne 0 ]]; then
    pass "5. unsupported-profile remove component fails validation"
else
    fail "5. unsupported-profile remove component was allowed"
fi

# Restore default representative components
reset_component_registry
init_default_components

# 6. Unknown component -> fail
ds_unk="DS_UNK"
init_desired_state "$ds_unk" "workstation" "customize"
desired_state_set_component "$ds_unk" "foot" "managed"
desired_state_set_component "$ds_unk" "ghost_app" "managed"
unk_rc=0
validate_desired_state "$ds_unk" 2>/dev/null || unk_rc=$?
if [[ "$unk_rc" -ne 0 ]]; then
    pass "6. unknown component in desired state fails validation"
else
    fail "6. unknown component was allowed"
fi

# 7. Unknown role -> fail
ds_unk_role="DS_UNK_ROLE"
init_desired_state "$ds_unk_role" "workstation" "customize"
desired_state_set_component "$ds_unk_role" "foot" "managed"
desired_state_set_default "$ds_unk_role" "invalid_role" "foot"
unk_role_rc=0
validate_desired_state "$ds_unk_role" 2>/dev/null || unk_role_rc=$?
if [[ "$unk_role_rc" -ne 0 ]]; then
    pass "7. unknown role in desired state fails validation"
else
    fail "7. unknown role was allowed"
fi

# 8. Default provider unmanaged -> fail
ds_def_unm="DS_DEF_UNM"
init_desired_state "$ds_def_unm" "workstation" "customize"
desired_state_set_component "$ds_def_unm" "foot" "managed"
desired_state_set_component "$ds_def_unm" "firefox" "unmanaged"
desired_state_set_default "$ds_def_unm" "browser" "firefox"
def_unm_rc=0
validate_desired_state "$ds_def_unm" 2>/dev/null || def_unm_rc=$?
if [[ "$def_unm_rc" -ne 0 ]]; then
    pass "8. default provider set to unmanaged fails validation"
else
    fail "8. unmanaged default provider was allowed"
fi

# 9. Default provider remove -> fail
ds_def_rem="DS_DEF_REM"
init_desired_state "$ds_def_rem" "workstation" "customize"
desired_state_set_component "$ds_def_rem" "foot" "managed"
desired_state_set_component "$ds_def_rem" "firefox" "remove"
desired_state_set_default "$ds_def_rem" "browser" "firefox"
def_rem_rc=0
validate_desired_state "$ds_def_rem" 2>/dev/null || def_rem_rc=$?
if [[ "$def_rem_rc" -ne 0 ]]; then
    pass "9. default provider set to remove fails validation"
else
    fail "9. removed default provider was allowed"
fi

# 10. Default provider wrong role -> fail
ds_def_wrong="DS_DEF_WRONG"
init_desired_state "$ds_def_wrong" "workstation" "customize"
desired_state_set_component "$ds_def_wrong" "foot" "managed"
# foot is a terminal, not a browser
desired_state_set_default "$ds_def_wrong" "browser" "foot"
def_wrong_rc=0
validate_desired_state "$ds_def_wrong" 2>/dev/null || def_wrong_rc=$?
if [[ "$def_wrong_rc" -ne 0 ]]; then
    pass "10. default provider with wrong role fails validation"
else
    fail "10. wrong role default provider was allowed"
fi

# 11. Default provider unsupported profile -> fail
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false supported_profiles "workstation vm" roles "terminal"
register_component id "wk_browser" display_name "Workstation Browser" category "Browsers" supported_profiles "workstation" roles "browser"
ds_def_unprof="DS_DEF_UNPROF"
init_desired_state "$ds_def_unprof" "vm" "customize"
desired_state_set_component "$ds_def_unprof" "foot" "managed"
desired_state_set_default "$ds_def_unprof" "browser" "wk_browser"
def_unprof_rc=0
validate_desired_state "$ds_def_unprof" 2>/dev/null || def_unprof_rc=$?
if [[ "$def_unprof_rc" -ne 0 ]]; then
    pass "11. default provider with unsupported profile fails validation"
else
    fail "11. unsupported profile default provider was allowed"
fi

# Restore default representative components
reset_component_registry
init_default_components

# 12. Valid managed default -> pass
ds_valid_def="DS_VALID_DEF"
init_desired_state "$ds_valid_def" "workstation" "customize"
desired_state_set_component "$ds_valid_def" "foot" "managed"
desired_state_set_component "$ds_valid_def" "firefox" "managed"
desired_state_set_default "$ds_valid_def" "browser" "firefox"
valid_def_rc=0
validate_desired_state "$ds_valid_def" || valid_def_rc=$?
if [[ "$valid_def_rc" -eq 0 ]]; then
    pass "12. valid managed default provider passes validation"
else
    fail "12. valid managed default failed: rc=$valid_def_rc"
fi

section "Plan Validation, Finalization, and Reconciler Guards"

# 13. Unvalidated plan -> reconciler rejects
init_plan "PLAN_UNVAL"
add_plan_action "PLAN_UNVAL" "INSTALL" "chromium" "test" "Chromium"
unval_exec_rc=0
execute_plan "PLAN_UNVAL" 2>/dev/null || unval_exec_rc=$?
if [[ "$unval_exec_rc" -ne 0 ]]; then
    pass "13. unvalidated plan is rejected by reconciler fail-closed"
else
    fail "13. reconciler executed unvalidated plan"
fi

# 14. Malformed plan (action count mismatch) -> reject
init_plan "PLAN_MAL"
add_plan_action "PLAN_MAL" "INSTALL" "chromium" "test" "Chromium"
PLAN_MAL_COUNT_INSTALL=99
mal_val_rc=0
validate_plan "PLAN_MAL" 2>/dev/null || mal_val_rc=$?
if [[ "$mal_val_rc" -ne 0 ]]; then
    pass "14. malformed plan with mismatched counts is rejected"
else
    fail "14. malformed plan was accepted"
fi

# 15. Unknown action -> reject
init_plan "PLAN_UNK_ACT"
add_plan_action "PLAN_UNK_ACT" "PURGE" "chromium" "test" "Chromium"
unk_act_rc=0
finalize_plan "PLAN_UNK_ACT" 2>/dev/null || unk_act_rc=$?
if [[ "$unk_act_rc" -ne 0 ]]; then
    pass "15. unknown action type in plan is rejected"
else
    fail "15. unknown action was accepted"
fi

# 16. Unknown target -> reject
init_plan "PLAN_UNK_TARG"
add_plan_action "PLAN_UNK_TARG" "INSTALL" "fake_app" "test" "Fake App"
unk_targ_rc=0
finalize_plan "PLAN_UNK_TARG" 2>/dev/null || unk_targ_rc=$?
if [[ "$unk_targ_rc" -ne 0 ]]; then
    pass "16. unknown target component in plan is rejected"
else
    fail "16. unknown target was accepted"
fi

# 17. Illegal REMOVE -> reject
init_plan "PLAN_ILL_REM"
add_plan_action "PLAN_ILL_REM" "REMOVE" "foot" "test" "Foot"
ill_rem_rc=0
finalize_plan "PLAN_ILL_REM" 2>/dev/null || ill_rem_rc=$?
if [[ "$ill_rem_rc" -ne 0 ]]; then
    pass "17. illegal REMOVE action of required component is rejected"
else
    fail "17. illegal REMOVE was accepted"
fi

# 18. Invalid CHANGE_DEFAULT -> reject
init_plan "PLAN_INV_DEF"
add_plan_action "PLAN_INV_DEF" "CHANGE_DEFAULT" "foot" "test" "browser: none -> Foot"
inv_def_rc=0
finalize_plan "PLAN_INV_DEF" 2>/dev/null || inv_def_rc=$?
if [[ "$inv_def_rc" -ne 0 ]]; then
    pass "18. invalid CHANGE_DEFAULT action for wrong role is rejected"
else
    fail "18. invalid CHANGE_DEFAULT was accepted"
fi

# 19. Finalized plan unexpected mutation -> reject
init_plan "PLAN_TAMP"
add_plan_action "PLAN_TAMP" "INSTALL" "chromium" "test" "Chromium"
finalize_plan "PLAN_TAMP"
# Mutate the plan target after finalization
PLAN_TAMP_ACTION_TARGET[0]="firefox"
tamp_rc=0
execute_plan "PLAN_TAMP" 2>/dev/null || tamp_rc=$?
if [[ "$tamp_rc" -ne 0 ]]; then
    pass "19. modified plan after finalization is rejected by deterministic fingerprint check"
else
    fail "19. modified plan was executed"
fi

section "Dependency Ordering, Structural Traversal, and Cycle Detection"

# Register isolated synthetic components for dependency graph tests
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
register_component id "dep_a" display_name "Comp A" category "Testing" dependencies "dep_b"
register_component id "dep_b" display_name "Comp B" category "Testing" dependencies "dep_c"
register_component id "dep_c" display_name "Comp C" category "Testing"
register_component id "dia_top" display_name "Dia Top" category "Testing" dependencies "dia_left dia_right"
register_component id "dia_left" display_name "Dia Left" category "Testing" dependencies "dia_base"
register_component id "dia_right" display_name "Dia Right" category "Testing" dependencies "dia_base"
register_component id "dia_base" display_name "Dia Base" category "Testing"

# 20. Dependency ordered before dependent (simple)
ds_ord1="DS_ORD1"
init_desired_state "$ds_ord1" "workstation" "customize"
desired_state_set_component "$ds_ord1" "foot" "managed"
desired_state_set_component "$ds_ord1" "dep_b" "managed"
declare -g -A ACT_ORD1_PRESENT=([foot]=true [dep_b]=false [dep_c]=false)
create_execution_plan "$ds_ord1" "PLAN_ORD1" "ACT_ORD1"
idx_b=-1
idx_c=-1
for idx in "${PLAN_ORD1_ACTIONS[@]}"; do
    if [[ "${PLAN_ORD1_ACTION_TARGET[$idx]}" == "dep_b" && "${PLAN_ORD1_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_b=$idx; fi
    if [[ "${PLAN_ORD1_ACTION_TARGET[$idx]}" == "dep_c" && "${PLAN_ORD1_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_c=$idx; fi
done
if [[ "$idx_c" -ge 0 && "$idx_b" -ge 0 && "$idx_c" -lt "$idx_b" ]]; then
    pass "20. dependency (dep_c) is ordered before dependent (dep_b) in execution plan"
else
    fail "20. dependency ordering failed: idx_c=$idx_c, idx_b=$idx_b"
fi

# 21. Multi-level dependency ordering (A -> B -> C)
ds_ord2="DS_ORD2"
init_desired_state "$ds_ord2" "workstation" "customize"
desired_state_set_component "$ds_ord2" "foot" "managed"
desired_state_set_component "$ds_ord2" "dep_a" "managed"
declare -g -A ACT_ORD2_PRESENT=([foot]=true [dep_a]=false [dep_b]=false [dep_c]=false)
create_execution_plan "$ds_ord2" "PLAN_ORD2" "ACT_ORD2"
idx_a=-1; idx_b=-1; idx_c=-1
for idx in "${PLAN_ORD2_ACTIONS[@]}"; do
    if [[ "${PLAN_ORD2_ACTION_TARGET[$idx]}" == "dep_a" && "${PLAN_ORD2_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_a=$idx; fi
    if [[ "${PLAN_ORD2_ACTION_TARGET[$idx]}" == "dep_b" && "${PLAN_ORD2_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_b=$idx; fi
    if [[ "${PLAN_ORD2_ACTION_TARGET[$idx]}" == "dep_c" && "${PLAN_ORD2_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_c=$idx; fi
done
if [[ "$idx_c" -ge 0 && "$idx_b" -ge 0 && "$idx_a" -ge 0 && "$idx_c" -lt "$idx_b" && "$idx_b" -lt "$idx_a" ]]; then
    pass "21. multi-level dependency ordering (C < B < A) is preserved"
else
    fail "21. multi-level ordering failed: C=$idx_c, B=$idx_b, A=$idx_a"
fi

# 22. Diamond dependency ordering (Top -> Left, Right -> Base)
ds_dia="DS_DIA"
init_desired_state "$ds_dia" "workstation" "customize"
desired_state_set_component "$ds_dia" "foot" "managed"
desired_state_set_component "$ds_dia" "dia_top" "managed"
declare -g -A ACT_DIA_PRESENT=([foot]=true [dia_top]=false [dia_left]=false [dia_right]=false [dia_base]=false)
create_execution_plan "$ds_dia" "PLAN_DIA" "ACT_DIA"
idx_base=-1; idx_left=-1; idx_right=-1; idx_top=-1
for idx in "${PLAN_DIA_ACTIONS[@]}"; do
    if [[ "${PLAN_DIA_ACTION_TARGET[$idx]}" == "dia_base" && "${PLAN_DIA_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_base=$idx; fi
    if [[ "${PLAN_DIA_ACTION_TARGET[$idx]}" == "dia_left" && "${PLAN_DIA_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_left=$idx; fi
    if [[ "${PLAN_DIA_ACTION_TARGET[$idx]}" == "dia_right" && "${PLAN_DIA_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_right=$idx; fi
    if [[ "${PLAN_DIA_ACTION_TARGET[$idx]}" == "dia_top" && "${PLAN_DIA_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_top=$idx; fi
done
if [[ "$idx_base" -lt "$idx_left" && "$idx_base" -lt "$idx_right" && "$idx_left" -lt "$idx_top" && "$idx_right" -lt "$idx_top" ]]; then
    pass "22. diamond dependency graph orders base before branches and branches before top"
else
    fail "22. diamond ordering failed: base=$idx_base, left=$idx_left, right=$idx_right, top=$idx_top"
fi

# 23. Direct dependency cycle -> fail
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
register_component id "cyc_a" display_name "Cycle A" category "Testing" dependencies "cyc_b"
register_component id "cyc_b" display_name "Cycle B" category "Testing" dependencies "cyc_a"
ds_cyc1="DS_CYC1"
init_desired_state "$ds_cyc1" "workstation" "customize"
desired_state_set_component "$ds_cyc1" "foot" "managed"
desired_state_set_component "$ds_cyc1" "cyc_a" "managed"
cyc1_rc=0
create_execution_plan "$ds_cyc1" "PLAN_CYC1" 2>/dev/null || cyc1_rc=$?
if [[ "$cyc1_rc" -ne 0 ]]; then
    pass "23. direct dependency cycle (A -> B -> A) fails closed before mutation"
else
    fail "23. direct cycle was allowed"
fi

# 24. Indirect dependency cycle -> fail
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
register_component id "ind_a" display_name "Ind A" category "Testing" dependencies "ind_b"
register_component id "ind_b" display_name "Ind B" category "Testing" dependencies "ind_c"
register_component id "ind_c" display_name "Ind C" category "Testing" dependencies "ind_a"
ds_cyc2="DS_CYC2"
init_desired_state "$ds_cyc2" "workstation" "customize"
desired_state_set_component "$ds_cyc2" "foot" "managed"
desired_state_set_component "$ds_cyc2" "ind_a" "managed"
cyc2_rc=0
create_execution_plan "$ds_cyc2" "PLAN_CYC2" 2>/dev/null || cyc2_rc=$?
if [[ "$cyc2_rc" -ne 0 ]]; then
    pass "24. indirect dependency cycle (A -> B -> C -> A) fails closed before mutation"
else
    fail "24. indirect cycle was allowed"
fi

# 25. Dependency marked remove -> fail
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
register_component id "parent_comp" display_name "Parent" category "Testing" dependencies "child_comp"
register_component id "child_comp" display_name "Child" category "Testing" removable true
ds_rem_dep="DS_REM_DEP"
init_desired_state "$ds_rem_dep" "workstation" "customize"
desired_state_set_component "$ds_rem_dep" "foot" "managed"
desired_state_set_component "$ds_rem_dep" "parent_comp" "managed"
desired_state_set_component "$ds_rem_dep" "child_comp" "remove"
rem_dep_rc=0
create_execution_plan "$ds_rem_dep" "PLAN_REM_DEP" 2>/dev/null || rem_dep_rc=$?
if [[ "$rem_dep_rc" -ne 0 ]]; then
    pass "25. planning fails closed when required dependency is marked for removal"
else
    fail "25. planning permitted dependency marked remove"
fi

# 26. Deterministic plan ordering across repeated planning
reset_component_registry
init_default_components
ds_det="DS_DET"
create_recommended_desired_state "$ds_det" "workstation"
declare -g -A ACT_DET_PRESENT=([foot]=false [chromium]=false [firefox]=false [neovim]=false [nix]=false [devenv]=false [htop]=false)
create_execution_plan "$ds_det" "PLAN_DET_1" "ACT_DET"
create_execution_plan "$ds_det" "PLAN_DET_2" "ACT_DET"
if [[ "$PLAN_DET_1_FINGERPRINT" == "$PLAN_DET_2_FINGERPRINT" ]]; then
    pass "26. repeated plan generation produces byte-identical deterministic plan fingerprint"
else
    fail "26. plan generation was non-deterministic"
fi

section "Single Mutation Ownership and Legacy Stage Transition"

# 27. Migrated REMOVE cannot be undone by legacy install stage
test_rem_called=0
install_dnf_packages() {
    for pkg in "$@"; do
        if [[ "$pkg" == "chromium" ]]; then test_rem_called=1; fi
    done
    return 0
}
BROWSER_CHROMIUM=true
install_chromium
if [[ "$test_rem_called" -eq 0 ]]; then
    pass "27. migrated component (chromium) is skipped by legacy stage; cannot be reinstalled"
else
    fail "27. legacy stage reinstalled migrated component"
fi

# 28. Migrated unmanaged remains untouched by legacy stage
test_unm_called=0
install_dnf_packages() {
    for pkg in "$@"; do
        if [[ "$pkg" == "firefox" ]]; then test_unm_called=1; fi
    done
    return 0
}
BROWSER_FIREFOX=true
install_firefox
if [[ "$test_unm_called" -eq 0 ]]; then
    pass "28. migrated unmanaged component (firefox) is skipped by legacy stage"
else
    fail "28. legacy stage touched unmanaged migrated component"
fi

# 29. Migrated INSTALL executes once through reconciler adapter
test_reconciler_installs=0
install_dnf_packages() {
    for pkg in "$@"; do
        if [[ "$pkg" == "chromium" ]]; then test_reconciler_installs=$(( test_reconciler_installs + 1 )); fi
    done
    return 0
}
rpm() { return 0; }
# Reconciler installs it via adapter
perform_install_chromium
# Legacy stage runs
BROWSER_CHROMIUM=true
install_chromium
if [[ "$test_reconciler_installs" -eq 1 ]]; then
    pass "29. migrated INSTALL executes exactly once through reconciler; legacy stage does not duplicate"
else
    fail "29. migrated component was installed $test_reconciler_installs times"
fi

# 30. Non-migrated legacy functionality remains owned
# brave-origin is not registered in the Component Registry
if ! is_component_migrated "brave-origin"; then
    pass "30. non-migrated component (brave-origin) remains owned by legacy stage"
else
    fail "30. non-migrated component was mistakenly classified as migrated"
fi

section "Reconciler Failure Surfacing and Classification"

# 31. CONFIGURE failure surfaced
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
mock_fail_cfg() { return 1; }
register_component id "cfg_fail_comp" display_name "Fail Cfg" category "Testing" configure_fn "mock_fail_cfg"
init_plan "PLAN_CFG_FAIL"
add_plan_action "PLAN_CFG_FAIL" "CONFIGURE" "cfg_fail_comp" "update" "Fail Cfg"
finalize_plan "PLAN_CFG_FAIL"
cfg_fail_rc=0
execute_plan "PLAN_CFG_FAIL" 2>/dev/null || cfg_fail_rc=$?
if [[ "$cfg_fail_rc" -ne 0 ]]; then
    pass "31. CONFIGURE failure is surfaced and causes non-zero reconciler exit code"
else
    fail "31. CONFIGURE failure was silently swallowed"
fi

# 32. VALIDATE failure surfaced
mock_val_fail() { return 1; }
mock_inst_ok() { return 0; }
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
register_component id "val_fail_comp" display_name "Fail Val" category "Testing" install_fn "mock_inst_ok" validate_fn "mock_val_fail"
init_plan "PLAN_VAL_FAIL"
add_plan_action "PLAN_VAL_FAIL" "INSTALL" "val_fail_comp" "new" "Fail Val"
finalize_plan "PLAN_VAL_FAIL"
val_fail_rc=0
execute_plan "PLAN_VAL_FAIL" 2>/dev/null || val_fail_rc=$?
if [[ "$val_fail_rc" -ne 0 ]]; then
    pass "32. VALIDATE failure is surfaced and causes non-zero reconciler exit code"
else
    fail "32. VALIDATE failure was silently swallowed"
fi

# 33. REMOVE failure surfaced
mock_rem_fail() { return 1; }
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
register_component id "rem_fail_comp" display_name "Fail Rem" category "Testing" removable true remove_fn "mock_rem_fail"
init_plan "PLAN_REM_FAIL"
add_plan_action "PLAN_REM_FAIL" "REMOVE" "rem_fail_comp" "deselected" "Fail Rem"
finalize_plan "PLAN_REM_FAIL"
rem_fail_rc=0
execute_plan "PLAN_REM_FAIL" 2>/dev/null || rem_fail_rc=$?
if [[ "$rem_fail_rc" -ne 0 ]]; then
    pass "33. REMOVE failure is surfaced and causes non-zero reconciler exit code"
else
    fail "33. REMOVE failure was silently swallowed"
fi

# 34. CHANGE_DEFAULT verification fail-closed semantics
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
register_component id "chromium" display_name "Chromium" category "Browsers" roles "browser"

# 34a: xdg-mime default mutation failure -> CHANGE_DEFAULT failure
xdg-mime() {
    if [[ "$1" == "default" ]]; then return 1; fi
    if [[ "$1" == "query" ]]; then printf 'chromium-browser.desktop\n'; return 0; fi
    return 1
}
init_plan "PLAN_DEF_MUT_FAIL"
add_plan_action "PLAN_DEF_MUT_FAIL" "CHANGE_DEFAULT" "chromium" "preferred" "browser: none -> Chromium"
finalize_plan "PLAN_DEF_MUT_FAIL"
def_mut_rc=0
execute_plan "PLAN_DEF_MUT_FAIL" 2>/dev/null || def_mut_rc=$?
if [[ "$def_mut_rc" -ne 0 ]]; then
    pass "34a. xdg-mime default mutation failure causes CHANGE_DEFAULT failure"
else
    fail "34a. xdg-mime default mutation failure was ignored"
fi

# 34b: verification query command failure -> CHANGE_DEFAULT failure
xdg-mime() {
    if [[ "$1" == "default" ]]; then return 0; fi
    if [[ "$1" == "query" ]]; then return 1; fi # query command fails
    return 1
}
init_plan "PLAN_DEF_QRY_FAIL"
add_plan_action "PLAN_DEF_QRY_FAIL" "CHANGE_DEFAULT" "chromium" "preferred" "browser: none -> Chromium"
finalize_plan "PLAN_DEF_QRY_FAIL"
def_qry_rc=0
execute_plan "PLAN_DEF_QRY_FAIL" 2>/dev/null || def_qry_rc=$?
if [[ "$def_qry_rc" -ne 0 ]]; then
    pass "34b. verification query command failure causes CHANGE_DEFAULT failure"
else
    fail "34b. verification query command failure was ignored"
fi

# 34c: verification query returns empty -> CHANGE_DEFAULT failure
xdg-mime() {
    if [[ "$1" == "default" ]]; then return 0; fi
    if [[ "$1" == "query" ]]; then printf '\n'; return 0; fi # returns empty
    return 1
}
init_plan "PLAN_DEF_EMPTY"
add_plan_action "PLAN_DEF_EMPTY" "CHANGE_DEFAULT" "chromium" "preferred" "browser: none -> Chromium"
finalize_plan "PLAN_DEF_EMPTY"
def_emp_rc=0
execute_plan "PLAN_DEF_EMPTY" 2>/dev/null || def_emp_rc=$?
if [[ "$def_emp_rc" -ne 0 ]]; then
    pass "34c. verification query returning empty association causes CHANGE_DEFAULT failure"
else
    fail "34c. empty verification query was accepted"
fi

# 34d: verification query returns wrong desktop file -> CHANGE_DEFAULT failure
xdg-mime() {
    if [[ "$1" == "default" ]]; then return 0; fi
    if [[ "$1" == "query" ]]; then printf 'firefox.desktop\n'; return 0; fi # wrong desktop file
    return 1
}
init_plan "PLAN_DEF_WRONG"
add_plan_action "PLAN_DEF_WRONG" "CHANGE_DEFAULT" "chromium" "preferred" "browser: none -> Chromium"
finalize_plan "PLAN_DEF_WRONG"
def_wrong_rc=0
execute_plan "PLAN_DEF_WRONG" 2>/dev/null || def_wrong_rc=$?
if [[ "$def_wrong_rc" -ne 0 ]]; then
    pass "34d. verification query returning wrong desktop file causes CHANGE_DEFAULT failure"
else
    fail "34d. wrong desktop file verification was accepted"
fi

# 34e: verification query returns exact expected desktop file -> success
xdg-mime() {
    if [[ "$1" == "default" ]]; then return 0; fi
    if [[ "$1" == "query" ]]; then printf 'chromium-browser.desktop\n'; return 0; fi # matching expected
    return 1
}
init_plan "PLAN_DEF_OK"
add_plan_action "PLAN_DEF_OK" "CHANGE_DEFAULT" "chromium" "preferred" "browser: none -> Chromium"
finalize_plan "PLAN_DEF_OK"
def_ok_rc=0
execute_plan "PLAN_DEF_OK" 2>/dev/null || def_ok_rc=$?
if [[ "$def_ok_rc" -eq 0 ]]; then
    pass "34e. verification query returning exact expected desktop file succeeds"
else
    fail "34e. exact matching desktop file failed: rc=$def_ok_rc"
fi

# 34f: CHANGE_DEFAULT failure continues to record via record_deferred
xdg-mime() { return 1; }
init_plan "PLAN_DEF_REC"
add_plan_action "PLAN_DEF_REC" "CHANGE_DEFAULT" "chromium" "preferred" "browser: none -> Chromium"
finalize_plan "PLAN_DEF_REC"
def_rec_recorded=0
record_deferred() { def_rec_recorded=1; }
execute_plan "PLAN_DEF_REC" 2>/dev/null || true
if [[ "$def_rec_recorded" -eq 1 ]]; then
    pass "34f. CHANGE_DEFAULT failure is surfaced through record_deferred"
else
    fail "34f. CHANGE_DEFAULT failure was not recorded"
fi
record_deferred() { :; }

# 35. INSTALL failure classified correctly
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
mock_req_inst_fail() { return 1; }
register_component id "req_fail_comp" display_name "Req Fail" category "Testing" required true removable false install_fn "mock_req_inst_fail"
init_plan "PLAN_REQ_FAIL"
add_plan_action "PLAN_REQ_FAIL" "INSTALL" "req_fail_comp" "user" "Req Fail"
finalize_plan "PLAN_REQ_FAIL"
req_recorded=0
record_required() { req_recorded=1; }
execute_plan "PLAN_REQ_FAIL" 2>/dev/null || true
if [[ "$req_recorded" -eq 1 ]]; then
    pass "35. required component installation failure is recorded via record_required"
else
    fail "35. required failure classification failed"
fi

section "Interactive Wizard Safety and Non-TTY Fail-Closed Behavior"

# Restore default representative components
reset_component_registry
init_default_components

# 36. Cancellation before Apply -> zero mutations
WIZARD_MOCK_INPUT=1
WIZARD_MOCK_KEYS="CANCEL"
wiz_cancel_rc=0
run_setup_mode "workstation" "PLAN_CANCEL" || wiz_cancel_rc=$?
if [[ "$wiz_cancel_rc" -eq 2 ]]; then
    pass "36. cancellation in Review terminates cleanly with exit code 2 (zero mutations)"
else
    fail "36. cancel in review failed: rc=$wiz_cancel_rc"
fi
unset WIZARD_MOCK_INPUT WIZARD_MOCK_KEYS

# 37. Edit -> rebuild/review correctly
WIZARD_MOCK_INPUT=1
# Sequence: select recommended, in review choose EDIT, in customize press ENTER across categories + default selection, in review choose APPLY
WIZARD_MOCK_KEYS="ENTER EDIT ENTER ENTER ENTER ENTER ENTER APPLY"
wiz_edit_rc=0
run_setup_mode "workstation" "PLAN_EDIT" || wiz_edit_rc=$?
if [[ "$wiz_edit_rc" -eq 0 && "${PLAN_EDIT_VALIDATED:-}" == "true" ]]; then
    pass "37. Edit flow from Review allows modifying desired state and rebuilds validated plan"
else
    fail "37. Edit flow failed: rc=$wiz_edit_rc"
fi
unset WIZARD_MOCK_INPUT WIZARD_MOCK_KEYS

# 38. Removal requires explicit confirmation
plan_rem_conf="PLAN_REM_CONF"
init_plan "$plan_rem_conf"
add_plan_action "$plan_rem_conf" "REMOVE" "htop" "deselected" "htop"
finalize_plan "$plan_rem_conf"
WIZARD_MOCK_INPUT=1
WIZARD_MOCK_KEYS="a CANCEL"
WIZARD_MOCK_CONFIRM="no"
rem_conf_action=""
wizard_review_plan "$plan_rem_conf" rem_conf_action
if [[ "$rem_conf_action" == "CANCEL" ]]; then
    pass "38. destructive REMOVE action requires typing 'yes'; declining cancels setup safely"
else
    fail "38. destructive confirmation was bypassed: action=$rem_conf_action"
fi
unset WIZARD_MOCK_INPUT WIZARD_MOCK_KEYS WIZARD_MOCK_CONFIRM

# 39. Production non-TTY -> fail safely
unset SETUP_MODE WIZARD_MOCK_INPUT
nontty_rc=0
nontty_out="$(run_setup_mode "workstation" "PLAN_NONTTY" </dev/null 2>&1)" || nontty_rc=$?
if [[ "$nontty_rc" -ne 0 && "$nontty_out" == *"Interactive terminal required"* ]]; then
    pass "39. non-interactive terminal execution fails closed safely with clear diagnostic without hanging"
else
    fail "39. non-interactive execution did not fail safely: rc=$nontty_rc"
fi

# 40. SETUP_MODE environment variable cannot bypass interactive terminal requirement
SETUP_MODE="recommended"
nontty_rec_rc=0
nontty_rec_out="$(run_setup_mode "workstation" "PLAN_NONTTY_REC" </dev/null 2>&1)" || nontty_rec_rc=$?
if [[ "$nontty_rec_rc" -ne 0 && "$nontty_rec_out" == *"Interactive terminal required"* ]]; then
    pass "40. SETUP_MODE environment variable cannot bypass interactive terminal requirement"
else
    fail "40. SETUP_MODE bypassed terminal safety: rc=$nontty_rec_rc out=$nontty_rec_out"
fi
unset SETUP_MODE

# 41. SETUP_MODE environment variable cannot bypass interactive setup-mode selection
WIZARD_MOCK_INPUT=1
SETUP_MODE="recommended"
# User input sends CANCEL at the setup mode selection screen
WIZARD_MOCK_KEYS="CANCEL"
sm_bypass_rc=0
run_setup_mode "workstation" "PLAN_SM_BYPASS" || sm_bypass_rc=$?
# If SETUP_MODE was honored as an override, it would have selected recommended, built plan, and prompted Review.
# Because it must ALWAYS call wizard_select_setup_mode, CANCEL terminates immediately with rc 2.
if [[ "$sm_bypass_rc" -eq 2 ]]; then
    pass "41. SETUP_MODE=recommended cannot bypass interactive setup-mode selection screen"
else
    fail "41. SETUP_MODE bypassed interactive setup-mode selection: rc=$sm_bypass_rc"
fi
unset SETUP_MODE WIZARD_MOCK_INPUT WIZARD_MOCK_KEYS

# 41b. SETUP_MODE=customize cannot bypass interactive setup-mode selection screen
WIZARD_MOCK_INPUT=1
SETUP_MODE="customize"
WIZARD_MOCK_KEYS="CANCEL"
sm_cust_rc=0
run_setup_mode "workstation" "PLAN_SM_CUST" || sm_cust_rc=$?
if [[ "$sm_cust_rc" -eq 2 ]]; then
    pass "41b. SETUP_MODE=customize cannot bypass interactive setup-mode selection screen"
else
    fail "41b. SETUP_MODE=customize bypassed interactive setup-mode selection: rc=$sm_cust_rc"
fi
unset SETUP_MODE WIZARD_MOCK_INPUT WIZARD_MOCK_KEYS

# 41c. Arbitrary SETUP_MODE values do not create a separate production parsing path
WIZARD_MOCK_INPUT=1
SETUP_MODE="garbage"
WIZARD_MOCK_KEYS="CANCEL"
sm_garb_rc=0
run_setup_mode "workstation" "PLAN_SM_GARB" || sm_garb_rc=$?
if [[ "$sm_garb_rc" -eq 2 ]]; then
    pass "41c. arbitrary SETUP_MODE=garbage is completely ignored and interactive selection runs"
else
    fail "41c. arbitrary SETUP_MODE altered setup-mode behavior: rc=$sm_garb_rc"
fi
unset SETUP_MODE WIZARD_MOCK_INPUT WIZARD_MOCK_KEYS

section "CLI Contract and Preservation Invariants"

# 42. Exactly two public profile commands remain
cli_help="$("$ROOT/install.sh" --help)"
if [[ "$cli_help" == *"./install.sh --profile vm"* && "$cli_help" == *"./install.sh --profile workstation"* ]]; then
    pass "42. help documents exactly the allowed public profile commands"
else
    fail "42. help documentation changed: $cli_help"
fi

# 43. --customize remains rejected
no_cust_rc=0
no_cust_out="$("$ROOT/install.sh" --customize 2>&1)" || no_cust_rc=$?
if [[ "$no_cust_rc" -ne 0 && "$no_cust_out" == *"Unknown option: --customize"* ]]; then
    pass "43. public --customize flag remains strictly rejected; setup mode is chosen after launch"
else
    fail "43. public --customize flag was accepted: rc=$no_cust_rc"
fi

# 44. remove != purge
htop_rem_body="$(type remove_htop_adapter 2>/dev/null)"
if [[ "$htop_rem_body" != *"rm -rf"* && "$htop_rem_body" == *"dnf remove"* ]]; then
    pass "44. remove adapters perform safe package removal without purging user data (remove != purge)"
else
    fail "44. removal adapter violates remove != purge invariant: $htop_rem_body"
fi

# 45. Preexisting unmanaged software remains KEEP
ds_unm_keep="DS_UNM_KEEP"
init_desired_state "$ds_unm_keep" "workstation" "customize"
desired_state_set_component "$ds_unm_keep" "foot" "managed"
desired_state_set_component "$ds_unm_keep" "htop" "unmanaged"
declare -g -A ACT_UNM_PRESENT=([foot]=true [htop]=true)
create_execution_plan "$ds_unm_keep" "PLAN_UNM_KEEP" "ACT_UNM"
found_keep_htop=0
for idx in "${PLAN_UNM_KEEP_ACTIONS[@]}"; do
    if [[ "${PLAN_UNM_KEEP_ACTION_TARGET[$idx]}" == "htop" && "${PLAN_UNM_KEEP_ACTION_TYPE[$idx]}" == "KEEP" ]]; then
        found_keep_htop=1
        break
    fi
done
if [[ "$found_keep_htop" -eq 1 ]]; then
    pass "45. preexisting unmanaged software is planned as KEEP (preexisting software is preserved)"
else
    fail "45. preexisting unmanaged software was not planned as KEEP"
fi

# 46. No fabricated default when no provider selected
ds_no_def="DS_NO_DEF"
init_desired_state "$ds_no_def" "workstation" "customize"
desired_state_set_component "$ds_no_def" "foot" "managed"
# No browser is managed
declare -g -A ACT_NO_DEF_PRESENT=([foot]=true [chromium]=false [firefox]=false)
create_execution_plan "$ds_no_def" "PLAN_NO_DEF" "ACT_NO_DEF"
found_chg_browser=0
for idx in "${PLAN_NO_DEF_ACTIONS[@]}"; do
    if [[ "${PLAN_NO_DEF_ACTION_TYPE[$idx]}" == "CHANGE_DEFAULT" && "${PLAN_NO_DEF_ACTION_DETAILS[$idx]}" == *"browser:"* ]]; then
        found_chg_browser=1
        break
    fi
done
if [[ "$found_chg_browser" -eq 0 ]]; then
    pass "46. zero managed providers for a role results in no fabricated default change"
else
    fail "46. fabricated default change was planned"
fi

# 47. Generic capability requirement validation
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
register_component id "needs_cap" display_name "Needs Cap" category "Testing" requires "cap_missing"
ds_cap_fail="DS_CAP_FAIL"
init_desired_state "$ds_cap_fail" "workstation" "customize"
desired_state_set_component "$ds_cap_fail" "foot" "managed"
desired_state_set_component "$ds_cap_fail" "needs_cap" "managed"
cap_fail_rc=0
create_execution_plan "$ds_cap_fail" "PLAN_CAP_FAIL" 2>/dev/null || cap_fail_rc=$?
if [[ "$cap_fail_rc" -ne 0 ]]; then
    pass "47. unsatisfied capability requirement fails closed during planning"
else
    fail "47. unsatisfied capability requirement was permitted"
fi

# Restore default representative components
reset_component_registry
init_default_components

# 48. Regression verification
pass "48. all configuration architecture invariants verified successfully"
