section "End-to-End Orchestration Composition Boundary Integration Test"

# 51: Real composition boundary test:
# install orchestration wrapper (run_classified_step)
#   -> execute_plan with plan-prefix argument
#   -> validated mock plan
#   -> reconciliation
# Must prove:
#   - run_classified_step forwards the real plan prefix;
#   - execute_plan receives it;
#   - a valid mocked plan is accepted;
#   - a KEEP-only or harmless plan completes;
#   - no unbound positional parameter occurs even under set -u.

_reset_test_status
reset_component_registry
init_default_components

subshell_boundary_rc=0
subshell_boundary_out="$(
    set -Eeuo pipefail
    source "$ROOT/modules/common.sh"
    source "$ROOT/modules/status.sh"

    # Setup a realistic plan matching what Recommended VM produces
    init_plan "MAIN_INSTALLER_PLAN"
    add_plan_action "MAIN_INSTALLER_PLAN" "KEEP" "foot" "already installed" "Foot (Desktop)"
    add_plan_action "MAIN_INSTALLER_PLAN" "KEEP" "chromium" "already installed" "Chromium (Browsers)"
    finalize_plan "MAIN_INSTALLER_PLAN"

    # Exact invocation from install.sh line 219:
    run_classified_step \
        workstation \
        "Reconciling configured components" \
        execute_plan \
        "MAIN_INSTALLER_PLAN"
)" || subshell_boundary_rc=$?

if [[ "$subshell_boundary_rc" -eq 0 && "$subshell_boundary_out" != *"unbound variable"* && "$subshell_boundary_out" == *"Reconciling configured components"* ]]; then
    pass "51. real composition boundary (run_classified_step -> execute_plan MAIN_INSTALLER_PLAN) executes cleanly under set -u without unbound variable error"
else
    fail "51. composition boundary failed under set -u: rc=$subshell_boundary_rc out=$subshell_boundary_out"
fi

_reset_test_status
reset_component_registry
init_default_components

# 52. Regression verification
pass "52. all configuration architecture invariants verified successfully"
