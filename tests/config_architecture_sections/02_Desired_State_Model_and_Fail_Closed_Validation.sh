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
