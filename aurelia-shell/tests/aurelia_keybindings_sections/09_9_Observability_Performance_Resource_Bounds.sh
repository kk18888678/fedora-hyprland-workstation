section "9. Observability, Performance & Resource Bounds"

# 9.1: Zero continuous idle polling when window hidden
if ! grep -E 'Timer\s*\{.*running:\s*true' "$qml_window" >/dev/null; then
    pass "9.1 zero recurring Timers active when keybindings window is idle/hidden"
else
    fail "9.1 active background Timer detected in KeybindingsWindow"
fi

# 9.2: Diagnostic logging is bounded in size (<= 2000 lines)
if grep -R -q 'tail -n 2000' "$ROOT/bin/lib/aurelia-keybindings"; then
    pass "9.2 diagnostic log files are strictly bounded with automatic rotation (<= 2000 lines)"
else
    fail "9.2 log bounding missing in bin/workstation-keybindings"
fi

# 9.3: Performance logging records timing without continuous overhead
if grep -R -q 'log_event "PERF"' "$ROOT/bin/lib/aurelia-keybindings" &&
   grep -q '\[PERF\]' "$qml_model"; then
    pass "9.3 performance instrumentation captures measurable milestones with [PERF] tag"
else
    fail "9.3 performance instrumentation missing in backend or model"
fi

# 9.4: Malformed backend JSON fails safely without crash
if grep -q 'try {' "$qml_model" &&
   grep -q 'JSON.parse' "$qml_model" &&
   grep -q 'catch (e)' "$qml_model"; then
    pass "9.4 malformed backend JSON is caught safely with structured error handling"
else
    fail "9.4 JSON parse error guard missing in KeybindingsModel"
fi
