#!/usr/bin/env bash

# Static and command-contract checks for the minimal Screenshot bar slice.
# The popup intentionally exposes two capture actions; customization remains
# available through compact delay and pointer controls.

set -Eeuo pipefail

plugin_root="$ROOT/plugins/aurelia.screenshot"
bar_root="$ROOT/plugins/aurelia.bar"
capture_bin="$ROOT/bin/aurelia-screenshot"
shared_ui_root="$ROOT/ui"

section "Screenshot Plugin Contract"

if [[ -f "$plugin_root/manifest.json" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.screenshot" and
       (.kinds == ["bar-widget"]) and
       .entryPoints["bar-widget"] == "ui/ScreenshotBarWidget.qml" and
       ((.description | ascii_downcase | contains("window")) | not)
   ' "$plugin_root/manifest.json" >/dev/null; then
    pass "Screenshot plugin declares a minimal bar-only entry point"
else
    fail "Screenshot plugin manifest is missing, invalid, or advertises removed window capture"
fi

if [[ -x "$capture_bin" ]] &&
   "$capture_bin" --help >/dev/null 2>&1 &&
   grep -q 'capture <full|region>' "$capture_bin" &&
   grep -q 'select region' "$capture_bin" &&
   ! grep -Eiq 'smart|windows?|capture_mode.*window|selector.*window' "$capture_bin" &&
   grep -q 'grim' "$capture_bin" &&
   grep -q 'slurp' "$capture_bin" &&
   grep -q 'hyprpicker' "$capture_bin" &&
   grep -q 'screen_freeze' "$capture_bin" &&
   grep -q 'hide_cursor_for_capture' "$capture_bin" &&
   grep -q 'wl-copy' "$capture_bin" &&
   grep -q 'cursor:no_hardware_cursors' "$capture_bin" &&
   grep -q 'cursor:inactive_timeout' "$capture_bin" &&
   grep -q 'timeout' "$capture_bin" &&
   grep -q 'delay=3' "$capture_bin" &&
   grep -q 'show_pointer=0' "$capture_bin" &&
   grep -q -- '--show-pointer' "$capture_bin" &&
   grep -q -- '--geometry' "$capture_bin" &&
   grep -q '.aurelia-screenshot-XXXXXX.png' "$capture_bin" &&
   grep -q 'mv -f -- "$capture_path" "$published_path"' "$capture_bin" &&
   grep -q '"$capture_mode" == "full"' "$capture_bin" &&
   ! grep -Eq '(^|[[:space:];])eval([[:space:];]|$)' "$capture_bin"; then
    pass "Screenshot backend keeps bounded full/region capture without dead window code or eval"
else
    fail "Screenshot backend mode or safety contract is incomplete"
fi

menu_qml="$plugin_root/ui/ScreenshotMenuPopup.qml"
panel_qml="$plugin_root/ui/ScreenshotPanel.qml"
selection_qml="$plugin_root/ui/ScreenshotSelectionOverlay.qml"
button_qml="$shared_ui_root/AureliaActionButton.qml"
icon_qml="$shared_ui_root/AureliaIcon.qml"

if [[ -f "$button_qml" && -f "$icon_qml" ]] &&
   grep -q 'AureliaActionButton 1.0 AureliaActionButton.qml' "$shared_ui_root/qmldir" &&
   grep -q 'AureliaIcon 1.0 AureliaIcon.qml' "$shared_ui_root/qmldir" &&
   grep -q 'Theme.surfaceElevated' "$button_qml" &&
   grep -q 'Theme.borderActive' "$button_qml" &&
   grep -q 'signal triggered' "$button_qml" &&
   [[ "$(grep -c 'AureliaActionButton {' "$menu_qml")" -eq 2 ]] &&
   grep -q 'popupWidth: 280' "$menu_qml" &&
   grep -q 'popupHeight: controller ? controller.popupHeight : 228' "$menu_qml" &&
   grep -q 'label: "Full Screen"' "$menu_qml" &&
   grep -q 'label: "Selection"' "$menu_qml" &&
   grep -q 'startRegionSelection' "$menu_qml" &&
   grep -q 'Delay' "$menu_qml" &&
   grep -q 'Pointer' "$menu_qml" &&
   ! grep -Eiq 'GridLayout|ListView|window|windows|region-ready|Take Screenshot with Delay|Full screen \+ delay|capturePendingRegion|startWindowSelection' "$menu_qml"; then
    pass "Screenshot popup uses the compact shared action-button design with exactly two capture actions"
else
    fail "Screenshot popup layout, design primitive, or removed-action cleanup is incomplete"
fi

if grep -q 'readonly property int popupHeight: 228' "$panel_qml" &&
   grep -q 'property int delaySeconds: 0' "$panel_qml" &&
   grep -q 'function startRegionSelection' "$panel_qml" &&
   grep -q 'function regionSelectionFinished' "$panel_qml" &&
   grep -q 'capture("region", delaySeconds, selectedGeometry)' "$panel_qml" &&
   grep -q 'capture("full", popup.controller.delaySeconds' "$menu_qml" &&
   ! grep -Eiq 'window|windows|region-ready|pendingGeometry|pendingWindow|capturePendingRegion|startWindowSelection|captureWindow' "$panel_qml" &&
   ! grep -Eiq 'window|windows|region-ready|capturePendingRegion|startWindowSelection|captureWindow' "$menu_qml"; then
    pass "Screenshot controller retains delay/pointer customization and only full/region capture paths"
else
    fail "Screenshot controller still contains removed capture paths or lacks the compact flow"
fi

if grep -q 'selectionDragging' "$selection_qml" &&
   grep -q 'native region geometry' "$selection_qml" &&
   grep -q 'Keys.onPressed' "$selection_qml" &&
   ! grep -Eiq 'text:.*esc' "$menu_qml" "$selection_qml" &&
   grep -q 'region selection cancelled' "$panel_qml" &&
   grep -q 'cursorShape: Qt.CrossCursor' "$selection_qml" &&
   grep -q 'FocusScope' "$selection_qml" &&
   grep -q 'selectionKeyboardScope.forceActiveFocus' "$selection_qml" &&
   grep -q 'function quickRegion' "$plugin_root/ui/ScreenshotBarWidget.qml" &&
   grep -q 'function quickRegion' "$panel_qml" &&
   grep -q 'startRegionSelection()' "$panel_qml" &&
   ! grep -Eiq 'smart|window|windows' "$menu_qml" "$panel_qml" "$capture_bin"; then
    pass "Widget and shortcut region entry points share the crosshair/Escape-safe overlay flow"
else
    fail "Region capture overlay or unified quick-region compatibility path is incomplete"
fi

if grep -q 'captureProcess' "$plugin_root/ui/ScreenshotBarWidget.qml" &&
   grep -q 'duration_ms' "$plugin_root/ui/ScreenshotBarWidget.qml" &&
   grep -q 'captureRequested' "$panel_qml" &&
   grep -q 'captureCompleted' "$panel_qml" &&
   grep -q 'ScreenshotPanel.qml' "$plugin_root/ui/ScreenshotBarWidget.qml" &&
   grep -q 'camera-photo' "$plugin_root/ui/ScreenshotBarWidget.qml" &&
   grep -q 'aurelia.screenshot' "$plugin_root/ui/ScreenshotBarWidget.qml" &&
   grep -q 'import "../../../ui"' "$plugin_root/ui/ScreenshotBarWidget.qml" &&
   grep -q 'ToolTip' "$plugin_root/ui/ScreenshotBarWidget.qml" &&
   grep -q 'Full Screen or Selection' "$plugin_root/ui/ScreenshotBarWidget.qml" &&
   grep -q 'AureliaIcon' "$plugin_root/ui/ScreenshotBarWidget.qml" &&
   grep -q 'MultiEffect' "$icon_qml" &&
   grep -q 'colorizationColor' "$icon_qml" &&
   grep -q 'asynchronous: false' "$icon_qml" &&
   ! grep -q 'asynchronous: true' "$icon_qml"; then
    pass "Bar widget owns capture lifecycle, tooltip, and theme-aware icon visibility"
else
    fail "Screenshot bar lifecycle, tooltip, or icon contrast contract is incomplete"
fi

section "Resident Bar Contract"

if [[ -f "$bar_root/manifest.json" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.bar" and (.kinds == ["bar"]) and .keepLoaded == true and .entryPoints.bar == "Bar.qml"' "$bar_root/manifest.json" >/dev/null; then
    pass "Aurelia Bar declares a resident bar manifest"
else
    fail "Aurelia Bar manifest is missing or invalid"
fi

if grep -q 'target: "aurelia.bar"' "$bar_root/Bar.qml" &&
   grep -q 'BarWidgetRow' "$bar_root/Bar.qml" &&
   grep -q 'BarCenter' "$bar_root/Bar.qml" &&
   grep -q 'barSize: 26' "$bar_root/Bar.qml" &&
   grep -q 'AureliaLogo' "$bar_root/Bar.qml" &&
   grep -q 'centerAnchor' "$bar_root/Bar.qml" &&
   grep -q 'visible: true' "$bar_root/Bar.qml" &&
   [[ -f "$bar_root/BarWidgetSlot.qml" && -f "$bar_root/BarWidgetRow.qml" && -f "$bar_root/BarCenter.qml" ]] &&
   grep -q 'entryPointUrl(root.pluginId, "bar-widget")' "$bar_root/BarWidgetSlot.qml"; then
    pass "Bar exposes manifest-backed theme-aware widgets and the compact screenshot action"
else
    fail "Aurelia Bar screenshot action or lifecycle contract is incomplete"
fi
