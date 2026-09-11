section "Action vs Stage Failure Classification Contract"

_reset_test_status() {
    INSTALL_SUCCEEDED=()
    INSTALL_DEFERRED=()
    INSTALL_REQUIRED_FAILURES=()
    INSTALL_LOGIN_FAILURES=()
    ACTIVATION_BLOCKED=0
}

# 50a: workstation stage returns nonzero with NO prior classification -> records required failure
_reset_test_status
mock_unclass_fail() { return 1; }
run_classified_step workstation "Unclassified workstation failure" mock_unclass_fail
if [[ "${#INSTALL_REQUIRED_FAILURES[@]}" -eq 1 && "${INSTALL_REQUIRED_FAILURES[0]}" == *"without classifying the failure"* ]]; then
    pass "50a. unclassified workstation failure records required failure"
else
    fail "50a. unclassified workstation failure was not classified as required"
fi

# 50b: optional stage returns nonzero with NO prior classification -> records deferred failure
_reset_test_status
run_classified_step optional "Unclassified optional failure" mock_unclass_fail
if [[ "${#INSTALL_DEFERRED[@]}" -eq 1 && "${INSTALL_DEFERRED[0]}" == *"Stage exited 1"* ]]; then
    pass "50b. unclassified optional failure records deferred failure"
else
    fail "50b. unclassified optional failure was not classified as deferred"
fi

# 50c: login stage returns nonzero with NO prior classification -> records activation failure and blocks activation
_reset_test_status
run_classified_step login "Unclassified login failure" mock_unclass_fail
if [[ "${#INSTALL_LOGIN_FAILURES[@]}" -eq 1 && "$ACTIVATION_BLOCKED" -eq 1 ]]; then
    pass "50c. unclassified login failure records activation failure and blocks activation"
else
    fail "50c. unclassified login failure did not block activation"
fi

# 50c1: a login-class stage that already classified a workstation failure must
# not be upgraded to activation-critical merely because it returns nonzero.
_reset_test_status
mock_login_required_fail() {
    record_required "desktop" "service" "Non-login desktop service failed."
    return 1
}
run_classified_step login "Classified login-stage service failure" mock_login_required_fail
if [[ "${#INSTALL_REQUIRED_FAILURES[@]}" -eq 1 &&
      "${#INSTALL_LOGIN_FAILURES[@]}" -eq 0 &&
      "$ACTIVATION_BLOCKED" -eq 0 ]]; then
    pass "50c1. preclassified workstation failure in a login stage does not block graphical activation"
else
    fail "50c1. preclassified login-stage failure was incorrectly upgraded: req=${#INSTALL_REQUIRED_FAILURES[@]} login=${#INSTALL_LOGIN_FAILURES[@]} blocked=$ACTIVATION_BLOCKED"
fi

# 50c2: production stages cannot swallow an unguarded mutation failure.
_reset_test_status
mock_uncaught_mutation() {
    false
    record_success "must-not-be-recorded"
}
INSTALLER_PRODUCTION_MODE=1
run_classified_step optional "Production unguarded failure" mock_uncaught_mutation
unset INSTALLER_PRODUCTION_MODE
if [[ "${#INSTALL_DEFERRED[@]}" -eq 1 &&
      "${#INSTALL_SUCCEEDED[@]}" -eq 0 &&
      "${INSTALL_DEFERRED[0]}" == *"Stage exited 1"* ]]; then
    pass "50c2. production ERR trampoline classifies unguarded stage failures before success can be recorded"
else
    fail "50c2. production stage swallowed an unguarded failure: success=${INSTALL_SUCCEEDED[*]} deferred=${INSTALL_DEFERRED[*]}"
fi

# 50d & 50e: reconciler action records deferred and execution completes -> no additional required stage failure is added
_reset_test_status
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
mock_opt_inst_fail() { return 1; }
register_component id "opt_comp" display_name "Opt Comp" category "Testing" required false removable true install_fn "mock_opt_inst_fail"
init_plan "PLAN_OPT_ONLY"
add_plan_action "PLAN_OPT_ONLY" "INSTALL" "opt_comp" "user" "Opt Comp"
finalize_plan "PLAN_OPT_ONLY"

run_classified_step workstation "Reconciling configured components" execute_plan "PLAN_OPT_ONLY"
if [[ "${#INSTALL_DEFERRED[@]}" -eq 1 && "${#INSTALL_REQUIRED_FAILURES[@]}" -eq 0 ]]; then
    pass "50d. reconciler deferred failure completes without adding a duplicate required stage failure"
else
    fail "50d. reconciler deferred failure was promoted: req=${#INSTALL_REQUIRED_FAILURES[@]} def=${#INSTALL_DEFERRED[@]}"
fi
resolved_opt_exit="$(installer_exit_code)"
if [[ "$resolved_opt_exit" -eq 2 ]]; then
    pass "50e. deferred-only reconciliation outcome resolves to installer exit code 2"
else
    fail "50e. deferred-only reconciliation resolved to exit code $resolved_opt_exit (expected 2)"
