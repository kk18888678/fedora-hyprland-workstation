section "17-18. Shortcut Mutation Invariants (Alt+S and Alt+U)"

test_sb="$(mktemp -d)"
test_overrides="$test_sb/overrides.json"
echo "{}" > "$test_overrides"

# Test 17: Alt+S routes to physical capture backend
HOTKEYS_OVERRIDES="$test_overrides" HOTKEYS_CAPTURE_MOCK_INPUT="SUPER+SHIFT+T" "$ROOT/bin/workstation-hotkeys" set terminal >/dev/null 2>&1
check_set="$(cat "$test_overrides")"
if [[ "$check_set" == *"SUPER + SHIFT + T"* ]]; then
    pass "17. Alt+S routes to existing physical capture backend"
else
    fail "17. Alt+S failed to route to capture backend: $check_set"
fi

# Test 18: Alt+U routes to unset backend
HOTKEYS_OVERRIDES="$test_overrides" "$ROOT/bin/workstation-hotkeys" unset terminal >/dev/null 2>&1
check_unset="$(cat "$test_overrides")"
if [[ "$check_unset" == *"false"* || "$check_unset" == *"none"* ]]; then
    pass "18. Alt+U routes to existing unset backend"
else
    fail "18. Alt+U failed to unset shortcut: $check_unset"
fi
rm -rf "$test_sb"
