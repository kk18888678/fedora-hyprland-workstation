section "Interactive Wizard Safety and Non-TTY Fail-Closed Behavior"

# Restore default representative components
reset_component_registry
init_default_components

# 36. Cancellation before Apply -> zero mutations
WIZARD_MOCK_INPUT=1
WIZARD_MOCK_KEYS="CANCEL"
wiz_cancel_rc=0
run_setup_mode "workstation" "PLAN_CANCEL" || wiz_cancel_rc=$?
if [[ "$wiz_cancel_rc" -eq 2 ]]; then
    pass "36. cancellation in Review terminates cleanly with exit code 2 (zero mutations)"
else
    fail "36. cancel in review failed: rc=$wiz_cancel_rc"
fi
unset WIZARD_MOCK_INPUT WIZARD_MOCK_KEYS

# 37. Edit -> rebuild/review correctly
WIZARD_MOCK_INPUT=1
# Sequence: select recommended, in review choose EDIT, in customize press ENTER across categories + default selection screens (browser, file-manager), in review choose APPLY
WIZARD_MOCK_KEYS="ENTER EDIT ENTER ENTER ENTER ENTER ENTER ENTER APPLY"
wiz_edit_rc=0
run_setup_mode "workstation" "PLAN_EDIT" || wiz_edit_rc=$?
if [[ "$wiz_edit_rc" -eq 0 && "${PLAN_EDIT_VALIDATED:-}" == "true" ]]; then
    pass "37. Edit flow from Review allows modifying desired state and rebuilds validated plan"
else
    fail "37. Edit flow failed: rc=$wiz_edit_rc"
fi
unset WIZARD_MOCK_INPUT WIZARD_MOCK_KEYS

# 38. Removal requires explicit confirmation
plan_rem_conf="PLAN_REM_CONF"
init_plan "$plan_rem_conf"
add_plan_action "$plan_rem_conf" "REMOVE" "htop" "deselected" "htop"
finalize_plan "$plan_rem_conf"
WIZARD_MOCK_INPUT=1
WIZARD_MOCK_KEYS="a CANCEL"
WIZARD_MOCK_CONFIRM="no"
rem_conf_action=""
wizard_review_plan "$plan_rem_conf" rem_conf_action
if [[ "$rem_conf_action" == "CANCEL" ]]; then
    pass "38. destructive REMOVE action requires typing 'yes'; declining cancels setup safely"
else
    fail "38. destructive confirmation was bypassed: action=$rem_conf_action"
fi
unset WIZARD_MOCK_INPUT WIZARD_MOCK_KEYS WIZARD_MOCK_CONFIRM

# 39. Production non-TTY -> fail safely
unset SETUP_MODE WIZARD_MOCK_INPUT
nontty_rc=0
nontty_out="$(run_setup_mode "workstation" "PLAN_NONTTY" </dev/null 2>&1)" || nontty_rc=$?
if [[ "$nontty_rc" -ne 0 && "$nontty_out" == *"Interactive terminal required"* ]]; then
    pass "39. non-interactive terminal execution fails closed safely with clear diagnostic without hanging"
else
    fail "39. non-interactive execution did not fail safely: rc=$nontty_rc"
fi

# 40. SETUP_MODE environment variable cannot bypass interactive terminal requirement
SETUP_MODE="recommended"
nontty_rec_rc=0
nontty_rec_out="$(run_setup_mode "workstation" "PLAN_NONTTY_REC" </dev/null 2>&1)" || nontty_rec_rc=$?
if [[ "$nontty_rec_rc" -ne 0 && "$nontty_rec_out" == *"Interactive terminal required"* ]]; then
    pass "40. SETUP_MODE environment variable cannot bypass interactive terminal requirement"
else
    fail "40. SETUP_MODE bypassed terminal safety: rc=$nontty_rec_rc out=$nontty_rec_out"
fi
unset SETUP_MODE

# 41. SETUP_MODE environment variable cannot bypass interactive setup-mode selection
WIZARD_MOCK_INPUT=1
SETUP_MODE="recommended"
# User input sends CANCEL at the setup mode selection screen
WIZARD_MOCK_KEYS="CANCEL"
sm_bypass_rc=0
run_setup_mode "workstation" "PLAN_SM_BYPASS" || sm_bypass_rc=$?
# If SETUP_MODE was honored as an override, it would have selected recommended, built plan, and prompted Review.
# Because it must ALWAYS call wizard_select_setup_mode, CANCEL terminates immediately with rc 2.
if [[ "$sm_bypass_rc" -eq 2 ]]; then
    pass "41. SETUP_MODE=recommended cannot bypass interactive setup-mode selection screen"
else
    fail "41. SETUP_MODE bypassed interactive setup-mode selection: rc=$sm_bypass_rc"
fi
unset SETUP_MODE WIZARD_MOCK_INPUT WIZARD_MOCK_KEYS

# 41b. SETUP_MODE=customize cannot bypass interactive setup-mode selection screen
WIZARD_MOCK_INPUT=1
SETUP_MODE="customize"
WIZARD_MOCK_KEYS="CANCEL"
sm_cust_rc=0
run_setup_mode "workstation" "PLAN_SM_CUST" || sm_cust_rc=$?
if [[ "$sm_cust_rc" -eq 2 ]]; then
    pass "41b. SETUP_MODE=customize cannot bypass interactive setup-mode selection screen"
else
    fail "41b. SETUP_MODE=customize bypassed interactive setup-mode selection: rc=$sm_cust_rc"
fi
unset SETUP_MODE WIZARD_MOCK_INPUT WIZARD_MOCK_KEYS

# 41c. Arbitrary SETUP_MODE values do not create a separate production parsing path
WIZARD_MOCK_INPUT=1
SETUP_MODE="garbage"
WIZARD_MOCK_KEYS="CANCEL"
sm_garb_rc=0
run_setup_mode "workstation" "PLAN_SM_GARB" || sm_garb_rc=$?
if [[ "$sm_garb_rc" -eq 2 ]]; then
    pass "41c. arbitrary SETUP_MODE=garbage is completely ignored and interactive selection runs"
else
    fail "41c. arbitrary SETUP_MODE altered setup-mode behavior: rc=$sm_garb_rc"
fi
unset SETUP_MODE WIZARD_MOCK_INPUT WIZARD_MOCK_KEYS
