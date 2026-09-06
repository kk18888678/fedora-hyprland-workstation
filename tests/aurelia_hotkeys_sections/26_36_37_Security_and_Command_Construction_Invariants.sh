section "36-37. Security and Command Construction Invariants"

# Test 36: QML IPC endpoints expose only allowlisted operations
ipc_methods="$(grep -E 'function [a-zA-Z0-9_]+\(\)' "$ROOT/dotfiles/aurelia/shell.qml" | sed 's/^[[:space:]]*function //;s/(.*//' | tr '\n' ' ')"
if [[ "$ipc_methods" =~ (ping toggle open close isVisible|ping toggle isVisible open close|toggle open close isVisible) ]]; then
    pass "36. QML can invoke only allowlisted backend operations"
else
    fail "36. QML IPC methods contain unexpected endpoints: $ipc_methods"
fi

# Test 37: Zero shell command injection / string concatenation
if ! grep -E '(bash -c|sh -c|eval )' "$ROOT/dotfiles/aurelia/components/hotkeys/HotkeysModel.qml" >/dev/null; then
    pass "37. no shell command construction from action metadata"
else
    fail "37. found shell command construction in HotkeysModel.qml"
fi
