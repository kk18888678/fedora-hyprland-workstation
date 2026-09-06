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
    printf 'keybindings.provider = custom_mock\n' > "$prov_sb/.config/workstation/desktop.conf"

    reset_component_registry
    init_default_components

    # Force quickshell install to fail
    install_quickshell_adapter() { return 1; }

    init_plan "PLAN_AURE_FAIL"
    add_plan_action "PLAN_AURE_FAIL" "INSTALL" "quickshell" "convergence required" "Quickshell Toolkit"
    add_plan_action "PLAN_AURE_FAIL" "INSTALL" "desktop.hotkeys.aurelia" "selected by user" "Aurelia Hotkeys"
    finalize_plan "PLAN_AURE_FAIL"

    TARGET_HOME="$prov_sb" execute_plan "PLAN_AURE_FAIL" >/dev/null 2>&1 || true

    curr_prov="$(grep -E '^[[:space:]]*(keybindings|hotkeys)[._]provider[[:space:]]*=' "$prov_sb/.config/workstation/desktop.conf" | cut -d '=' -f2 | tr -d '[:space:]')"
    rm -rf "$prov_sb"

    if [[ "$curr_prov" == "custom_mock" ]]; then
        pass "57. failed Aurelia dependency preserves existing provider configuration"
    else
        fail "57. existing provider was not preserved: '$curr_prov'"
    fi
)

# Test 58: provider config is not committed before successful dependency/component validation
(
    prov_sb="$(mktemp -d)"
    mkdir -p "$prov_sb/.config/workstation"
    printf 'keybindings.provider = custom_mock\n' > "$prov_sb/.config/workstation/desktop.conf"

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

    curr_prov="$(grep -E '^[[:space:]]*(keybindings|hotkeys)[._]provider[[:space:]]*=' "$prov_sb/.config/workstation/desktop.conf" | cut -d '=' -f2 | tr -d '[:space:]')"
    rm -rf "$prov_sb"

    if [[ "$curr_prov" == "custom_mock" ]]; then
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
    desired_state_set_component "DS_RERUN" "desktop.keybindings.aurelia" "unmanaged"
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
