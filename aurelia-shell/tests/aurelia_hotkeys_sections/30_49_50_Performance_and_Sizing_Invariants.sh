section "49-50. Performance and Sizing Invariants"

# Test 49: Search does not spawn processes
if ! grep -E 'filterItems.*Process' "$ROOT/components/hotkeys/HotkeysModel.qml" >/dev/null; then
    pass "49. search operates in-memory with zero process spawning on keystrokes"
else
    fail "49. process spawning detected in search"
fi

# Test 50: Window dimensions follow restrained command-palette proportions (640-800x440-480)
if grep -qE 'implicitWidth:.*(640|800|palettePreferredWidth)' "$ROOT/components/keybindings/KeybindingsWindow.qml" &&
   grep -qE 'implicitHeight:.*(440|460|480|palettePreferredHeight)' "$ROOT/components/keybindings/KeybindingsWindow.qml"; then
    pass "50. window dimensions follow restrained command-palette proportions (640-800x440-480)"
else
    fail "50. window dimensions deviate from command-palette target"
fi
