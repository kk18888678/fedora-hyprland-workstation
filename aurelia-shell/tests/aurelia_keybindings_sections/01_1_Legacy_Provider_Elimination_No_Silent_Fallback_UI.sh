section "1. Legacy Provider Elimination & No Silent Fallback UI"

# 1.1: workstation-keybindings --provider=legacy fails with exit code 1
keyb_leg_rc=0
keyb_leg_out="$("$ROOT/bin/workstation-keybindings" --provider=legacy 2>&1)" || keyb_leg_rc=$?
if [[ "$keyb_leg_rc" -eq 1 && "$keyb_leg_out" == *"Legacy provider has been removed"* ]]; then
    pass "1.1 workstation-keybindings rejects --provider=legacy with exit code 1"
else
    fail "1.1 workstation-keybindings failed to reject --provider=legacy: rc=$keyb_leg_rc out=$keyb_leg_out"
fi

# 1.2: workstation-hotkeys --provider=legacy fails with exit code 1
hotk_leg_rc=0
hotk_leg_out="$("$ROOT/bin/workstation-hotkeys" --provider=legacy 2>&1)" || hotk_leg_rc=$?
if [[ "$hotk_leg_rc" -eq 1 && "$hotk_leg_out" == *"Legacy provider has been removed"* ]]; then
    pass "1.2 workstation-hotkeys forwards and rejects --provider=legacy with exit code 1"
else
    fail "1.2 workstation-hotkeys failed to reject --provider=legacy: rc=$hotk_leg_rc out=$hotk_leg_out"
fi

# 1.3: No silent fallback UI on failure (does not launch Foot/Kitty/fzf when Aurelia unavailable)
fail_closed_rc=0
fail_closed_out="$(HOTKEYS_SIMULATE_AURELIA_FAIL=1 "$ROOT/bin/workstation-keybindings" 2>&1)" || fail_closed_rc=$?
if [[ "$fail_closed_rc" -ne 0 && "$fail_closed_out" != *"fzf"* && "$fail_closed_out" != *"Keyboard Shortcuts"* ]]; then
    pass "1.3 Aurelia failure fails closed without launching silent legacy fallback UI"
else
    fail "1.3 Aurelia failure launched fallback UI: rc=$fail_closed_rc out=$fail_closed_out"
fi
