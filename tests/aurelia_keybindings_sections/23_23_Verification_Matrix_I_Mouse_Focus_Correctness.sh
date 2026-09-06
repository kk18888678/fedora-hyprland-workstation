section "23. Verification Matrix I: Mouse & Focus Correctness"

# 23.1: Mouse selection in KeybindingRow: single click focuses window and updates index without closing
row_qml="$ROOT/dotfiles/aurelia/components/keybindings/KeybindingRow.qml"
if grep -q 'onClicked: function(mouse)' "$row_qml" && \
   grep -q 'keybindingsModel.selectedIndex = rowRoot.index' "$row_qml" && \
   grep -q 'ListView.view.forceActiveFocus()' "$row_qml" && \
   ! grep -q 'windowRoot.visible = false' <(sed -n '/onClicked: function(mouse)/,/^    }/p' "$row_qml"); then
    pass "23.1 single click on row selects item and focuses view without dismissing palette"
else
    fail "23.1 single click row focus logic missing or dismisses window in KeybindingRow.qml"
fi

# 23.2: A type click owns navigation; application clicks only select
if ! grep -q 'onDoubleClicked: {' "$row_qml" && \
   grep -q 'viewAtClick' "$row_qml" && \
   grep -q 'viewAtClick === "add_action_type"' "$row_qml" && \
   grep -q 'windowRoot.activateSelected("mouse")' "$row_qml"; then
    pass "23.2 click ownership prevents cross-view double-click fallthrough and keeps app selection non-activating"
else
    fail "23.2 click ownership or application-picker safety missing in KeybindingRow.qml"
fi

# 23.3: Tab and cursor keys keep mouse selection and keyboard selection synchronized
if grep -q 'modelController.selectNext()' "$qml_action_list" && \
   grep -q 'modelController.selectPrevious()' "$qml_action_list" && \
   grep -q 'listView.positionViewAtIndex(actionListRoot.modelController.selectedIndex' "$qml_action_list" && \
   grep -q 'actionList.listView.positionViewAtIndex(keybindingsModel.selectedIndex' "$qml_window"; then
    pass "23.3 keyboard navigation synchronizes selection and viewport position with mouse selection"
else
    fail "23.3 selection synchronization missing in KeybindingsWindow.qml"
fi

# 23.4: Outside click dismissal: clicking outside surfaceCard dismisses keybindings frame
if grep -q 'id: outsideDismissArea' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'windowRoot.visible = false' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'anchors.centerIn: parent' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsWindow.qml"; then
    pass "23.4 outside click dismiss area closes keybindings frame and centers surfaceCard"
else
    fail "23.4 outside click dismiss area missing or incomplete in KeybindingsWindow.qml"
fi
