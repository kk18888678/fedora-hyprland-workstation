section "6. Process Concurrency & State Bounds in Quickshell Model"

# 6.1: KeybindingsModel guards against concurrent re-entry on reload()
if grep -q 'if (root.isReloading) return;' "$qml_model" &&
   grep -q 'property bool isReloading:' "$qml_model"; then
    pass "6.1 reload() is bounded with isReloading guard against concurrent fetch re-entry"
else
    fail "6.1 reload() missing isReloading guard in KeybindingsModel"
fi

# 6.2: KeybindingsModel guards against concurrent runSelected() re-entry
if grep -q 'if (root.isExecuting) return;' "$qml_model" &&
   grep -q 'property bool isExecuting:' "$qml_model"; then
    pass "6.2 runSelected() is bounded with isExecuting guard"
else
    fail "6.2 runSelected() missing isExecuting guard in KeybindingsModel"
fi

# 6.3: KeybindingsModel guards against concurrent setShortcut() / unsetShortcut()
if grep -q 'if (root.isMutating) return;' "$qml_model" &&
   grep -q 'property bool isMutating:' "$qml_model"; then
    pass "6.3 setShortcut() and unsetShortcut() are bounded with isMutating guard"
else
    fail "6.3 set/unset operations missing isMutating guard in KeybindingsModel"
fi

# 6.4: Rapid IPC toggle calls do not spawn duplicate Quickshell daemons
(
    mock_dir="$(mktemp -d)"
    mock_log="$(mktemp)"
    cat << "MOCK_EOF" > "$mock_dir/qs"
#!/usr/bin/env bash
if [[ "$1" == "ipc" ]]; then
    if [[ "$*" == *"ping"* ]]; then
        echo "true"
    fi
    echo "toggle" >> "$MOCK_LOG"
    exit 0
elif [[ "$1" == "--no-duplicate" ]]; then
    echo "daemon_start" >> "$MOCK_LOG"
    exit 0
fi
exit 0
MOCK_EOF
    chmod +x "$mock_dir/qs"
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" "$ROOT/bin/workstation-keybindings" toggle >/dev/null 2>&1
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" "$ROOT/bin/workstation-keybindings" toggle >/dev/null 2>&1
    daemons="$(grep -c '^daemon_start$' "$mock_log" || true)"
    rm -rf "$mock_dir" "$mock_log"
    if [[ "$daemons" -eq 0 ]]; then
        pass "6.4 rapid warm IPC toggles do not spawn secondary Quickshell instances"
    else
        fail "6.4 rapid IPC toggles spawned duplicate instance: daemons=$daemons"
    fi
)
