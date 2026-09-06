section "Executable Role Default Adapters and Decoupled Preference Modeling"

reset_component_registry
init_default_components

# 49a: role with registered executable adapter can produce CHANGE_DEFAULT
# In workstation profile, actual browser is detected as "" (none), desired is chromium
create_recommended_desired_state "DS_DEF_EXEC" "workstation"
create_execution_plan "DS_DEF_EXEC" "PLAN_DEF_EXEC"
found_browser_action=0
for idx in "${PLAN_DEF_EXEC_ACTIONS[@]}"; do
    if [[ "${PLAN_DEF_EXEC_ACTION_TYPE[$idx]}" == "CHANGE_DEFAULT" && "${PLAN_DEF_EXEC_ACTION_DETAILS[$idx]}" == *"browser:"* ]]; then
        found_browser_action=1
        break
    fi
done
if [[ "$found_browser_action" -eq 1 ]]; then
    pass "49a. role with registered executable adapter (browser) produces CHANGE_DEFAULT"
else
    fail "49a. executable adapter role did not produce CHANGE_DEFAULT"
fi

# 49b: role without executable adapter does NOT produce CHANGE_DEFAULT
# 49d: terminal currently does not produce an executable CHANGE_DEFAULT action
# 49e: text-editor currently does not produce an executable CHANGE_DEFAULT action
found_term_action=0
found_editor_action=0
for idx in "${PLAN_DEF_EXEC_ACTIONS[@]}"; do
    if [[ "${PLAN_DEF_EXEC_ACTION_TYPE[$idx]}" == "CHANGE_DEFAULT" ]]; then
        if [[ "${PLAN_DEF_EXEC_ACTION_DETAILS[$idx]}" == *"terminal:"* ]]; then found_term_action=1; fi
        if [[ "${PLAN_DEF_EXEC_ACTION_DETAILS[$idx]}" == *"text-editor:"* ]]; then found_editor_action=1; fi
    fi
done
if [[ "$found_term_action" -eq 0 && "$found_editor_action" -eq 0 ]]; then
    pass "49b. roles without executable adapters do not produce CHANGE_DEFAULT actions"
    pass "49d. terminal role produces zero executable CHANGE_DEFAULT actions"
    pass "49e. text-editor role produces zero executable CHANGE_DEFAULT actions"
else
    fail "49b. un-executable role produced CHANGE_DEFAULT: term=$found_term_action editor=$found_editor_action"
fi

# 49c: browser remains actionable by default
if role_has_default_adapter "browser"; then
    pass "49c. browser role is registered as an executable default adapter"
else
    fail "49c. browser role is not registered as executable"
fi

# 49f: review action counts accurately reflect only executable actions
c_def="${PLAN_DEF_EXEC_COUNT_CHANGE_DEFAULT}"
if [[ "$c_def" -eq 2 ]]; then
    pass "49f. review plan action counts accurately reflect only executable actions (2 default changes: browser and file-manager)"
else
    fail "49f. review plan action count was $c_def (expected 2)"
fi

# 49g: unsupported/non-actionable role fails closed if manually planned or called in set_system_role_default
init_plan "PLAN_UNEXEC_DEF"
add_plan_action "PLAN_UNEXEC_DEF" "CHANGE_DEFAULT" "foot" "preferred" "terminal: none -> Foot"
unexec_rc=0
finalize_plan "PLAN_UNEXEC_DEF" 2>/dev/null || unexec_rc=$?
if [[ "$unexec_rc" -ne 0 ]]; then
    pass "49g. un-executable role in plan CHANGE_DEFAULT fails plan validation fail-closed"
else
    fail "49g. un-executable role in plan was accepted by finalize_plan"
fi

call_unexec_rc=0
set_system_role_default "terminal" "foot" 2>/dev/null || call_unexec_rc=$?
if [[ "$call_unexec_rc" -ne 0 ]]; then
    pass "49g2. set_system_role_default returns 1 for un-executable role"
else
    fail "49g2. set_system_role_default succeeded for un-executable role"
fi

# 49h: generic role/default desired-state validation remains intact
ds_val_rc=0
validate_desired_state "DS_DEF_EXEC" || ds_val_rc=$?
if [[ "$ds_val_rc" -eq 0 ]]; then
    pass "49h. generic role/default desired-state validation remains valid"
else
    fail "49h. desired state validation failed: rc=$ds_val_rc"
fi

# 49i: adding a mocked adapter for another role in isolated tests proves architecture is extensible
mock_terminal_adapter_called=0
mock_terminal_adapter() { mock_terminal_adapter_called=1; return 0; }
mock_terminal_detector() { printf 'none\n'; }
register_role_default_adapter "terminal" "mock_terminal_adapter" "mock_terminal_detector"
create_recommended_desired_state "DS_MOCK_TERM" "workstation"
create_execution_plan "DS_MOCK_TERM" "PLAN_MOCK_TERM"
found_mock_term=0
for idx in "${PLAN_MOCK_TERM_ACTIONS[@]}"; do
    if [[ "${PLAN_MOCK_TERM_ACTION_TYPE[$idx]}" == "CHANGE_DEFAULT" && "${PLAN_MOCK_TERM_ACTION_DETAILS[$idx]}" == *"terminal:"* ]]; then
        found_mock_term=1
        break
    fi
done
if [[ "$found_mock_term" -eq 1 ]]; then
    pass "49i. registering a new role default adapter enables planning without planner role-name special-casing"
else
    fail "49i. dynamically registered role default adapter was not planned"
fi
init_default_role_adapters
