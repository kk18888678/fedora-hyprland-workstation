#!/usr/bin/env bash

# Static and command-contract checks for the Screenshot + opt-in Bar slice.

set -Eeuo pipefail

plugin_root="$ROOT/plugins/aurelia.screenshot"
bar_root="$ROOT/plugins/aurelia.bar"
capture_bin="$ROOT/bin/aurelia-screenshot"

section "Screenshot Plugin Contract"

if [[ -f "$plugin_root/manifest.json" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.screenshot" and (.kinds == ["bar-widget"]) and .entryPoints["bar-widget"] == "ui/ScreenshotBarWidget.qml"' "$plugin_root/manifest.json" >/dev/null; then
    pass "Screenshot plugin declares a bar-only entry point"
else
    fail "Screenshot plugin manifest is missing or invalid"
fi

if [[ -x "$capture_bin" ]] &&
   "$capture_bin" --help >/dev/null 2>&1 &&
   grep -q 'grim' "$capture_bin" &&
   grep -q 'slurp' "$capture_bin" &&
   grep -q 'wl-copy' "$capture_bin" &&
   grep -q 'cursor:no_hardware_cursors' "$capture_bin" &&
   grep -q 'getoption cursor:no_hardware_cursors' "$capture_bin" &&
   grep -q 'cursor:inactive_timeout' "$capture_bin" &&
   grep -Fq '[[ "$original_inactive_timeout" =~ ^[0-9]+([.][0-9]+)?$ ]]' "$capture_bin" &&
   grep -Fq '[[ "$original_no_hw_cursors" =~ ^[0-9]+$ ]]' "$capture_bin" &&
   grep -q 'timeout' "$capture_bin" &&
   grep -q 'delay=3' "$capture_bin" &&
   grep -q 'show_pointer=0' "$capture_bin" &&
   grep -q -- '--show-pointer' "$capture_bin" &&
   grep -q 'command_name.*windows' "$capture_bin" &&
   grep -q -- '--geometry' "$capture_bin" &&
   grep -Fq 'if [[ -z "$geometry" &&' "$capture_bin" &&
   grep -q '.aurelia-screenshot-XXXXXX.png' "$capture_bin" &&
   grep -q 'mv -f -- "$capture_path" "$published_path"' "$capture_bin" &&
   grep -q '"$capture_mode" == "full"' "$capture_bin" &&
   ! grep -Eq '(^|[[:space:];])eval([[:space:];]|$)' "$capture_bin"; then
    pass "Screenshot backend has bounded grim/slurp/clipboard capture without eval"
else
    fail "Screenshot backend contract is incomplete"
fi

if grep -q 'function open(payloadJson)' "$plugin_root/ScreenshotPlugin.qml" &&
   grep -q 'function capture(payloadJson)' "$plugin_root/ScreenshotPlugin.qml" &&
   grep -q 'Selection (Region)' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'text: "Window"' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'Delay (seconds)' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'Show pointer' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'startRegionSelection' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'startWindowSelection' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'capturePendingRegion' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'Take Screenshot' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'Take Screenshot with Delay' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'native region geometry' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'selectionRect' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'selectionDragging' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'WAYLAND_DISPLAY' "$plugin_root/ScreenshotPlugin.qml" &&
   grep -q 'XDG_RUNTIME_DIR' "$plugin_root/ScreenshotPlugin.qml" &&
   grep -q 'captureProcess' "$plugin_root/ScreenshotPlugin.qml" &&
   grep -q 'duration_ms' "$plugin_root/ScreenshotPlugin.qml" &&
   grep -q 'captureRequested' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'captureCompleted' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'function quickRegion' "$plugin_root/ScreenshotPlugin.qml" &&
   grep -q 'quickCapture' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'anchorWindow' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'closeForPopoutSwitch' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'aurelia.screenshot.quick_region' "$plugin_root/keybindings.lua" &&
   grep -q 'ScreenshotPlugin.qml' "$plugin_root/ui/ScreenshotBarWidget.qml" &&
   grep -q 'function open(payloadJson)' "$plugin_root/ui/ScreenshotBarWidget.qml" &&
   grep -q 'root.open' "$plugin_root/ui/ScreenshotBarWidget.qml" &&
   grep -q '#33ffffff' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'captureStage === "region-selecting"' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'native region geometry' "$plugin_root/ui/ScreenshotPanel.qml" &&
   grep -q 'delaySeconds: 3' "$plugin_root/ui/ScreenshotPanel.qml"; then
    pass "Screenshot panel exposes full, region, window, and delayed capture flows"
else
    fail "Screenshot panel lifecycle or capture modes are incomplete"
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
   grep -q 'entryPointUrl(root.pluginId, "bar-widget")' "$bar_root/BarWidgetSlot.qml" &&
   grep -q 'camera-photo' "$plugin_root/ui/ScreenshotBarWidget.qml" &&
   grep -q 'aurelia.screenshot' "$plugin_root/ui/ScreenshotBarWidget.qml"; then
    pass "Bar exposes manifest-backed theme-aware widgets and mounts with the resident host"
else
    fail "Aurelia Bar screenshot action or opt-in lifecycle is incomplete"
fi
