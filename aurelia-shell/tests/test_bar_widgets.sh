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
   grep -Fq 'var ids = [1, 2, 3, 4, 5]' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'id > 0 && id <= 10' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'ids.sort(function(left, right) { return left - right })' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'model: root.workspaceIds()' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'workspace.toplevels.values.length' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'Hyprland.focusedWorkspace' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'modelData === 10 ? "0"' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'text: focused ? "\uDB85\uDCFB" : (occupied ? (modelData === 10 ? "0" : String(modelData)) : "•")' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'occupied ? (modelData === 10' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq ': "•")' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'font.pixelSize: !focused && !occupied' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'root.bar && root.bar.barTextSize ? root.bar.barTextSize + 5' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'root.bar && root.bar.barTextSize ? root.bar.barTextSize : Theme.fontSizeSm' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'delegate: Item {' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'clip: true' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'anchors.margins: 1' "$workspace_root/WorkspacesBarWidget.qml" &&
   ! grep -Fq 'color: workspaceHover.hovered ? Theme.selection : Theme.surface' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'opacity: occupied || focused ? 1 : 0.5' "$workspace_root/WorkspacesBarWidget.qml" &&
   ! grep -Fq 'focused ? Theme.accent' "$workspace_root/WorkspacesBarWidget.qml" &&
   ! grep -Fq 'focused ? Theme.bgBase' "$workspace_root/WorkspacesBarWidget.qml" &&
   ! grep -Fq 'focused ? Theme.fontWeightBold' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'columns: root.vertical ? 1' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'rowSpacing: root.vertical ? 2 : 0' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'implicitHeight: root.barSize' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'Layout.preferredHeight: root.barSize' "$workspace_root/WorkspacesBarWidget.qml" &&
   ! grep -Fq 'cellInset' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'if (Hyprland.usingLua)' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'Hyprland.dispatch("hl.dsp.focus' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'Hyprland.dispatch("workspace " + workspaceId)' "$workspace_root/WorkspacesBarWidget.qml" &&
   ! grep -q 'focusProcess' "$workspace_root/WorkspacesBarWidget.qml" &&
   ! grep -q 'modelData.activate' "$workspace_root/WorkspacesBarWidget.qml"; then
    pass "Workspace switcher mirrors the reference model/state/layout, renders dots for empty workspaces and a theme-aware active glyph without cell highlighting, stays inside the bar, and focuses through native Hyprland IPC"
else
    fail "Workspace bar widget reference behavior, bar bounds, or native focus dispatch is incomplete"
fi

if [[ -f "$bar_root/AureliaLogo.qml" ]] &&
   grep -q 'property var bar: null' "$bar_root/AureliaLogo.qml" &&
   grep -q 'implicitWidth: bar && bar.barIconSlot ? bar.barIconSlot : 27' "$bar_root/AureliaLogo.qml" &&
   grep -q 'implicitHeight: bar && bar.barSize ? bar.barSize : 26' "$bar_root/AureliaLogo.qml" &&
   grep -q 'AureliaMark {' "$bar_root/AureliaLogo.qml" &&
   grep -q 'color: root.hovered ? Theme.text : Theme.accent' "$bar_root/AureliaLogo.qml" &&
   grep -q 'coreColor: root.hovered ? Theme.text : Theme.gold' "$bar_root/AureliaLogo.qml" &&
   grep -q 'AureliaMark 1.0 AureliaMark.qml' "$ROOT/ui/qmldir" &&
   [[ -f "$ROOT/config/branding/aurelia-mark.svg" ]] &&
   grep -q 'viewBox="0 0 256 256"' "$ROOT/config/branding/aurelia-mark.svg" &&
   grep -q 'aria-label="Aurelia"' "$ROOT/config/branding/aurelia-mark.svg" &&
   grep -q 'shell.summon("aurelia.launcher"' "$bar_root/AureliaLogo.qml"; then
    pass "Aurelia logo uses one vector brand mark with a theme-aware hover state"
else
    fail "Aurelia logo sizing, monogram rendering, or launcher action is incomplete"
fi

