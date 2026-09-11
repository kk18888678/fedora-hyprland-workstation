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
dnf_remove_helper_body="$(type remove_managed_dnf_package 2>/dev/null)"
if [[ "$htop_rem_body" != *"rm -rf"* &&
      "$dnf_remove_helper_body" == *"dnf remove"* &&
      "$dnf_remove_helper_body" == *"run_dnf_command"* ]]; then
    pass "44. remove adapters perform bounded, trust-gated package removal without purging user data"
else
    fail "44. removal adapter violates bounded remove != purge invariant: $htop_rem_body helper=$dnf_remove_helper_body"
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
