section "15-16. Return / Action Execution Invariants"

# Test 15: Return invokes runnable action path
run_term_rc=0
HOTKEYS_TEST_ACTION=run HOTKEYS_TEST_ID=terminal "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || run_term_rc=$?
if [[ "$run_term_rc" -eq 0 ]]; then
    pass "15. Return invokes runnable action path"
else
    fail "15. Return failed on runnable action: rc=$run_term_rc"
fi

# Test 16: Return does not pretend to run non-runnable action
run_nonrun_rc=0
"$ROOT/bin/workstation-hotkeys" run window_close >/dev/null 2>&1 || run_nonrun_rc=$?
if [[ "$run_nonrun_rc" -ne 0 ]]; then
    pass "16. Return does not pretend to run non-runnable action (fails closed without execution)"
else
    fail "16. Return executed non-runnable context action"
fi
