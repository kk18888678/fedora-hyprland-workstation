section "34-35. Strict Action ID Validation"

# Test 34: Unknown action ID must fail closed
unknown_rc=0
"$ROOT/bin/workstation-hotkeys" run "non_existent_action_xyz" >/dev/null 2>&1 || unknown_rc=$?
if [[ "$unknown_rc" -ne 0 ]]; then
    pass "34. unknown action ID cannot run (fails closed)"
else
    fail "34. unknown action ID succeeded unexpectedly"
fi

# Test 35: Malicious/metacharacter action ID must fail closed
meta_rc=0
"$ROOT/bin/workstation-hotkeys" run "app:foo;reboot" >/dev/null 2>&1 || meta_rc=$?
if [[ "$meta_rc" -ne 0 ]]; then
    pass "35. invalid action ID format fails closed"
else
    fail "35. invalid action ID accepted: rc=$meta_rc"
fi
