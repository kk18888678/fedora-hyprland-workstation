section "6. Hotkeys Provider Conflict Resolution"

init_desired_state "DS_HOTKEY_CONFLICT" "workstation"
desired_state_set_component "DS_HOTKEY_CONFLICT" "desktop.keybindings.aurelia" "managed"
desired_state_set_component "DS_HOTKEY_CONFLICT" "desktop.hotkeys.aurelia" "managed"
desired_state_set_default "DS_HOTKEY_CONFLICT" "browser" "chromium"
desired_state_set_default "DS_HOTKEY_CONFLICT" "file-manager" "nautilus"

plan_conf_rc=0
create_execution_plan "DS_HOTKEY_CONFLICT" "PLAN_HOTKEY_CONFLICT" 2>/dev/null || plan_conf_rc=$?
if [[ "$plan_conf_rc" -ne 0 ]]; then
    pass "6. provider conflict prevents two Keybindings/Hotkeys owners from being active simultaneously"
else
    fail "6. planner allowed conflicting keybinding providers to be managed simultaneously"
fi
