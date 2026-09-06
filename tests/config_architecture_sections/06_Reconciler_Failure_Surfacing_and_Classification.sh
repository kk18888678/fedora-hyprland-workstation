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
INSTALL_DEFERRED=()
execute_plan "PLAN_DEF_REC" 2>/dev/null || true
if [[ "${#INSTALL_DEFERRED[@]}" -gt 0 ]]; then
    pass "34f. CHANGE_DEFAULT failure is surfaced through record_deferred"
else
    fail "34f. CHANGE_DEFAULT failure was not recorded"
fi

# 35. INSTALL failure classified correctly
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
mock_req_inst_fail() { return 1; }
register_component id "req_fail_comp" display_name "Req Fail" category "Testing" required true removable false install_fn "mock_req_inst_fail"
init_plan "PLAN_REQ_FAIL"
add_plan_action "PLAN_REQ_FAIL" "INSTALL" "req_fail_comp" "user" "Req Fail"
finalize_plan "PLAN_REQ_FAIL"
INSTALL_REQUIRED_FAILURES=()
execute_plan "PLAN_REQ_FAIL" 2>/dev/null || true
if [[ "${#INSTALL_REQUIRED_FAILURES[@]}" -gt 0 ]]; then
    pass "35. required component installation failure is recorded via record_required"
else
    fail "35. required failure classification failed"
fi
