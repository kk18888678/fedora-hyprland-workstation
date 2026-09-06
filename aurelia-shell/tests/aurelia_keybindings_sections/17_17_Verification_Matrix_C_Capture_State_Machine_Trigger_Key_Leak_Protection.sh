section "17. Verification Matrix C: Capture State Machine & Trigger Key Leak Protection"

# 17.1: Pressing S enters entering_capture; initiating key cannot be captured
if grep -q 'property string captureState: "idle"' "$qml_window" && \
   grep -q 'captureState = "entering_capture"' "$qml_window" && \
   grep -q 'initiatingKey = triggerEvent.key' "$qml_window" && \
   grep -q 'if (captureState === "entering_capture")' "$qml_window"; then
    pass "17.1 pressing S enters entering_capture and sets initiatingKey to prevent self-capture leak"
else
    fail "17.1 entering_capture and trigger key leak protection missing in KeybindingsWindow.qml"
fi

# 17.2: Initiating key release transitions state to capture_armed
if grep -q 'function handleRecordingKeyRelease(event)' "$qml_window" && \
   grep -q 'captureState = "capture_armed"' "$qml_window" && \
   grep -q 'initiatingKey = 0' "$qml_window"; then
    pass "17.2 initiating key release transitions capture state machine to capture_armed"
else
    fail "17.2 capture_armed transition missing in KeybindingsWindow.qml"
fi

# 17.3: In capture_armed, candidate key combination proceeds to validation
if grep -q 'captureState = "validating"' "$qml_window" && \
   grep -q 'keybindingsModel.validateShortcut' "$qml_window"; then
    pass "17.3 armed combination transitions to validating state and calls asynchronous policy validation"
else
    fail "17.3 validation transition missing in KeybindingsWindow.qml"
fi

# 17.4: Esc cancels cleanly from any capture state back to idle with zero mutation
if grep -q 'if (event.key === Qt.Key_Escape)' "$qml_window" && \
   grep -q 'function cancelCapture()' "$qml_window" && \
   grep -q 'captureState = "idle"' "$qml_window"; then
    pass "17.4 Esc cancels capture cleanly from all states back to idle with zero mutation"
else
    fail "17.4 cancelCapture logic missing in KeybindingsWindow.qml"
fi
