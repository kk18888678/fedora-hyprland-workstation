section "3. Thin Compatibility Wrapper Invariants"

# 3.1: workstation-hotkeys is a thin wrapper without duplicate logic
hotk_lines="$(wc -l < "$ROOT/bin/workstation-hotkeys")"
if [[ "$hotk_lines" -le 60 ]] &&
   grep -q 'workstation-keybindings' "$ROOT/bin/workstation-hotkeys" &&
   grep -q 'exec "\$target_bin"' "$ROOT/bin/workstation-hotkeys"; then
    pass "3.1 workstation-hotkeys is a thin forwarding wrapper ($hotk_lines lines)"
else
    fail "3.1 workstation-hotkeys is not a thin forwarding wrapper: lines=$hotk_lines"
fi

# 3.2: workstation-hotkeys json produces identical output to workstation-keybindings json
json_keyb="$("$ROOT/bin/workstation-keybindings" json)"
json_hotk="$("$ROOT/bin/workstation-hotkeys" json)"
if [[ "$json_keyb" == "$json_hotk" && -n "$json_keyb" ]]; then
    pass "3.2 workstation-hotkeys json produces output identical to workstation-keybindings json"
else
    fail "3.2 JSON output mismatch between keybindings and hotkeys wrapper"
fi
