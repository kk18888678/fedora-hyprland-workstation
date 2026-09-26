#!/usr/bin/env bash

# Static and command-contract checks for the core-owned Screenshot capability.
# The capability moved from the bar-widget plugin into the resident core
# service so the popup intentionally exposes two capture actions while the
# bar widget remains a thin view and the shortcut survives plugin disable.

set -Eeuo pipefail

plugin_root="$ROOT/plugins/aurelia.screenshot"
bar_root="$ROOT/plugins/aurelia.bar"
capture_bin="$ROOT/bin/aurelia-screenshot"
shared_ui_root="$ROOT/ui"
service_qml="$ROOT/services/ScreenshotService.qml"
router_qml="$ROOT/services/ShellCallRouter.qml"
widget_qml="$plugin_root/ui/ScreenshotBarWidget.qml"

section "Screenshot Plugin Contract"

if [[ -f "$plugin_root/manifest.json" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.screenshot" and
       (.kinds == ["bar-widget"]) and
       .entryPoints.barWidget == "ui/ScreenshotBarWidget.qml" and
       ((.description | ascii_downcase | contains("window")) | not)
   ' "$plugin_root/manifest.json" >/dev/null; then
    pass "Screenshot plugin declares a minimal bar-only entry point"
else
    fail "Screenshot plugin manifest is missing, invalid, or advertises removed window capture"
fi

if [[ -x "$capture_bin" ]] &&
   "$capture_bin" --help >/dev/null &&
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
   grep -q 'Pictures"' "$capture_bin" &&
   grep -q 'Screenshots' "$capture_bin" &&
   ! grep -q 'runtime_dir=.*tmp' "$capture_bin" &&
   grep -q "mv -f -- \"\$capture_path\" \"\$published_path\"" "$capture_bin" &&
   grep -q "\"\$capture_mode\" == \"full\"" "$capture_bin" &&
   ! grep -Eq '(^|[[:space:];])eval([[:space:];]|$)' "$capture_bin"; then
    pass "Screenshot backend keeps bounded full/region capture without dead window code or eval"
else
    fail "Screenshot backend mode or safety contract is incomplete"
fi

menu_qml="$shared_ui_root/ScreenshotMenuPopup.qml"
panel_qml="$shared_ui_root/ScreenshotPanel.qml"
selection_qml="$shared_ui_root/ScreenshotSelectionOverlay.qml"
button_qml="$shared_ui_root/AureliaActionButton.qml"
icon_qml="$shared_ui_root/AureliaIcon.qml"

if [[ -f "$button_qml" && -f "$icon_qml" ]] &&
   grep -q 'AureliaActionButton 1.0 AureliaActionButton.qml' "$shared_ui_root/qmldir" &&
   grep -q 'AureliaIcon 1.0 AureliaIcon.qml' "$shared_ui_root/qmldir" &&
   grep -q 'ScreenshotMenuPopup 1.0 ScreenshotMenuPopup.qml' "$shared_ui_root/qmldir" &&
   grep -q 'ScreenshotPanel 1.0 ScreenshotPanel.qml' "$shared_ui_root/qmldir" &&
   grep -q 'ScreenshotSelectionOverlay 1.0 ScreenshotSelectionOverlay.qml' "$shared_ui_root/qmldir" &&
   grep -q 'Theme.controls.normalFill' "$button_qml" &&
   grep -q 'Theme.controls.hoverBorder' "$button_qml" &&
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
   grep -q 'function quickRegion' "$service_qml" &&
   grep -q 'function quickRegion' "$panel_qml" &&
   grep -q 'startRegionSelection()' "$panel_qml" &&
   grep -q 'ScreenshotSelectionOverlay.qml' "$service_qml" &&
   ! grep -Eiq 'smart|window|windows' "$menu_qml" "$panel_qml" "$capture_bin"; then
    pass "Core service and shortcut region entry points share the crosshair/Escape-safe overlay flow"
else
    fail "Region capture overlay or core quick-region compatibility path is incomplete"
fi

# The bar widget is a pure view. The capture lifecycle belongs to the core
# service, so these negative assertions are the ownership boundary.
if grep -Fq 'glyph: "󰄀"' "$widget_qml" &&
   grep -q 'aurelia.screenshot' "$widget_qml" &&
   grep -q 'import "../../../ui"' "$widget_qml" &&
   grep -q 'AureliaToolTip' "$widget_qml" &&
   grep -q 'Full Screen or Selection' "$widget_qml" &&
   grep -q 'AureliaIcon' "$widget_qml" &&
   grep -q 'activePopoutId === "aurelia.screenshot"' "$widget_qml" &&
   grep -q 'shell.call("aurelia.screenshot"' "$widget_qml" &&
   ! grep -q 'Process {' "$widget_qml" &&
   ! grep -q 'captureProcess' "$widget_qml" &&
   ! grep -q 'captureStage' "$widget_qml" &&
   ! grep -q 'pendingCaptureRequest' "$widget_qml" &&
   ! grep -q 'publishScreenshot' "$widget_qml" &&
   ! grep -q 'ScreenshotPanel.qml' "$widget_qml" &&
   ! grep -q 'ScreenshotMenuPopup' "$widget_qml" &&
   ! grep -q 'ScreenshotSelectionOverlay' "$widget_qml" &&
   ! grep -q 'downloadScreenshot' "$widget_qml" &&
   grep -q 'MultiEffect' "$icon_qml" &&
   grep -q 'colorizationColor' "$icon_qml" &&
   grep -q 'Text.NativeRendering' "$icon_qml" &&
   grep -q 'sourcePixelRatio: Math.max(1, Screen.devicePixelRatio)' "$icon_qml" &&
   grep -q 'asynchronous: false' "$icon_qml" &&
   ! grep -q 'asynchronous: true' "$icon_qml"; then
    pass "Bar widget is a thin affordance while the core service owns the capture lifecycle"
else
    fail "Screenshot bar widget still owns capture state or the icon contrast contract regressed"
fi

if grep -q 'Process {' "$service_qml" &&
   grep -q 'waitForEnd: true' "$service_qml" &&
   grep -q 'duration_ms' "$service_qml" &&
   grep -q 'ScreenshotPanel {' "$service_qml" &&
   grep -q 'ScreenshotMenuPopup.qml' "$service_qml" &&
   grep -q 'ScreenshotSelectionOverlay.qml' "$service_qml" &&
   grep -q 'publishScreenshot' "$service_qml" &&
   grep -q 'function cancelCapture' "$service_qml" &&
   grep -q 'target: "aurelia.screenshot"' "$service_qml" &&
   grep -q 'function ping(): string' "$service_qml" &&
   grep -q 'function open(payloadJson: string): string' "$service_qml" &&
   grep -q 'function close(): string' "$service_qml" &&
   grep -q 'function toggle(payloadJson: string): string' "$service_qml" &&
   grep -q 'function isVisible(): string' "$service_qml" &&
   grep -q 'function quickRegion(): string' "$service_qml" &&
   grep -q 'function quickScreen(): string' "$service_qml" &&
   grep -q 'function capture(payloadJson: string): string' "$service_qml" &&
   ! grep -q 'plugins/aurelia.screenshot' "$service_qml" &&
   [[ -f "$router_qml" ]] &&
   grep -q 'screenshotService' "$router_qml" &&
   grep -q 'screenshot-unavailable' "$router_qml" &&
   grep -q 'shellCallRouter.call(pluginHost' "$ROOT/shell.qml" &&
   grep -q 'ScreenshotService {' "$ROOT/shell.qml"; then
    pass "Core ScreenshotService owns the capture process, presentation surfaces, IPC target, and shell fallback"
else
    fail "Core screenshot service, IPC surface, or shell fallback is incomplete"
fi

section "Resident Bar Contract"

if [[ -f "$bar_root/manifest.json" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.bar" and (.kinds == ["bar"]) and .keepLoaded == true and .entryPoints.bar == "Bar.qml"' "$bar_root/manifest.json" >/dev/null; then
    pass "Aurelia Bar declares a resident bar manifest"
else
    fail "Aurelia Bar manifest is missing or invalid"
fi

if grep -q 'target: "aurelia.bar"' "$bar_root/Bar.qml" &&
   grep -q 'BarWidgetRow' "$bar_root/BarPanel.qml" &&
   grep -q 'BarCenter' "$bar_root/BarPanel.qml" &&
   grep -q 'barSize: vertical ? Theme.bar.sizeVertical : Theme.bar.sizeHorizontal' "$bar_root/Bar.qml" &&
   grep -q 'AureliaLogo' "$bar_root/BarPanel.qml" &&
   grep -q 'centerAnchor' "$bar_root/Bar.qml" &&
   grep -q 'visible: !remapGuard.remapping' "$bar_root/BarPanel.qml" &&
   grep -q 'model: Quickshell.screens' "$bar_root/Bar.qml" &&
   [[ -f "$bar_root/BarWidgetSlot.qml" && -f "$bar_root/BarWidgetRow.qml" && -f "$bar_root/BarCenter.qml" ]] &&
   grep -q 'entryPointUrl(root.pluginId, "bar-widget")' "$bar_root/BarWidgetSlot.qml"; then
    pass "Bar exposes manifest-backed theme-aware widgets and the compact screenshot action"
else
    fail "Aurelia Bar screenshot action or lifecycle contract is incomplete"
fi
