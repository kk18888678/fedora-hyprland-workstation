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

# Production execution must never honor the test-only reconciler executor.
reconciler_mock_calls=0
reconciler_real_calls=0
mock_reconciler_executor() {
    reconciler_mock_calls=$((reconciler_mock_calls + 1))
    return 0
}
real_reconciler_callback() {
    reconciler_real_calls=$((reconciler_real_calls + 1))
    return 0
}

production_reconciler_rc=0
INSTALLER_PRODUCTION_MODE=1 \
RECONCILER_MOCK_EXECUTOR=mock_reconciler_executor \
    _reconciler_invoke real_reconciler_callback test_component CONFIGURE ||
    production_reconciler_rc=$?

if [[ "$production_reconciler_rc" -eq 0 && "$reconciler_mock_calls" -eq 0 && "$reconciler_real_calls" -eq 1 ]]; then
    pass "20. production reconciler ignores test mock executor and calls registered callback"
else
    fail "20. production reconciler honored test mock executor: rc=$production_reconciler_rc mock=$reconciler_mock_calls real=$reconciler_real_calls"
fi

# Desktop shell metadata participates in the plan integrity boundary.
init_plan "PLAN_SHELL_META"
PLAN_SHELL_META_DESKTOP_SHELL="aurelia"
add_plan_action "PLAN_SHELL_META" "KEEP" "chromium" "already installed" "Chromium"
finalize_plan "PLAN_SHELL_META"
PLAN_SHELL_META_DESKTOP_SHELL="noctalia"
shell_meta_rc=0
validate_plan "PLAN_SHELL_META" 2>/dev/null || shell_meta_rc=$?
if [[ "$shell_meta_rc" -ne 0 ]]; then
    pass "20b. changing selected desktop shell after review fails plan integrity validation"
else
    fail "20b. plan integrity did not cover selected desktop shell"
fi
