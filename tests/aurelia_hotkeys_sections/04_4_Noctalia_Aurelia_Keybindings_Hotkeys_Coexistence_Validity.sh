section "4. Noctalia + Aurelia Keybindings/Hotkeys Coexistence Validity"

reset_component_registry
init_default_components
init_desired_state "DS_NOCT_AURE" "workstation"
create_recommended_desired_state "DS_NOCT_AURE" "workstation"
desired_state_set_component "DS_NOCT_AURE" "desktop.environment.noctalia" "managed"
desired_state_set_component "DS_NOCT_AURE" "desktop.keybindings.aurelia" "managed"

plan_rc=0
create_execution_plan "DS_NOCT_AURE" "PLAN_NOCT_AURE" || plan_rc=$?
if [[ "$plan_rc" -eq 0 && "${PLAN_NOCT_AURE_VALIDATED:-}" == "true" ]]; then
    pass "4. Noctalia + Aurelia Keybindings is valid and generates a valid execution plan"
else
    fail "4. Noctalia + Aurelia Keybindings failed planning: rc=$plan_rc"
fi