if grep -q 'property string sourcePath: ""' "$ROOT/ui/AureliaIcon.qml" &&
   grep -q 'property string fallbackName: "application-x-executable"' "$ROOT/ui/AureliaIcon.qml" &&
   grep -q 'root.sourcePath' "$ROOT/ui/AureliaIcon.qml" &&
   grep -q 'root.fallbackName' "$ROOT/ui/AureliaIcon.qml" &&
   grep -q 'colorizationColor: root.tint' "$ROOT/ui/AureliaIcon.qml" &&
   grep -q 'sourcePixelRatio: Math.max(1, Screen.devicePixelRatio)' "$ROOT/ui/AureliaIcon.qml" &&
   grep -q 'TextMetrics' "$ROOT/ui/AureliaIcon.qml" &&
   grep -q 'renderType: Text.NativeRendering' "$ROOT/ui/AureliaIcon.qml" &&
   grep -q 'function glyphForName(value)' "$ROOT/ui/AureliaIcon.qml"; then
    pass "Shared icon primitive preserves artwork, decodes at physical pixels, and renders semantic glyphs natively"
else
    fail "Shared icon primitive does not expose the crisp physical-pixel and native-glyph contract"
fi

if grep -Fq 'glyph: root.networkPanel && root.networkPanel.icon' "$ROOT/plugins/aurelia.network/NetworkBarWidget.qml" &&
   grep -Fq 'glyph: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"' "$ROOT/plugins/aurelia.monitor/DisplayBarWidget.qml" &&
   grep -Fq 'glyph: "󰄀"' "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotBarWidget.qml" &&
   grep -Fq 'if (n === "notifications") return "󰂚"' "$ROOT/ui/AureliaIcon.qml" &&
   grep -Fq 'if (n === "system-shutdown"' "$ROOT/ui/AureliaIcon.qml"; then
    pass "Reference network, display, screenshot, notification, and power glyphs are used for crisp bar affordances"
else
    fail "Semantic bar icons still depend on weak theme-name image lookups"
fi

if grep -Fq 'barOuterMargin: Theme.bar.outerMargin' "$bar_root/Bar.qml" &&
   grep -Fq 'barIconSlot: Theme.bar.iconSlot' "$bar_root/Bar.qml" &&
   grep -Fq 'barTextSize: Theme.bar.text' "$bar_root/Bar.qml" &&
   grep -Fq 'barCaptionSize: Theme.bar.caption' "$bar_root/Bar.qml" &&
   grep -Fq 'barSize: vertical ? Theme.bar.sizeVertical : Theme.bar.sizeHorizontal' "$bar_root/Bar.qml" &&
   grep -Fq 'anchors.leftMargin: barRoot.vertical ? 0 : barRoot.barOuterMargin' "$bar_root/Bar.qml" &&
   grep -Fq 'anchors.rightMargin: barRoot.vertical ? 0 : barRoot.barOuterMargin' "$bar_root/Bar.qml" &&
   grep -Fq 'bar: barRoot' "$bar_root/Bar.qml"; then
    pass "Bar geometry keeps the reference edge margin, shared icon slot, and minimum readable text metrics without changing palette tokens"
else
    fail "Reference bar geometry metrics or shared widget injection is incomplete"
fi

if grep -Fq 'barScaleWithFont' "$ROOT/theme/Theme.qml" &&
   grep -Fq 'sizeHorizontal: themeRoot._getScaledInt("barSizeHorizontal", 26)' "$ROOT/theme/Theme.qml" &&
   grep -Fq 'iconSlot: themeRoot._getScaledInt("barIconSlot", 27)' "$ROOT/theme/Theme.qml" &&
   grep -Fq 'statusSlot: themeRoot._getScaledInt("barStatusSlot", 21)' "$ROOT/theme/Theme.qml" &&
   grep -Fq 'barSizeHorizontal = 26' "$ROOT/theme.conf" &&
   grep -Fq 'barScaleWithFont = true' "$ROOT/theme.conf"; then
    pass "Bar metrics scale together from one structural contract"
