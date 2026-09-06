section "21-22. Command Execution Safety Invariants"

# Test 21: Structured argv execution remains preserved
term_argv="$(HOTKEYS_TEST_ACTION=run_argv HOTKEYS_TEST_ID=terminal "$ROOT/bin/workstation-hotkeys")"
if [[ "$term_argv" == *"kitty"* || "$term_argv" == *"foot"* ]]; then
    pass "21. structured argv execution remains preserved"
else
    fail "21. structured argv failed: $term_argv"
fi

# Test 22: No eval or sh -c command execution added
eval_hotkeys="$(grep -E 'eval |sh -c' "$ROOT/bin/workstation-hotkeys" 2>/dev/null || true)"
eval_qml="$(grep -E 'eval\(|sh -c' "$ROOT/dotfiles/aurelia/components/hotkeys/"*.qml 2>/dev/null || true)"
if [[ -z "$eval_hotkeys" && -z "$eval_qml" ]]; then
    pass "22. no eval/sh-c command execution added"
else
    fail "22. unsafe command execution detected: hotkeys=$eval_hotkeys qml=$eval_qml"
fi
