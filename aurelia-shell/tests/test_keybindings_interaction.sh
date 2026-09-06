#!/usr/bin/env bash

# Static regression checks for keyboard routing and the lightweight UI pass.

set -Eeuo pipefail

ui_root="$ROOT/plugins/aurelia.keybindings/ui"
window_qml="$ui_root/KeybindingsWindow.qml"
header_qml="$ui_root/KeybindingsHeader.qml"
list_qml="$ui_root/KeybindingsActionList.qml"
settings_qml="$ui_root/KeybindingsSettings.qml"
row_qml="$ui_root/KeybindingsPreferenceRow.qml"
config_qml="$ui_root/KeybindingsConfig.qml"

section "Keybindings Input Routing"

if grep -q 'function beginSearch(value)' "$header_qml" &&
   grep -q 'Qt.callLater' "$header_qml" &&
   grep -q 'windowController.beginSearch' "$list_qml" &&
   grep -q 'event.accepted = true' "$list_qml"; then
    pass "type-to-search defers focus and claims the originating key event once"
else
    fail "type-to-search focus/event ownership regression guard failed"
fi

if grep -q 'focusActiveView("bound")' "$window_qml" &&
   grep -q 'focusList()' "$window_qml" &&
   ! grep -q 'if (selectedIndex === 0)' "$list_qml"; then
    pass "landing and application lists start keyboard-focused without forcing search focus"
else
    fail "list focus/search ownership remains coupled"
fi

section "Settings Navigation Bounds"

if grep -q 'function selectRow(index: int)' "$settings_qml" &&
   grep -q 'Math.max(0, Math.min(totalRows - 1, index))' "$settings_qml" &&
   grep -q 'Qt.Key_Home' "$settings_qml" &&
   grep -q 'Qt.Key_End' "$settings_qml" &&
   grep -q 'if (selectedIndex === 0)' "$settings_qml" &&
   grep -q 'Math.max(0, Math.min(maxY, nextY))' "$settings_qml"; then
    pass "settings navigation clamps selection and scrolls to exact bounds"
else
    fail "settings navigation bounds regression guard failed"
fi

if [[ -f "$row_qml" ]] &&
   grep -q 'KeybindingsPreferenceRow' "$settings_qml" &&
   grep -q 'KeybindingsPreferenceRow 1.0' "$ui_root/qmldir"; then
    pass "settings presentation is separated into a reusable lightweight row"
else
    fail "settings row presentation separation is incomplete"
fi

if grep -q 'readonly property string shortcutSet:.*ALT + S' "$ROOT/theme/Theme.qml" &&
   grep -q 'readonly property string shortcutUnset:.*ALT + U' "$ROOT/theme/Theme.qml" &&
   grep -q 'readonly property int rowSpacing: 8' "$config_qml" &&
   grep -q 'text: "← Back"' "$settings_qml"; then
    pass "settings shortcuts, vertical spacing, and right-aligned Back affordance are explicit"
else
    fail "settings shortcut/spacing/back layout regression guard failed"
fi

section "Keybindings Minimal UI"

if grep -q 'uiRevision: "2026.09.06.r7"' "$config_qml" &&
   grep -q 'readonly property bool searchVisible' "$header_qml" &&
   grep -q 'visible: headerRoot.searchVisible' "$header_qml" &&
   grep -q 'searchVisible: headerVisible' "$header_qml" &&
   grep -q 'focusActiveView("bound")' "$window_qml" &&
   grep -q 'searchInput.focus = false' "$header_qml" &&
   ! grep -q 'searchInput.clearFocus' "$header_qml" &&
   grep -q 'border.width: cardRoot.selected ?' "$ui_root/KeybindingsActionTypeCard.qml"; then
    pass "search remains visible without initial focus and Add Action uses balanced selected-state styling"
else
    fail "minimal Keybindings UI regression guard failed"
fi
