section "33. Single-Instance and Path Option Dispatch Invariants"

# Test 33: Quickshell dispatch must use --no-duplicate and --path
dispatch_src="$(grep -E '\$qs_bin.*--no-duplicate.*--path' "$ROOT/bin/lib/aurelia-keybindings/toggle.sh" 2>/dev/null || true)"
if [[ -n "$dispatch_src" ]]; then
    pass "33. repeated dispatch cannot create duplicate instances (uses --no-duplicate and --path)"
else
    fail "33. dispatch missing --no-duplicate or --path"
fi
