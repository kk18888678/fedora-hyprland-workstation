section "20. Verification Matrix F: Input Inhibition & Capture Isolation"

# 20.1: ShortcutInhibitor component declared in KeybindingsWindow.qml
if grep -q 'ShortcutInhibitor {' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'window: windowRoot' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -qE 'enabled:.*windowRoot\.isRecording' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'onCancelled: windowRoot.cancelCapture()' "$ROOT/components/keybindings/KeybindingsWindow.qml"; then
    pass "20.1 ShortcutInhibitor declared with dynamic enablement and onCancelled handler"
else
    fail "20.1 ShortcutInhibitor declaration missing or incomplete in KeybindingsWindow.qml"
fi

# 20.2: WlrLayershell.keyboardFocus exclusivity during capture
if grep -qE 'WlrLayershell\.keyboardFocus:.*windowRoot\.isRecording \? WlrKeyboardFocus\.Exclusive : WlrKeyboardFocus\.OnDemand' "$ROOT/components/keybindings/KeybindingsWindow.qml"; then
    pass "20.2 WlrLayershell.keyboardFocus acquires Exclusive focus during capture and OnDemand when idle"
else
    fail "20.2 dynamic Exclusive keyboard focus missing in KeybindingsWindow.qml"
fi

# 20.3: Fail-safe inhibition release on cancellation
if grep -q 'function cancelCapture()' "$qml_window" && \
   grep -q 'captureState = "idle"' "$qml_window"; then
    pass "20.3 cancelCapture unconditionally releases capture and restores OnDemand focus"
else
    fail "20.3 cancelCapture release logic incomplete"
fi
