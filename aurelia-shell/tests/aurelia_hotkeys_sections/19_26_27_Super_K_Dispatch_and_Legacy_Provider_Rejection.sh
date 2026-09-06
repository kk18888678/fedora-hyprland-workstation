section "26-27. Super+K Dispatch and Legacy Provider Rejection"

# Test 26: Current provider determines Super+K target
aure_target="$(HOTKEYS_SIMULATE_AURELIA_SUCCESS=1 "$ROOT/bin/workstation-hotkeys" --provider=aurelia)"
if [[ "$aure_target" == "AURELIA_TOGGLE_OK" ]]; then
    pass "26. current provider determines Super+K target (dispatches to Aurelia when selected)"
else
    fail "26. provider dispatch failed: $aure_target"
fi

# Test 27: Legacy fzf Hotkeys is strictly rejected
leg_rc=0
leg_err="$("$ROOT/bin/workstation-hotkeys" --provider=legacy 2>&1)" || leg_rc=$?
if [[ "$leg_rc" -ne 0 && "$leg_err" == *"Legacy provider has been removed"* ]]; then
    pass "27. legacy fzf provider is strictly rejected (exit code 1, no fallback UI)"
else
    fail "27. legacy Hotkeys provider not rejected cleanly: rc=$leg_rc err=$leg_err"
fi
