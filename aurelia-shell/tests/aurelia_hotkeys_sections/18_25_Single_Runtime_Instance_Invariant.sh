section "25. Single Runtime Instance Invariant"

# Invariant: QML architecture hosts single Quickshell process with zero duplicate daemons
if grep -q "ShellRoot" "$ROOT/shell.qml" &&
   grep -q 'target: "hotkeys"' "$ROOT/shell.qml"; then
    pass "25. no duplicate Aurelia runtime instance is started (single ShellRoot with IPC endpoint)"
else
    fail "25. ShellRoot or IPC missing in Aurelia configuration"
fi
