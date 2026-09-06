section "44-48. Omarchy-Inspired UI and Presentation Invariants"

# Test 44: No keycap badge or pill rectangles in HotkeyRow
if ! grep -E '(Rectangle \{.*id: keyBadge|border\.color: rowRoot\.isSelected)' "$ROOT/components/hotkeys/HotkeyRow.qml" >/dev/null; then
    pass "44. no keycap-per-modifier UI or row borders introduced (clean two-column layout)"
else
    fail "44. found keycap badge or row borders in HotkeyRow.qml"
fi

# Test 45: Row display renders shortcut + separator arrow + action title
if grep -q 'text: rowRoot.formattedShortcut()' "$ROOT/components/hotkeys/HotkeyRow.qml" &&
   grep -q 'text: "→"' "$ROOT/components/hotkeys/HotkeyRow.qml" &&
   grep -q 'text: rowRoot.modelData ? (rowRoot.modelData.description || "") : ""' "$ROOT/components/hotkeys/HotkeyRow.qml"; then
    pass "45. row display has shortcut + arrow separator + action presentation"
else
    fail "45. row display missing shortcut, arrow, or action presentation"
fi

# Test 46: Search area uses minimal keybindings_ prompt style without boxed rectangle
if grep -q 'text: "keybindings_"' "$ROOT/components/keybindings/KeybindingsHeader.qml" &&
   ! grep -E 'Rectangle \{.*Search shortcuts' "$ROOT/components/keybindings/KeybindingsHeader.qml" >/dev/null; then
    pass "46. search area uses minimal keybindings_ prompt style without boxed rectangle"
else
    fail "46. search area has boxed rectangle or missing keybindings_ prompt"
fi

# Test 47: Footer is textual/hint-based and not modeled as action buttons
if grep -q 'text: "↵"' "$ROOT/components/keybindings/KeybindingsFooter.qml" &&
   grep -q 'text: Theme.shortcutSet' "$ROOT/components/keybindings/KeybindingsFooter.qml" &&
   grep -q 'text: Theme.shortcutUnset' "$ROOT/components/keybindings/KeybindingsFooter.qml" &&
   grep -q 'text: "ESC"' "$ROOT/components/keybindings/KeybindingsFooter.qml" &&
   ! grep -E 'Rectangle \{.*Layout\.preferredWidth: (altSText|sText)' "$ROOT/components/keybindings/KeybindingsFooter.qml" >/dev/null; then
    pass "47. footer is textual/hint-based, not modeled as action buttons"
else
    fail "47. footer contains button boxes or missing keyboard hints"
fi

# Test 48: No category headings/IDs/commands appear in normal row presentation
if ! grep -E '(category|action_id|command_argv)' "$ROOT/components/hotkeys/HotkeyRow.qml" >/dev/null; then
    pass "48. no category headings/IDs/commands appear in normal row presentation"
else
    fail "48. HotkeyRow leaks category headings or internal commands"
fi