fi

# 50f & 50g: reconciler action records required -> no duplicate generic required stage failure is added
_reset_test_status
mock_req_inst_fail() { return 1; }
register_component id "req_comp" display_name "Req Comp" category "Testing" required true removable false install_fn "mock_req_inst_fail"
init_plan "PLAN_REQ_ONLY"
add_plan_action "PLAN_REQ_ONLY" "INSTALL" "req_comp" "user" "Req Comp"
finalize_plan "PLAN_REQ_ONLY"

run_classified_step workstation "Reconciling configured components" execute_plan "PLAN_REQ_ONLY"
if [[ "${#INSTALL_REQUIRED_FAILURES[@]}" -eq 1 && "${INSTALL_REQUIRED_FAILURES[0]}" == *"Required component installation failed: req_comp"* ]]; then
    pass "50f. reconciler required failure completes without adding duplicate unclassified stage failure"
else
    fail "50f. required failure created duplicate stage failure: ${INSTALL_REQUIRED_FAILURES[*]}"
fi
resolved_req_exit="$(installer_exit_code)"
if [[ "$resolved_req_exit" -eq 1 ]]; then
    pass "50g. required reconciliation failure resolves to installer exit code 1"
else
    fail "50g. required reconciliation resolved to exit code $resolved_req_exit (expected 1)"
fi

# 50h: activation-critical classification is never downgraded
_reset_test_status
ACTIVATION_BLOCKED=1
INSTALL_LOGIN_FAILURES+=("test: login: critical failure")
run_classified_step workstation "Reconciling after login failure" execute_plan "PLAN_OPT_ONLY"
if [[ "$ACTIVATION_BLOCKED" -eq 1 && ${#INSTALL_LOGIN_FAILURES[@]} -eq 1 ]]; then
    pass "50h. activation-critical classification is never downgraded by reconciler"
else
    fail "50h. activation-critical status was downgraded: blocked=$ACTIVATION_BLOCKED"
fi

# 50i & 50j: malformed/unvalidated plan still fails closed and is classified by run_classified_step
_reset_test_status
init_plan "PLAN_UNFINAL"
add_plan_action "PLAN_UNFINAL" "INSTALL" "foot" "user" "Foot"
# Not finalized!
run_classified_step workstation "Reconciling unfinalized plan" execute_plan "PLAN_UNFINAL"
if [[ "${#INSTALL_REQUIRED_FAILURES[@]}" -eq 1 && "${INSTALL_REQUIRED_FAILURES[0]}" == *"without classifying the failure"* ]]; then
    pass "50i. unfinalized plan passed to execute_plan fails closed and is surfaced as required stage failure"
    pass "50j. unexpected execute_plan failure with no inner classification is surfaced by wrapper"
else
    fail "50i. unfinalized plan failure was not surfaced as required stage failure"
fi

# 50k: multiple classified failures do not create one extra generic failure
_reset_test_status
init_plan "PLAN_MULTI_FAIL"
add_plan_action "PLAN_MULTI_FAIL" "INSTALL" "opt_comp" "user" "Opt Comp"
add_plan_action "PLAN_MULTI_FAIL" "INSTALL" "req_comp" "user" "Req Comp"
finalize_plan "PLAN_MULTI_FAIL"
run_classified_step workstation "Reconciling multi-failure plan" execute_plan "PLAN_MULTI_FAIL"
if [[ "${#INSTALL_DEFERRED[@]}" -eq 1 && "${#INSTALL_REQUIRED_FAILURES[@]}" -eq 1 ]]; then
    pass "50k. multiple classified failures do not generate an additional generic stage failure"
else
    fail "50k. multiple failures resulted in incorrect failure counts: req=${#INSTALL_REQUIRED_FAILURES[@]} def=${#INSTALL_DEFERRED[@]}"
fi

# 50l: successful reconciliation returns/behaves as success
_reset_test_status
init_plan "PLAN_CLEAN_SUCCESS"
finalize_plan "PLAN_CLEAN_SUCCESS"
clean_rec_rc=0
run_classified_step workstation "Reconciling empty clean plan" execute_plan "PLAN_CLEAN_SUCCESS" || clean_rec_rc=$?
if [[ "$clean_rec_rc" -eq 0 && "${#INSTALL_REQUIRED_FAILURES[@]}" -eq 0 && "${#INSTALL_DEFERRED[@]}" -eq 0 ]]; then
    pass "50l. successful reconciliation returns 0 and leaves failure journals clean"
else
    fail "50l. clean reconciliation failed: rc=$clean_rec_rc"
fi

# 50m: no action failure disappears from the final status journal
_reset_test_status
run_classified_step workstation "Reconciling multi-failure plan" execute_plan "PLAN_MULTI_FAIL"
if [[ "${INSTALL_DEFERRED[0]}" == *"opt_comp"* && "${INSTALL_REQUIRED_FAILURES[0]}" == *"req_comp"* ]]; then
    pass "50m. no individual action failure disappears from the status journal"
else
    fail "50m. action failure details were lost in status journal"
fi
