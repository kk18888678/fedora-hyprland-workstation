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
tasklist_root="$ROOT/plugins/aurelia.tasklist"
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
   [[ -f "$tray_root/TrayMenuPanel.qml" ]] &&
   grep -q 'QsMenuOpener' "$tray_root/TrayMenuPanel.qml" &&
   grep -q 'Repeater' "$tray_root/TrayMenuPanel.qml" &&
   grep -q 'openApplicationContextMenu' "$tray_root/TrayBarWidget.qml" &&
   ! grep -q 'QsMenuAnchor' "$tray_root/TrayBarWidget.qml"; then
    pass "Tray/tasklist uses an in-shell D-Bus menu and Hyprland-window-backed bar widget"
else
    fail "System tray bar widget is incomplete"
fi

if [[ -f "$tasklist_root/manifest.json" && -f "$tasklist_root/TasklistBarWidget.qml" && -f "$tasklist_root/TasklistMenuPanel.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.tasklist" and (.kinds == ["bar-widget"])' "$tasklist_root/manifest.json" >/dev/null &&
   grep -q 'Quickshell.Hyprland' "$tasklist_root/TasklistBarWidget.qml" &&
   grep -q 'Qt.RightButton' "$tasklist_root/TasklistBarWidget.qml" &&
   grep -q 'function closeWindow' "$tasklist_root/TasklistMenuPanel.qml" &&
   grep -q 'function openMatchingWindowMenu' "$tasklist_root/TasklistBarWidget.qml" &&
   grep -q 'function iconSourceFor' "$tasklist_root/TasklistBarWidget.qml" &&
   grep -q 'window-new' "$tasklist_root/TasklistBarWidget.qml"; then
    pass "Tasklist is a separate Hyprland bar widget with an in-shell window context menu"
else
    fail "Tasklist plugin or window context menu is incomplete"
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
   grep -q 'apparent_temperature' "$weather_bin" &&
   grep -q 'relative_humidity_2m' "$weather_bin" &&
   grep -q 'forecast_days=3' "$weather_bin" &&
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

if ! grep -q 'aurelia.tasklist' "$ROOT/services/ShellConfig.qml" &&
   ! grep -q 'aurelia.tasklist' "$ROOT/plugins/aurelia.bar/Bar.qml"; then
    pass "Tasklist remains opt-in and is not part of the Omarchy-aligned default bar"
else
    fail "Tasklist unexpectedly appears in the default Aurelia bar layout"
fi

if grep -q 'Quickshell.iconPath' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'weather-clear' "$weather_root/WeatherBarWidget.qml" &&
   ! grep -q 'PanelWindow' "$clock_root/ClockBarWidget.qml" &&
   [[ -f "$weather_root/WeatherPanel.qml" ]] &&
   grep -q 'Next 3 days' "$weather_root/WeatherPanel.qml" &&
   ! grep -q 'PanelWindow' "$weather_root/WeatherBarWidget.qml"; then
    pass "Clock and weather remain lightweight bar surfaces with automatic detailed weather data"
else
    fail "Bar-only widget surface or icon lookup contract is incomplete"
fi

if grep -q 'function requestPopout(owner)' "$bar_root/Bar.qml" &&
   grep -q 'function releasePopout(owner)' "$bar_root/Bar.qml" &&
   grep -q 'function callBarWidget(id, method, argument)' "$ROOT/services/PluginHost.qml" &&
   grep -q 'function hasWidget(pluginId)' "$bar_root/Bar.qml" &&
   grep -q 'function open(payloadJson)' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'function isVisible()' "$weather_root/WeatherBarWidget.qml"; then
    pass "Bar widgets share one Omarchy-style popout owner and complete shell lifecycle routing"
else
    fail "Bar widget lifecycle routing or popout ownership is incomplete"
fi

if grep -q 'anchors.bottom: true' "$calendar_root/ui/CalendarPanel.qml" &&
   grep -q 'anchors.right: true' "$calendar_root/ui/CalendarPanel.qml" &&
   grep -q 'closeForPopoutSwitch' "$calendar_root/ui/CalendarPanel.qml" &&
   grep -q 'closeForPopoutSwitch' "$power_root/PowerPanel.qml" &&
   grep -q 'closeForPopoutSwitch' "$ROOT/plugins/aurelia.weather/WeatherPanel.qml" &&
   grep -q 'closeForPopoutSwitch' "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotPanel.qml"; then
    pass "Floating widget surfaces use full-screen dismissal ownership with cards below the bar"
else
    fail "Floating widget dismissal or below-bar surface contract is incomplete"
fi
