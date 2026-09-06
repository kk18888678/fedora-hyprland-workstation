section "34. Verification Matrix T: Interaction Model, Navigation & Input Theming"

# 34.1: Alt+A opens Add Action view without toggling back
if grep -q 'function openAddAction()' "$qml_win" && \
   grep -q 'keybindingsModel.activeView.indexOf("add_") === 0' "$qml_win" && \
   grep -q 'return' <(sed -n '/function openAddAction()/,/}/p' "$qml_win"); then
    pass "34.1 Alt+A opens Add Action view without toggling back into previous view"
else
    fail "34.1 Alt+A toggle-back prevention missing in KeybindingsWindow.qml"
fi

# 34.2: B or b navigates back in list/navigation context while search input permits typing b
if grep -q 'cmd === "back"' "$qml_win" && \
   grep -q 'windowRoot.goBack()' "$qml_win" && \
   ! grep -E 'event\.key === Qt\.Key_B([^_a-zA-Z]|$)' <(sed -n '/id: searchInput/,/RowLayout/p' "$qml_win"); then
    pass "34.2 B/b navigates back via authoritative router while search input allows standard b typing"
else
    fail "34.2 B-as-Back or search input typing isolation missing in KeybindingsWindow.qml"
fi

# 34.3: S and U shortcuts restricted to list context in bound/unbound view
if grep -q 'keybindingsModel.activeView === "bound" || keybindingsModel.activeView === "unbound"' "$qml_win" && \
   grep -q 'resolveSemanticCommand' "$qml_win" && \
   ! grep -q 'event.key === Qt.Key_S &&' <(sed -n '/id: searchInput/,/RowLayout/p' "$qml_win"); then
    pass "34.3 S/U shortcuts strictly restricted to list context and bound/unbound view"
else
    fail "34.3 S/U shortcut scoping missing or search input intercepts plain s/u in KeybindingsWindow.qml"
fi

# 34.4: Single-click activates add_action_type immediately; application rows only select
if grep -q 'keybindingsModel.selectedIndex = rowRoot.index' "$qml_row" && \
   grep -q 'viewAtClick === "add_action_type"' "$qml_row" && \
   grep -q 'windowRoot.activateSelected("mouse")' "$qml_row" && \
   ! grep -q 'onDoubleClicked: {' "$qml_row"; then
    pass "34.4 single-click activates add_action_type without double-click or app-picker fallthrough"
else
    fail "34.4 mouse interaction model check failed in KeybindingRow.qml"
fi

# 34.5: Executable / Script form uses Theme.input* tokens and entered text is high-contrast
if grep -q 'color: Theme.inputBg' "$qml_form" && \
   grep -q 'color: Theme.inputText' "$qml_form" && \
   grep -q 'border.color: execNameInput.activeFocus ? Theme.inputBorderFocused : Theme.inputBorder' "$qml_form" && \
   grep -q 'color: Theme.inputPlaceholder' "$qml_form" && \
   ! grep -q 'color: Theme.bgCard' "$qml_form"; then
    pass "34.5 Executable / Script form inputs use semantic Theme.input* tokens without undefined bgCard"
else
    fail "34.5 semantic input theming tokens missing or bgCard found in KeybindingsWindow.qml"
fi

# 34.6: Terminology is Executable / Script across UI and models
if grep -q 'Executable / Script' "$qml_model" && \
   grep -q 'Add Custom Executable / Script' "$qml_form" && \
   ! grep -q 'Binary / Shell' "$ROOT/components/keybindings/KeybindingsModel.qml"; then
    pass "34.6 Terminology is Executable / Script across UI, forms, and models"
else
    fail "34.6 legacy Binary / Shell terminology found or Executable / Script missing"
fi