else
    fail "Scaled structural bar metric contract is incomplete"
fi

if grep -q 'id: "aurelia.bar"' "$ROOT/services/ShellConfig.qml" &&
   grep -q 'var barId = isValidPluginId(source.id)' "$ROOT/services/ShellConfig.qml" &&
   grep -q 'readonly property string selectedBarId' "$ROOT/services/PluginHost.qml" &&
   grep -q 'readonly property string activeBarId' "$ROOT/services/PluginHost.qml" &&
   grep -q 'id !== host.activeBarId' "$ROOT/services/PluginHost.qml" &&
   grep -q 'function activeBar()' "$ROOT/services/PluginHost.qml" &&
   grep -q 'pluginHost.activeBar()' "$ROOT/shell.qml"; then
    pass "bar implementation ownership is selected from shell.json with a validated Aurelia fallback"
else
    fail "dynamic bar implementation selection or fallback boundary is incomplete"
fi

if grep -q 'readonly property bool customQml' "$bar_root/BarWidgetSlot.qml" &&
   grep -q 'readonly property bool customCommand' "$bar_root/BarWidgetSlot.qml" &&
   grep -q 'function safeCustomSource()' "$bar_root/BarWidgetSlot.qml" &&
   grep -q 'function safeArgv(value)' "$bar_root/BarWidgetSlot.qml" &&
   grep -q 'CustomCommandBarWidget.qml' "$bar_root/BarWidgetSlot.qml" &&
   [[ -f "$bar_root/CustomCommandBarWidget.qml" ]] &&
   grep -q '/usr/bin/timeout' "$bar_root/CustomCommandBarWidget.qml" &&
   grep -q 'function commandArgv()' "$bar_root/CustomCommandBarWidget.qml"; then
    pass "bar slots support validated user QML and bounded argv command modules"
else
    fail "generic custom bar module loading or command bounds are incomplete"
fi

if grep -Fq 'fitHeightToContent: false' "$ROOT/ui/AureliaKeyboardPanel.qml" &&
   grep -Fq 'contentSizingItem' "$ROOT/ui/AureliaKeyboardPanel.qml" &&
   grep -Fq 'resolvedPopupHeight' "$ROOT/ui/AureliaKeyboardPanel.qml" &&
   grep -Fq 'Theme.scaleGeometry(root.popupWidth)' "$ROOT/ui/AureliaKeyboardPanel.qml" &&
   ! grep -Fq '"/usr/bin/hyprctl", "layers", "-j"' "$ROOT/ui/AureliaKeyboardPanel.qml" &&
   grep -Fq 'Theme.scaleGeometry(popupWidth)' "$ROOT/ui/AureliaPopupCard.qml"; then
    pass "Popup primitives use direct bar anchors, shared scaling, and content-fitted heights"
else
    fail "Popup geometry contract still depends on fixed or compositor-query timing"
fi

chakravyuha_mark="$ROOT/config/branding/aurelia-mark-chakravyuha.svg"
if [[ -f "$chakravyuha_mark" ]] &&
   grep -q 'aria-label="Aurelia Chakravyuha concept mark"' "$chakravyuha_mark" &&
   grep -q 'id="aureliaChakravyuha"' "$chakravyuha_mark" &&
   grep -q 'A110 110' "$chakravyuha_mark" &&
   grep -q 'stroke-linejoin="round"' "$chakravyuha_mark" &&
   grep -q 'single luminous path' "$chakravyuha_mark" &&
   ! grep -qi 'omarchy' "$chakravyuha_mark"; then
    pass "Aurelia keeps the first mark and ships a separate original inward-labyrinth concept"
else
    fail "Aurelia's second Chakravyuha-inspired brand concept is missing or coupled to the reference asset"
fi

