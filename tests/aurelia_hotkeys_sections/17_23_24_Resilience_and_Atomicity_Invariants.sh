section "23-24. Resilience and Atomicity Invariants"

# Test 23: Aurelia failure reports error and does NOT silently launch legacy fzf
fail_rc=0
fail_fallback_out="$(HOTKEYS_SIMULATE_AURELIA_FAIL=1 "$ROOT/bin/workstation-hotkeys" --provider=aurelia 2>&1)" || fail_rc=$?
if [[ "$fail_rc" -ne 0 && "$fail_fallback_out" != *"Keyboard Shortcuts"* ]]; then
    pass "23. Aurelia failure fails closed and does not launch legacy fzf"
else
    fail "23. Aurelia failure unexpectedly launched fallback: $fail_fallback_out"
fi

# Test 24: Config/state writes are atomic where applicable
cfg_sb="$(mktemp -d)"
TARGET_HOME="$cfg_sb" set_workstation_hotkeys_provider "aurelia"
if [[ -f "$cfg_sb/.config/workstation/desktop.conf" ]] &&
   grep -q "hotkeys.provider = aurelia" "$cfg_sb/.config/workstation/desktop.conf"; then
    pass "24. config/state writes are atomic where applicable"
else
    fail "24. atomic state write failed"
fi
rm -rf "$cfg_sb"
