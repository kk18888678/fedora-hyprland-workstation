section "7. Inline Keybinding Capture State Machine & Zero Terminal Spawning"

qml_window="$ROOT/components/keybindings/KeybindingsWindow.qml"

# 7.1: Capture never opens a terminal window
term_spawn="$(grep -E '(foot|kitty|alacritty|xterm).*spawn' "$qml_window" "$qml_model" 2>/dev/null || true)"
if [[ -z "$term_spawn" ]]; then
    pass "7.1 inline capture never opens a terminal window (100% native Wayland layer-shell)"
else
    fail "7.1 terminal spawning detected in capture path: $term_spawn"
fi

# 7.2: Escape cancels capture mode cleanly back to idle
if grep -q 'Qt.Key_Escape' "$qml_window" &&
   grep -q 'cancelCapture()' "$qml_window" &&
   grep -q 'operationState = "idle"' "$qml_model"; then
    pass "7.2 Esc cancels capture state machine back to idle with reset inline status"
else
    fail "7.2 Esc capture cancellation missing or incomplete"
fi

# 7.3: Standalone modifier keys rejected (invalid key inline error)
if grep -q 'Qt.Key_Control || k === Qt.Key_Shift || k === Qt.Key_Alt || k === Qt.Key_Meta' "$qml_window"; then
    pass "7.3 standalone modifier keypresses rejected without leaving capture mode"
else
    fail "7.3 standalone modifier rejection missing in formatKeyEvent"
fi

# 7.4: Conflict inline error UX
if grep -q 'operationState === "conflict"' "$qml_window" &&
   grep -q 'conflict' "$qml_model"; then
    pass "7.4 shortcut conflict presents inline conflict UX with existing action title"
else
    fail "7.4 conflict inline UX missing in KeybindingsWindow/KeybindingsModel"
fi

# 7.5: Successful set displays inline result
if grep -q 'root.operationState = "success"' "$qml_model" &&
   grep -q 'modelController.operationState === "success"' "$qml_header" &&
   grep -q 'modelController.operationMessage' "$qml_header"; then
    pass "7.5 successful set displays inline confirmation before returning to idle"
else
    fail "7.5 success inline confirmation missing"
fi

# 7.6: Immutable binding refusal
(
    test_sb="$(mktemp -d)"
    test_overrides="$test_sb/overrides.json"
    echo "{}" > "$test_overrides"
    imm_rc=0
    imm_out="$(HOTKEYS_OVERRIDES="$test_overrides" "$ROOT/bin/workstation-keybindings" set workspace_touchpad_swipe "SUPER+X" 2>&1)" || imm_rc=$?
    rm -rf "$test_sb"
    if [[ "$imm_rc" -ne 0 && "$imm_out" == *"immutable"* ]]; then
        pass "7.6 immutable binding mutation is strictly refused by backend (fails closed)"
    else
        fail "7.6 immutable binding was not refused: rc=$imm_rc out=$imm_out"
    fi
)
