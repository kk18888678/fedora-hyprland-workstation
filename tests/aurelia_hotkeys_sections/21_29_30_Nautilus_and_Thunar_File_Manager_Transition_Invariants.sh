section "29-30. Nautilus and Thunar File Manager Transition Invariants"

# Test 29: If Nautilus is implemented, deselecting Thunar does not remove it (removable: false)
thunar_removable="$(get_component_attr "thunar" removable)"
if [[ "$thunar_removable" == "false" ]]; then
    pass "29. if Nautilus is implemented, deselecting Thunar does not remove it (removable: false invariant)"
else
    fail "29. Thunar is marked removable: $thunar_removable"
fi

# Test 30: If Nautilus is implemented, default file-manager role changes explicitly
init_desired_state "DS_FM_TEST" "workstation"
create_recommended_desired_state "DS_FM_TEST" "workstation"
fm_default="$(desired_state_get_default "DS_FM_TEST" "file-manager")"
if [[ "$fm_default" == "nautilus" ]]; then
    pass "30. if Nautilus is implemented, default file-manager role changes explicitly to nautilus"
else
    fail "30. Default file manager role did not default to nautilus: $fm_default"
fi
