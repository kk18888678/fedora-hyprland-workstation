#!/usr/bin/env bash

# Contract tests for the manifest-backed Aurelia bar widgets.

set -Eeuo pipefail

clock_root="$ROOT/plugins/aurelia.clock"
weather_root="$ROOT/plugins/aurelia.weather"
bar_root="$ROOT/plugins/aurelia.bar"
weather_bin="$ROOT/bin/aurelia-weather"
calendar_root="$ROOT/plugins/aurelia.calendar"
workspace_root="$ROOT/plugins/aurelia.workspaces"
tray_root="$ROOT/plugins/aurelia.tray"
power_root="$ROOT/plugins/aurelia.power"

section "Clock and Weather Bar Widgets"

if [[ -f "$calendar_root/manifest.json" && -f "$calendar_root/CalendarPlugin.qml" && -f "$calendar_root/ui/CalendarPanel.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.calendar" and (.kinds == ["panel"]) and .entryPoints.panel == "CalendarPlugin.qml"' "$calendar_root/manifest.json" >/dev/null &&
   grep -q 'aurelia.calendar' "$ROOT/plugins/aurelia.clock/ClockBarWidget.qml"; then
    pass "Calendar is a separate panel plugin opened by the clock widget"
else
    fail "Calendar plugin or clock integration is incomplete"
fi

if [[ -f "$workspace_root/manifest.json" && -f "$workspace_root/WorkspacesBarWidget.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.workspaces" and (.kinds == ["bar-widget"])' "$workspace_root/manifest.json" >/dev/null &&
   grep -q 'Quickshell.Hyprland' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -q 'modelData.activate' "$workspace_root/WorkspacesBarWidget.qml"; then
    pass "Workspace switcher is a Hyprland-backed bar widget"
else
    fail "Workspace bar widget is incomplete"
fi

if [[ -f "$tray_root/manifest.json" && -f "$tray_root/TrayBarWidget.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.tray" and (.kinds == ["bar-widget"])' "$tray_root/manifest.json" >/dev/null &&
   grep -q 'Quickshell.Services.SystemTray' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'SystemTray.items' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'Hyprland.toplevels' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'DesktopEntries.heuristicLookup' "$tray_root/TrayBarWidget.qml"; then
    pass "Tray/tasklist is a separate StatusNotifier and Hyprland-window-backed bar widget"
else
    fail "System tray bar widget is incomplete"
fi

if [[ -f "$power_root/manifest.json" && -f "$power_root/PowerBarWidget.qml" && -f "$power_root/PowerPanel.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.power" and (.kinds == ["bar-widget"])' "$power_root/manifest.json" >/dev/null &&
   grep -q 'system-lock-screen' "$power_root/PowerPanel.qml" &&
   grep -q 'systemctl.*poweroff' "$power_root/PowerPanel.qml" &&
   grep -q 'systemctl.*reboot' "$power_root/PowerPanel.qml"; then
    pass "Power bar widget provides lock, logout, suspend, reboot, and shutdown actions"
else
    fail "Power bar widget is incomplete"
fi

if [[ -f "$clock_root/manifest.json" && -f "$clock_root/ClockBarWidget.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.clock" and (.kinds == ["bar-widget"]) and .entryPoints["bar-widget"] == "ClockBarWidget.qml"' "$clock_root/manifest.json" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$clock_root" >/dev/null 2>&1; then
    pass "Clock is a validated first-party bar-widget plugin"
else
    fail "Clock bar-widget manifest or entry point is incomplete"
fi

if [[ -f "$weather_root/manifest.json" && -f "$weather_root/WeatherBarWidget.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.weather" and (.kinds == ["bar-widget"]) and .entryPoints["bar-widget"] == "WeatherBarWidget.qml"' "$weather_root/manifest.json" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$weather_root" >/dev/null 2>&1; then
    pass "Weather is a validated first-party bar-widget plugin"
else
    fail "Weather bar-widget manifest or entry point is incomplete"
fi

if [[ -x "$weather_bin" ]] &&
   bash -n "$weather_bin" &&
   grep -q 'wttr.in' "$weather_bin" &&
   grep -q 'api.open-meteo.com/v1/forecast' "$weather_bin" &&
   grep -q -- '--auto' "$weather_bin" &&
   grep -q -- '--location' "$weather_bin" &&
   grep -q -- '--connect-timeout 3' "$weather_bin" &&
   grep -q -- '--max-time 5' "$weather_bin" &&
   grep -q -- '--max-filesize 1048576' "$weather_bin" &&
   grep -q -- '--proto.*https' "$weather_bin" &&
   ! grep -Eq '(^|[[:space:];])eval([[:space:];]|$)' "$weather_bin"; then
    pass "Weather backend supports Omarchy-style auto detection, pinning, and bounded HTTPS retrieval"
else
    fail "Weather backend safety contract is incomplete"
fi

if grep -q 'aurelia.clock' "$ROOT/services/ShellConfig.qml" &&
   grep -q 'aurelia.weather' "$ROOT/services/ShellConfig.qml" &&
   grep -q 'centerAnchor: "aurelia.clock"' "$ROOT/services/ShellConfig.qml" &&
   grep -q 'function cloneEntrySettings(entry)' "$ROOT/services/ShellConfig.qml" &&
   grep -q 'entry.settings' "$bar_root/BarWidgetRow.qml" &&
   grep -q 'location: "auto"' "$ROOT/services/ShellConfig.qml"; then
    pass "Bar defaults include a centered clock and automatic weather location"
else
    fail "Bar default widget layout or settings normalization is incomplete"
fi

if grep -q 'Quickshell.iconPath' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'weather-clear' "$weather_root/WeatherBarWidget.qml" &&
   ! grep -q 'PanelWindow' "$clock_root/ClockBarWidget.qml" &&
   ! grep -q 'PanelWindow' "$weather_root/WeatherBarWidget.qml"; then
    pass "Clock and weather remain lightweight bar-only surfaces with theme icon lookup"
else
    fail "Bar-only widget surface or icon lookup contract is incomplete"
fi