if [[ -f "$tray_root/manifest.json" && -f "$tray_root/TrayBarWidget.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.tray" and (.kinds == ["bar-widget"])' "$tray_root/manifest.json" >/dev/null &&
   grep -q 'Quickshell.Services.SystemTray' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'SystemTray.items' "$tray_root/TrayBarWidget.qml" &&
   [[ -f "$tray_root/TrayMenuPanel.qml" ]] &&
   grep -q 'QsMenuOpener' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'QsMenuOpener' "$tray_root/TrayMenuPanel.qml" &&
   grep -q 'Repeater' "$tray_root/TrayMenuPanel.qml" &&
   grep -q 'currentValues' "$tray_root/TrayMenuPanel.qml" &&
   grep -q 'model: panelRoot.currentChildren' "$tray_root/TrayMenuPanel.qml" &&
   grep -q 'openApplicationContextMenu' "$tray_root/TrayBarWidget.qml" &&
   ! grep -q 'QsMenuAnchor' "$tray_root/TrayBarWidget.qml"; then
    pass "Tray/tasklist uses an in-shell D-Bus menu and Hyprland-window-backed bar widget"
else
    fail "System tray bar widget is incomplete"
fi

if grep -Fq 'spacing: 0' "$tray_root/TrayBarWidget.qml" &&
   grep -Fq 'root.bar && root.bar.barIconSlot ? root.bar.barIconSlot : 27' "$tray_root/TrayBarWidget.qml" &&
   grep -Fq 'root.bar && root.bar.barIconSlot ? root.bar.barIconSlot : Theme.bar.iconSlot' "$tray_root/TrayBarWidget.qml" &&
   grep -Fq 'root.bar && root.bar.barTrayIcon ? root.bar.barTrayIcon : Theme.bar.trayIcon' "$tray_root/TrayBarWidget.qml"; then
    pass "Tray items use the reference slot width, 27px item extent, 12px icon, and zero inter-item gap"
else
    fail "Tray bar geometry does not match the reference slot contract"
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
   grep -q 'systemctl.*poweroff' "$power_root/PowerPanel.qml" &&
   grep -q 'systemctl.*reboot' "$power_root/PowerPanel.qml" &&
   grep -q 'AureliaIcon {' "$power_root/PowerBarWidget.qml" &&
   grep -q 'name: "system-shutdown"' "$power_root/PowerBarWidget.qml" &&
   grep -q 'fallbackName: "system-power-off"' "$power_root/PowerBarWidget.qml" &&
   grep -q 'tint: powerHover.hovered ? Theme.text : Theme.textSecondary' "$power_root/PowerBarWidget.qml" &&
   grep -q 'function iconGlyph(name)' "$power_root/PowerPanel.qml" &&
   grep -q 'font.family: Theme.fontFamily' "$power_root/PowerBarWidget.qml" "$power_root/PowerPanel.qml" &&
   ! grep -q 'AureliaGlyph' "$power_root/PowerBarWidget.qml" "$power_root/PowerPanel.qml" &&
   ! grep -q 'text: "󰐥"' "$power_root/PowerBarWidget.qml" &&
   grep -q '"suspend"' "$power_root/PowerPanel.qml" &&
   grep -q '"reboot"' "$power_root/PowerPanel.qml" &&
   grep -q '"power"' "$power_root/PowerPanel.qml"; then
    pass "Power bar widget uses one coherent theme-aware system icon without custom QML type loading"
else
    fail "Power bar widget actions or theme-aware icon contract is incomplete"
fi

if grep -q 'AureliaIcon {' "$ROOT/plugins/aurelia.monitor/DisplayBarWidget.qml" &&
   grep -Fq 'glyph: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"' "$ROOT/plugins/aurelia.monitor/DisplayBarWidget.qml" &&
   ! grep -q 'name: Quickshell.screens.length > 1' "$ROOT/plugins/aurelia.monitor/DisplayBarWidget.qml" &&
   ! grep -q 'fallbackName: "computer"' "$ROOT/plugins/aurelia.monitor/DisplayBarWidget.qml" &&
   grep -q 'AureliaIcon {' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'name: root.iconName' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'fallbackName: "weather-clear"' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'tint: Theme.accent' "$weather_root/WeatherBarWidget.qml"; then
    pass "Display and weather bar icons resolve through the theme-aware icon primitive"
else
    fail "Display or weather bar icon theme integration is incomplete"
fi

if grep -q 'AureliaIcon {' "$tasklist_root/TasklistBarWidget.qml" &&
   grep -q 'sourcePath: root.iconSourceFor(modelData, appEntry)' "$tasklist_root/TasklistBarWidget.qml" &&
   grep -q 'tint: modelData.activated ? Theme.text : Theme.textMuted' "$tasklist_root/TasklistBarWidget.qml" &&
   ! grep -q '^                Image {' "$tasklist_root/TasklistBarWidget.qml" &&
   grep -q 'AureliaIcon {' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'function isSymbolicIcon' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'function isChatGptItem' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'function trayIconSize' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'root.bar && root.bar.barTrayIcon ? root.bar.barTrayIcon : Theme.bar.trayIcon' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'sourcePixelRatio: Screen.devicePixelRatio' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'smooth: false' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'preserveColors: !root.isSymbolicIcon' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'modelData && modelData.icon ? String(modelData.icon) : ""' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'tint: Theme.textSecondary' "$tray_root/TrayBarWidget.qml" &&
   ! grep -q '^                Image {' "$tray_root/TrayBarWidget.qml"; then
    pass "Tasklist and tray icons inherit semantic foreground colors while retaining their resolved sources"
else
    fail "Tasklist or tray bar icons bypass the theme-aware icon primitive"
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

if [[ -f "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotMenuPopup.qml" &&
      -f "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotSelectionOverlay.qml" ]] &&
   grep -q 'AureliaKeyboardPanel' "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotMenuPopup.qml" &&
   grep -q 'PanelWindow' "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotSelectionOverlay.qml" &&
   ! grep -q 'PanelWindow' "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotPanel.qml" &&
   grep -q 'function quickRegion' "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotPanel.qml"; then
    pass "Screenshot controls are bar-owned while region selection remains a dedicated overlay"
else
    fail "Screenshot bar-owned popup and selection overlay contract is incomplete"
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
   grep -q 'format=%l' "$weather_bin" &&
   grep -q 'automatic weather location response was invalid' "$weather_bin" &&
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

if grep -q 'visible: !root.hasAnchor' "$bar_root/BarCenter.qml" &&
   grep -Fq 'entries: root.hasAnchor ? [] : root.entries' "$bar_root/BarCenter.qml"; then
    pass "Anchored center rows do not instantiate duplicate hidden widget delegates"
else
    fail "Anchored center row can still instantiate duplicate hidden widget delegates"
fi

if ! grep -q 'aurelia.tasklist' "$ROOT/services/ShellConfig.qml" &&
   ! grep -q 'aurelia.tasklist' "$ROOT/plugins/aurelia.bar/Bar.qml"; then
    pass "Tasklist remains opt-in and is not part of the Omarchy-aligned default bar"
else
    fail "Tasklist unexpectedly appears in the default Aurelia bar layout"
fi

if grep -q 'AureliaIcon' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'fallbackName: "weather-clear"' "$weather_root/WeatherBarWidget.qml" &&
   ! grep -q 'PanelWindow' "$clock_root/ClockBarWidget.qml" &&
   [[ -f "$weather_root/WeatherPanel.qml" ]] &&
   grep -q 'Next 3 days' "$weather_root/WeatherPanel.qml" &&
   ! grep -q 'PanelWindow' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'function scheduleRefresh' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'onSettingsChanged:' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'function onVisibleChanged' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'property bool weatherReady: false' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'visible: root.weatherReady' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'forecastData.length < 3' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'weather-clear-wind' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'function dayLabel' "$weather_root/WeatherPanel.qml" &&
   grep -q 'FORECAST' "$weather_root/WeatherPanel.qml" &&
   grep -q 'find-location' "$weather_root/WeatherPanel.qml"; then
    pass "Clock and weather remain lightweight bar surfaces with automatic detailed weather data"
else
    fail "Bar-only widget surface or icon lookup contract is incomplete"
fi

if grep -q 'function requestPopout(owner, ownerId)' "$bar_root/Bar.qml" &&
   grep -q 'function releasePopout(owner)' "$bar_root/Bar.qml" &&
   grep -q 'activePopoutId' "$bar_root/Bar.qml" &&
   grep -q 'popoutActive' "$bar_root/BarWidgetSlot.qml" &&
   grep -q 'function callBarWidget(id, method, argument)' "$ROOT/services/PluginHost.qml" &&
   grep -q 'function hasWidget(pluginId)' "$bar_root/Bar.qml" &&
   grep -q 'function open(payloadJson)' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'function isVisible()' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'PopupWindow' "$ROOT/ui/AureliaPopupCard.qml" &&
   grep -q 'anchorItem.QsWindow.window' "$ROOT/ui/AureliaPopupCard.qml" &&
   grep -q 'Theme.popupMargin' "$ROOT/ui/AureliaPopupCard.qml" &&
   grep -q 'anchor_unavailable' "$ROOT/ui/AureliaPopupCard.qml"; then
    pass "Bar widgets share one Omarchy-style popout owner and complete shell lifecycle routing"
else
    fail "Bar widget lifecycle routing or popout ownership is incomplete"
fi

if grep -q 'FocusScope' "$ROOT/ui/AureliaPopupCard.qml" &&
   grep -q 'Qt.Key_Escape' "$ROOT/ui/AureliaPopupCard.qml" &&
   ! grep -R -q 'text: "ESC"' "$calendar_root" "$power_root" "$tasklist_root" "$tray_root" "$ROOT/plugins/aurelia.weather" "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotMenuPopup.qml"; then
    pass "Bar-owned popup cards share keyboard dismissal without rendering shortcut labels"
else
    fail "Bar-owned popup keyboard dismissal or visual contract is incomplete"
fi

if grep -q 'Theme.selectionHover' "$tray_root/TrayMenuPanel.qml" &&
   grep -q 'menuColumn.implicitHeight' "$tray_root/TrayMenuPanel.qml" &&
   grep -q 'width: 2' "$tray_root/TrayMenuPanel.qml" &&
   grep -q 'Theme.trayMenuPadding \* 2' "$tray_root/TrayMenuPanel.qml" &&
   grep -q 'Theme.trayMenuRowHeight' "$tray_root/TrayMenuPanel.qml" &&
   grep -q 'sectionLabel' "$tray_root/TrayMenuPanel.qml" &&
   ! grep -q 'Number(currentValues.length) \* 38' "$tray_root/TrayMenuPanel.qml"; then
    pass "Tray menus use semantic hover highlights and compact content-driven sizing"
else
    fail "Tray menu hover or compact sizing contract is incomplete"
fi

if grep -q 'AureliaKeyboardPanel' "$calendar_root/ui/CalendarPanel.qml" &&
   grep -q 'AureliaKeyboardPanel' "$power_root/PowerPanel.qml" &&
   grep -q 'AureliaKeyboardPanel' "$ROOT/plugins/aurelia.weather/WeatherPanel.qml" &&
   grep -q 'AureliaKeyboardPanel' "$ROOT/plugins/aurelia.tray/TrayMenuPanel.qml" &&
   grep -q 'AureliaKeyboardPanel' "$ROOT/plugins/aurelia.tasklist/TasklistMenuPanel.qml" &&
   [[ -f "$ROOT/ui/AureliaKeyboardPanel.qml" ]] &&
   grep -q 'closeForPopoutSwitch' "$calendar_root/ui/CalendarPanel.qml" &&
   grep -q 'closeForPopoutSwitch' "$power_root/PowerPanel.qml" &&
   grep -q 'closeForPopoutSwitch' "$ROOT/plugins/aurelia.weather/WeatherPanel.qml" &&
   grep -q 'closeForPopoutSwitch' "$ROOT/plugins/aurelia.tray/TrayMenuPanel.qml" &&
   grep -q 'closeForPopoutSwitch' "$ROOT/plugins/aurelia.tasklist/TasklistMenuPanel.qml"; then
    pass "Bar-owned widget surfaces use anchored popup cards and single-popout ownership"
else
    fail "Anchored bar-owned popup surface contract is incomplete"
fi
