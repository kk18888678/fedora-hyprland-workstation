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
session_actions_root="$ROOT/plugins/aurelia.session-actions"

section "Clock and Weather Bar Widgets"

if [[ -f "$calendar_root/manifest.json" && -f "$calendar_root/CalendarPlugin.qml" && -f "$calendar_root/ui/CalendarPanel.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.calendar" and (.kinds == ["panel"]) and .entryPoints.panel == "CalendarPlugin.qml"' "$calendar_root/manifest.json" >/dev/null &&
   grep -q 'aurelia.calendar' "$ROOT/plugins/aurelia.clock/ClockBarWidget.qml"; then
    pass "Calendar is a separate panel plugin opened by the clock widget"
else
    fail "Calendar plugin or clock integration is incomplete"
fi

if [[ -f "$workspace_root/manifest.json" && -f "$workspace_root/WorkspacesBarWidget.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.workspaces" and (.kinds == ["bar-widget"]) and
          (.barWidget.defaultSection == null)' "$workspace_root/manifest.json" >/dev/null &&
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
   grep -Fq 'implicitHeight: workspaceGrid.implicitHeight' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'Layout.preferredHeight: root.barSize' "$workspace_root/WorkspacesBarWidget.qml" &&
   ! grep -Fq 'cellInset' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'WorkspaceActionModel.actionFor' "$workspace_root/WorkspacesBarWidget.qml" &&
   grep -Fq 'Hyprland.dispatch(action.command)' "$workspace_root/WorkspacesBarWidget.qml" &&
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
   grep -q 'width: root.iconCanvas' "$bar_root/AureliaLogo.qml" &&
   grep -q 'height: root.iconCanvas' "$bar_root/AureliaLogo.qml" &&
   grep -q 'color: root.barForeground' "$bar_root/AureliaLogo.qml" &&
   grep -q 'coreColor: root.barForeground' "$bar_root/AureliaLogo.qml" &&
   ! grep -q 'Theme.accent' "$bar_root/AureliaLogo.qml" &&
   ! grep -q 'Theme.gold' "$bar_root/AureliaLogo.qml" &&
   ! grep -q '0.92' "$bar_root/AureliaLogo.qml" &&
   grep -q 'AureliaMark 1.0 AureliaMark.qml' "$ROOT/ui/qmldir" &&
   [[ -f "$ROOT/config/branding/aurelia-mark.svg" ]] &&
   grep -q 'viewBox="0 0 256 256"' "$ROOT/config/branding/aurelia-mark.svg" &&
   grep -q 'aria-label="Aurelia"' "$ROOT/config/branding/aurelia-mark.svg" &&
   grep -q 'controller.summon("aurelia.launcher"' "$bar_root/AureliaLogo.qml"; then
    pass "Aurelia logo uses the shared ink canvas, bar-foreground brand colour, and full opacity"
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

# Regression: glyph rendering must hand Qt one real font family. Qt's
# font.family takes a single family, so the theme exposes one resolved family
# and both the icon primitive and every text consumer use it. The raw
# comma-separated Theme.fontFamily list must never reach Qt's font.family.
glyph_family_line="$(grep -F 'property string glyphFontFamily:' "$ROOT/ui/AureliaIcon.qml" || true)"
configured_family="$(sed -n 's/^[[:space:]]*fontFamily[[:space:]]*=[[:space:]]*//p' "$ROOT/theme.conf" | head -n1)"
first_family="${configured_family%%,*}"
first_family="$(printf '%s' "$first_family" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
if grep -q 'readonly property string fontFamilyResolved:' "$ROOT/theme/Theme.qml" &&
   grep -q 'Qt.fontFamilies()' "$ROOT/theme/Theme.qml" &&
   [[ "$glyph_family_line" == *'Theme.fontFamilyResolved'* ]] &&
   [[ -n "$first_family" ]] &&
   ! grep -rqE 'font\.family: *Theme\.fontFamily([^A-Za-z]|$)' "$ROOT/plugins" "$ROOT/ui" "$ROOT/services" "$ROOT/components"; then
    pass "AureliaIcon and every text consumer resolve the declared font list through the theme's one family-resolution point"
else
    fail "Font resolution is not shared: the icon or a text consumer does not use Theme.fontFamilyResolved"
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
   grep -Fq 'anchors.leftMargin: contentRoot.orientationVertical ? 0' "$bar_root/BarPanel.qml" &&
   grep -Fq 'anchors.rightMargin: contentRoot.orientationVertical ? 0' "$bar_root/BarPanel.qml" &&
   grep -Fq 'bar: panelRoot.bar' "$bar_root/BarPanel.qml" &&
   grep -Fq 'model: Quickshell.screens' "$bar_root/Bar.qml" &&
   grep -Fq 'BarPanel' "$bar_root/Bar.qml"; then
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

if grep -q '"id": "aurelia.bar"' "$ROOT/config/bar-default.json" &&
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

if grep -Fq 'columnSpacing: 0' "$tray_root/TrayBarWidget.qml" &&
   grep -Fq 'rowSpacing: 0' "$tray_root/TrayBarWidget.qml" &&
   grep -Fq 'root.bar && root.bar.barIconSlot ? root.bar.barIconSlot : 27' "$tray_root/TrayBarWidget.qml" &&
   grep -Fq 'root.bar && root.bar.barIconSlot ? root.bar.barIconSlot : Theme.bar.iconSlot' "$tray_root/TrayBarWidget.qml" &&
   grep -Fq 'width: root.iconCanvas' "$tray_root/TrayBarWidget.qml" &&
   grep -Fq 'height: root.iconCanvas' "$tray_root/TrayBarWidget.qml" &&
   ! grep -Fq 'barTrayIcon' "$tray_root/TrayBarWidget.qml"; then
    pass "Tray items use the reference slot width, 27px item extent, canvas-sized icon, and zero inter-item gap"
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

window_routing="$ROOT/services/WindowRouting.js"
window_activation="$ROOT/services/WindowActivation.qml"
if [[ -f "$window_routing" && -f "$window_activation" ]] &&
   grep -Fq 'import "../../services/WindowRouting.js" as WindowRouting' "$tray_root/TrayBarWidget.qml" &&
   grep -Fq 'workspaceRouteDataForTrayItem' "$tray_root/TrayBarWidget.qml" &&
   grep -Fq 'windowActivationLoader.item.start(route)' "$tray_root/TrayBarWidget.qml" &&
   grep -Fq 'source: Qt.resolvedUrl("../../services/WindowActivation.qml")' "$tray_root/TrayBarWidget.qml" &&
   grep -Fq 'windowActivationLoader.item' "$tray_root/TrayBarWidget.qml" &&
   grep -Fq 'applicationRouteStarter' "$tray_root/TrayMenuPanel.qml" &&
   grep -Fq 'entry.triggered()' "$tray_root/TrayMenuPanel.qml" &&
   grep -Fq 'import "../../services/WindowRouting.js" as WindowRouting' "$tasklist_root/TasklistBarWidget.qml" &&
   grep -Fq 'workspaceRouteDataForTrayIdentity' "$tasklist_root/TasklistBarWidget.qml" &&
   grep -Fq 'activationController' "$tasklist_root/TasklistMenuPanel.qml" &&
   grep -Fq 'workspace.activate' "$tasklist_root/TasklistMenuPanel.qml" &&
   grep -Fq 'workspaceRouteMaxAttempts: 30' "$window_activation" &&
   grep -Fq 'Hyprland.refreshToplevels' "$window_activation" &&
   grep -Fq 'Hyprland.refreshWorkspaces' "$window_activation" &&
   grep -Fq 'workspaceRouteTimer.restart' "$window_activation" &&
   grep -Fq 'handle.activate' "$window_activation"; then
    pass "Tray and tasklist window actions use the notification-style workspace-first activation controller"
else
    fail "Tray/tasklist workspace routing does not share the bounded notification-style activation contract"
fi

if command -v node >/dev/null; then
    window_routing_status=0
    node - "$window_routing" <<'NODE_WINDOW_ROUTING' || window_routing_status=$?
const routing = require(process.argv[2])
const assert = (value, message) => { if (!value) throw new Error(message) }

const chatItem = { id: 'org.openai.chatgpt', title: 'ChatGPT', icon: 'chatgpt' }
const chatWindow = {
  workspace: { id: 4 },
  handle: { appId: 'chatgpt', activated: false },
  title: 'ChatGPT',
  lastIpcObject: {
    desktopEntry: 'chatgpt.desktop',
    class: 'chatgpt',
    initialClass: 'chatgpt'
  },
  activated: false
}
const route = routing.workspaceRouteDataForTrayItem(chatItem)
const match = routing.matchingWorkspaceToplevel(route, [chatWindow])
assert(route.enabled, 'ChatGPT tray identity should produce a route')
assert(match && match.toplevel === chatWindow, 'ChatGPT window should be located')
assert(match.workspaceId === 4, 'ChatGPT workspace should be preserved')
const arrayLikeMatch = routing.matchingWorkspaceToplevel(route, { 0: chatWindow, length: 1 })
assert(arrayLikeMatch && arrayLikeMatch.toplevel === chatWindow, 'array-like Hyprland values should be supported')
const xwaylandChatWindow = {
  workspace: { id: 1 },
  class: 'Chatgpt',
  initialClass: 'Chatgpt',
  title: 'ChatGPT',
  initialTitle: 'ChatGPT'
}
const xwaylandMatch = routing.matchingWorkspaceToplevel(route, [xwaylandChatWindow])
assert(xwaylandMatch && xwaylandMatch.toplevel === xwaylandChatWindow, 'XWayland class/title metadata should locate ChatGPT')

const serialized = routing.workspaceRouteDataForTrayIdentity('org.openai.chatgpt|ChatGPT||')
assert(routing.matchingWorkspaceToplevel(serialized, [chatWindow]), 'serialized tray identity should locate ChatGPT')
assert(!routing.matchingWorkspaceToplevel(
  routing.workspaceRouteDataForTrayItem({ id: 'chat', title: 'Chat' }),
  [{ workspace: { id: 4 }, handle: { appId: 'chatgpt' }, title: 'ChatGPT' }]
), 'generic chat identity must not route to ChatGPT')

// Startup focus fallback: select the single entry marked focusHistoryID 0,
// ignore entries without the marker, and fail closed when the marker is
// missing or ambiguous so a wrong window is never chosen.
const focusedToplevel = { lastIpcObject: { focusHistoryID: 0 } }
const otherToplevel = { lastIpcObject: { focusHistoryID: 2 } }
const noMarkerToplevel = { lastIpcObject: {} }
assert(routing.focusedToplevel([otherToplevel, focusedToplevel, noMarkerToplevel]) === focusedToplevel,
  'focused toplevel should be selected by focusHistoryID 0')
assert(routing.focusedToplevel([otherToplevel, noMarkerToplevel]) === null,
  'no focusHistoryID 0 must fail closed')
assert(routing.focusedToplevel([]) === null,
  'empty toplevel list must fail closed')
assert(routing.focusedToplevel(null) === null,
  'absent toplevel list must fail closed')
assert(routing.focusedToplevel([
  { lastIpcObject: { focusHistoryID: 0 } },
  { lastIpcObject: { focusHistoryID: 0 } }
]) === null, 'ambiguous focus markers must fail closed')
assert(routing.focusedToplevel([{ lastIpcObject: { focusHistoryID: '0' } }]) !== null,
  'numeric-string focus marker should resolve')
assert(routing.focusedToplevel({ 0: focusedToplevel, length: 1 }) === focusedToplevel,
  'array-like toplevels should resolve')
NODE_WINDOW_ROUTING
    if (( window_routing_status == 0 )); then
        pass "[isolated-runtime] Tray identity matching locates ChatGPT's workspace, rejects generic false matches, and the startup focus fallback selects focusHistoryID 0 while failing closed on absent or ambiguous markers"
    else
        fail "[isolated-runtime] Tray identity matching failed"
    fi
else
    skip "[isolated-runtime] Tray identity matching matrix (node unavailable)"
fi

if [[ -f "$power_root/manifest.json" && -f "$power_root/PowerBarWidget.qml" && -f "$power_root/PowerPanel.qml" &&
      -f "$session_actions_root/manifest.json" && -f "$session_actions_root/SessionActionsBarWidget.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.power" and (.kinds == ["bar-widget"])' "$power_root/manifest.json" >/dev/null &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.session-actions" and (.kinds == ["bar-widget"])' "$session_actions_root/manifest.json" >/dev/null &&
   ! grep -Eq 'loginctl|hyprctl|systemctl.*(poweroff|reboot|suspend)' "$power_root/PowerPanel.qml" &&
   grep -q 'AureliaIcon {' "$power_root/PowerBarWidget.qml" &&
   grep -q 'glyph: root.powerPanel' "$power_root/PowerBarWidget.qml" &&
   grep -q 'visible: root.batteryPresent' "$power_root/PowerBarWidget.qml" &&
   grep -q 'function batteryIcon()' "$power_root/PowerPanel.qml" &&
   grep -q 'showPercentage' "$power_root/PowerPanel.qml" &&
   grep -q 'profilesSection' "$power_root/PowerPanel.qml" &&
   grep -q 'progressSection' "$power_root/PowerPanel.qml" &&
   grep -q 'statsSection' "$power_root/PowerPanel.qml" &&
   grep -q 'font.family: Theme.fontFamilyResolved' "$power_root/PowerBarWidget.qml" "$power_root/PowerPanel.qml" &&
   grep -q 'AureliaToolTip' "$power_root/PowerBarWidget.qml" &&
   ! grep -q 'cardHeight' "$power_root/PowerPanel.qml" &&
   grep -q 'property QtObject runtime' "$session_actions_root/SessionActionsPanel.qml" &&
   grep -q 'function confirmPendingAction' "$session_actions_root/SessionActionsPanel.qml" &&
   grep -q 'function actionRows' "$session_actions_root/Model.js"; then
    pass "Power owns battery-aware geometry while Session Actions owns the separate session-action surface"
else
    fail "Power/session-action ownership or battery-aware bar widget contract is incomplete"
fi

if grep -q 'AureliaIcon {' "$ROOT/plugins/aurelia.monitor/DisplayBarWidget.qml" &&
   grep -Fq 'glyph: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"' "$ROOT/plugins/aurelia.monitor/DisplayBarWidget.qml" &&
   ! grep -q 'name: Quickshell.screens.length > 1' "$ROOT/plugins/aurelia.monitor/DisplayBarWidget.qml" &&
   ! grep -q 'fallbackName: "computer"' "$ROOT/plugins/aurelia.monitor/DisplayBarWidget.qml" &&
   grep -q 'AureliaIcon {' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'name: root.iconName' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'fallbackName: "weather-clear"' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'iconSize: root.iconCanvas' "$weather_root/WeatherBarWidget.qml" &&
   grep -q 'tint: root.barForeground' "$weather_root/WeatherBarWidget.qml"; then
    pass "Display and weather bar icons resolve through the theme-aware icon primitive"
else
    fail "Display or weather bar icon theme integration is incomplete"
fi

if grep -q 'AureliaIcon {' "$tasklist_root/TasklistBarWidget.qml" &&
   grep -q 'sourcePath: root.iconSourceFor(modelData, appEntry)' "$tasklist_root/TasklistBarWidget.qml" &&
   grep -q 'tint: root.barForeground' "$tasklist_root/TasklistBarWidget.qml" &&
   ! grep -q '^                Image {' "$tasklist_root/TasklistBarWidget.qml" &&
   grep -q 'AureliaIcon {' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'TrayIconPolicy.preserveColors' "$tray_root/TrayBarWidget.qml" &&
   [[ -f "$tray_root/TrayIconPolicy.js" ]] &&
   grep -q 'width: root.iconCanvas' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'height: root.iconCanvas' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'iconSize: root.iconCanvas' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'sourcePixelRatio: Screen.devicePixelRatio' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'smooth: false' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'modelData && modelData.icon ? String(modelData.icon) : ""' "$tray_root/TrayBarWidget.qml" &&
   grep -q 'tint: root.barForeground' "$tray_root/TrayBarWidget.qml" &&
   ! grep -q '^                Image {' "$tray_root/TrayBarWidget.qml"; then
    pass "Tasklist and tray icons inherit semantic foreground colors while retaining their resolved sources"
else
    fail "Tasklist or tray bar icons bypass the theme-aware icon primitive"
fi

if [[ -f "$clock_root/manifest.json" && -f "$clock_root/ClockBarWidget.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.clock" and (.kinds == ["bar-widget"]) and .entryPoints.barWidget == "ClockBarWidget.qml"' "$clock_root/manifest.json" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$clock_root" >/dev/null; then
    pass "Clock is a validated first-party bar-widget plugin"
else
    fail "Clock bar-widget manifest or entry point is incomplete"
fi

if [[ -f "$weather_root/manifest.json" && -f "$weather_root/WeatherBarWidget.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.weather" and (.kinds == ["bar-widget"]) and .entryPoints.barWidget == "WeatherBarWidget.qml"' "$weather_root/manifest.json" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$weather_root" >/dev/null; then
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
   grep -q 'format=j1' "$weather_bin" &&
   grep -q 'nearest_area\[0\]' "$weather_bin" &&
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

if grep -q 'aurelia.clock' "$ROOT/config/bar-default.json" &&
   grep -q 'aurelia.weather' "$ROOT/config/bar-default.json" &&
   grep -q 'centerAnchor.*aurelia.clock' "$ROOT/config/bar-default.json" &&
   grep -q 'function cloneEntrySettings(entry)' "$ROOT/services/ShellConfig.qml" &&
   grep -q 'entry.settings' "$bar_root/BarWidgetRow.qml" &&
   grep -q 'location.*auto' "$ROOT/config/bar-default.json"; then
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
   grep -q 'function onBarVisibleChanged' "$weather_root/WeatherBarWidget.qml" &&
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

section "Uniform Bar-Icon Contract"

icon_widget_files=(
    "$ROOT/plugins/aurelia.notifications/BarWidget.qml"
    "$ROOT/plugins/aurelia.weather/WeatherBarWidget.qml"
    "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotBarWidget.qml"
    "$ROOT/plugins/aurelia.network/NetworkBarWidget.qml"
    "$ROOT/plugins/aurelia.audio/AudioBarWidget.qml"
    "$ROOT/plugins/aurelia.bluetooth/BluetoothBarWidget.qml"
    "$ROOT/plugins/aurelia.monitor/DisplayBarWidget.qml"
    "$ROOT/plugins/aurelia.power/PowerBarWidget.qml"
    "$ROOT/plugins/aurelia.microphone/MicrophoneBarWidget.qml"
    "$ROOT/plugins/aurelia.session-actions/SessionActionsBarWidget.qml"
    "$ROOT/plugins/aurelia.tasklist/TasklistBarWidget.qml"
    "$ROOT/plugins/aurelia.tray/TrayBarWidget.qml"
    "$ROOT/plugins/aurelia.agents/AgentsBarWidget.qml"
    "$ROOT/plugins/aurelia.workspaces/WorkspacesBarWidget.qml"
)

# Extract only the body of each AureliaIcon { ... } declaration so the
# literal-size and tint assertions cannot be fooled by unrelated geometry.
extract_aurelia_icon_blocks() {
    awk '
        /AureliaIcon[[:space:]]*\{/ { inblock = 1; depth = 0 }
        inblock {
            print
            line = $0
            opens = gsub(/\{/, "{", line)
            closes = gsub(/\}/, "}", line)
            depth += opens - closes
            if (depth <= 0) inblock = 0
        }
    ' "$1"
}

icon_canvas_failures=0
icon_literal_failures=0
icon_tint_failures=0
icon_accent_failures=0
for widget_file in "${icon_widget_files[@]}"; do
    if [[ ! -f "$widget_file" ]] || ! grep -q 'barIconCanvas' "$widget_file"; then
        icon_canvas_failures=$((icon_canvas_failures + 1))
    fi
    icon_blocks="$(extract_aurelia_icon_blocks "$widget_file")"
    [[ -z "$icon_blocks" ]] && continue
    if grep -Eq '(^|[^[:alnum:]_])(width|height|iconSize)[[:space:]]*:[[:space:]]*[0-9]' <<<"$icon_blocks"; then
        icon_literal_failures=$((icon_literal_failures + 1))
    fi
    tint_count="$(grep -c 'tint[[:space:]]*:' <<<"$icon_blocks" || true)"
    fallback_count="$(grep -o 'root.barForeground' <<<"$icon_blocks" | wc -l)"
    if (( tint_count == 0 )) || (( fallback_count < tint_count )); then
        icon_tint_failures=$((icon_tint_failures + 1))
    fi
    if (( $(grep -c 'Theme.accent' <<<"$icon_blocks" || true) > 1 )); then
        icon_accent_failures=$((icon_accent_failures + 1))
    fi
done

if (( icon_canvas_failures == 0 )); then
    pass "[static] every first-party bar icon widget derives its ink from barIconCanvas"
else
    fail "[static] $icon_canvas_failures first-party bar icon widget(s) do not declare the shared barIconCanvas contract"
fi

if (( icon_literal_failures == 0 )); then
    pass "[static] no first-party bar widget AureliaIcon uses a literal width/height/iconSize"
else
    fail "[static] $icon_literal_failures first-party bar widget(s) still hard-code an icon ink size"
fi

if (( icon_tint_failures == 0 )); then
    pass "[static] every first-party bar widget icon rests at root.barForeground"
else
    fail "[static] $icon_tint_failures first-party bar widget tint expression(s) do not fall back to root.barForeground"
fi

if (( icon_accent_failures == 0 )); then
    pass "[static] no first-party bar widget exposes more than one Theme.accent icon state"
else
    fail "[static] $icon_accent_failures first-party bar widget(s) expose multiple accent icon states"
fi

if grep -q 'tint: root.doNotDisturb ? Theme.warning : root.barForeground' "$ROOT/plugins/aurelia.notifications/BarWidget.qml" &&
   grep -Fq 'tint: root.networkPanel && root.networkPanel.restricted' "$ROOT/plugins/aurelia.network/NetworkBarWidget.qml" &&
   grep -q 'Theme.warning : root.barForeground' "$ROOT/plugins/aurelia.network/NetworkBarWidget.qml" &&
   grep -q 'tint: root.panelVisible ? Theme.accent : root.barForeground' "$ROOT/plugins/aurelia.audio/AudioBarWidget.qml" &&
   grep -q 'tint: root.isVisible() ? Theme.accent : root.barForeground' "$ROOT/plugins/aurelia.bluetooth/BluetoothBarWidget.qml" &&
   grep -q 'tint: root.isVisible() ? Theme.accent : root.barForeground' "$ROOT/plugins/aurelia.monitor/DisplayBarWidget.qml" &&
   grep -q 'tint: root.inUse ? Theme.accent : root.barForeground' "$ROOT/plugins/aurelia.microphone/MicrophoneBarWidget.qml"; then
    pass "[static] the only non-foreground icon states are the documented DND, restricted-network, open-panel, and in-use alerts"
else
    fail "[static] a documented active/alert icon state is missing or uses the wrong token"
fi

if grep -q 'focusedGlyphSize: Math.round(root.iconCanvas \* 0.9)' "$ROOT/plugins/aurelia.workspaces/WorkspacesBarWidget.qml" &&
   grep -q 'font.pixelSize: !focused && !occupied' "$ROOT/plugins/aurelia.workspaces/WorkspacesBarWidget.qml" &&
   grep -q 'focused ? root.focusedGlyphSize' "$ROOT/plugins/aurelia.workspaces/WorkspacesBarWidget.qml" &&
   grep -q 'renderType: Text.NativeRendering' "$ROOT/plugins/aurelia.workspaces/WorkspacesBarWidget.qml" &&
   grep -q 'font.family: Theme.fontFamilyResolved' "$ROOT/plugins/aurelia.workspaces/WorkspacesBarWidget.qml"; then
    pass "[static] the raw focused-workspace Text glyph uses the canvas-derived optical font size with native rendering"
else
    fail "[static] focused-workspace glyph does not follow the canvas-derived metric"
fi

if grep -q 'glyph: "󰚩"' "$ROOT/plugins/aurelia.agents/AgentsBarWidget.qml" &&
   grep -q 'AureliaIcon {' "$ROOT/plugins/aurelia.agents/AgentsBarWidget.qml" &&
   ! grep -q 'font.pixelSize: root.bar && root.bar.barIconFont' "$ROOT/plugins/aurelia.agents/AgentsBarWidget.qml"; then
    pass "[static] the agents usage glyph renders through AureliaIcon instead of a raw Text glyph"
else
    fail "[static] the agents usage glyph still bypasses the shared icon primitive"
fi

# The multi-colour brand/tray exception is the only place preserveColors is
# allowed; everything else must be tinted to the bar foreground.
if grep -q 'preserveColors: TrayIconPolicy.preserveColors' "$ROOT/plugins/aurelia.tray/TrayBarWidget.qml" &&
   [[ -f "$tray_root/TrayIconPolicy.js" ]]; then
    pass "[static] tray is the single documented preserveColors exception for multi-colour art"
else
    fail "[static] tray preserveColors policy is not routed through the shared tray icon policy"
fi

if command -v node >/dev/null; then
    tray_policy_status=0
    node - "$tray_root/TrayIconPolicy.js" <<'NODE_TRAY_ICON_POLICY' || tray_policy_status=$?
const assert = require('assert')
const policy = require(process.argv[2])
assert.strictEqual(policy.isSymbolicIcon('foo-symbolic'), true)
assert.strictEqual(policy.isSymbolicIcon('foo-symbolic?query=1'), true)
assert.strictEqual(policy.isSymbolicIcon('foo'), false)
assert.strictEqual(policy.isSymbolicIcon(''), false)
assert.strictEqual(policy.preserveColors('foo'), true)
assert.strictEqual(policy.preserveColors('foo-symbolic'), false)
console.log('tray icon policy ok')
NODE_TRAY_ICON_POLICY
    if (( tray_policy_status == 0 )); then
        pass "[isolated-node] tray icon policy tints symbolic artwork and preserves multi-colour brand art"
    else
        fail "[isolated-node] tray icon policy split failed"
    fi
else
    skip "[isolated-node] tray icon policy split (node unavailable)"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] bar icon contract fixture (qs or timeout unavailable)"
    return 0
fi

bar_icon_runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$bar_icon_runtime_root" || true' RETURN
for font_base in 9 12 16; do
    case_root="$bar_icon_runtime_root/$font_base"
    mkdir -p "$case_root/config/aurelia" "$case_root/runtime" "$case_root/state" "$case_root/cache" "$case_root/home"
    printf 'fontBaseSize = %s\n' "$font_base" >"$case_root/config/aurelia/display.conf"
    : >"$case_root/result.json"
    runtime_status=0
    AURELIA_BAR_ICONS_RESULT="$case_root/result.json" \
    AURELIA_BAR_ICONS_WIDGET_SOURCE="file://$ROOT/plugins/aurelia.notifications/BarWidget.qml" \
    AURELIA_BAR_ICONS_ICON_SOURCE="file://$ROOT/ui/AureliaIcon.qml" \
    QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$case_root/runtime" XDG_CONFIG_HOME="$case_root/config" \
    XDG_STATE_HOME="$case_root/state" XDG_CACHE_HOME="$case_root/cache" HOME="$case_root/home" \
        /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
        --path "$ROOT/tests/fixtures/bar-icons/shell.qml" --no-color >"$case_root/runtime.log" 2>&1 || runtime_status=$?

    expected_canvas=$(( (16 * font_base + 6) / 12 ))
    expected_pixel=$(( (expected_canvas * 9 + 5) / 10 ))
    if [[ "$runtime_status" -eq 0 && -s "$case_root/result.json" ]] &&
       jq -e --argjson ec "$expected_canvas" --argjson ep "$expected_pixel" '
           .loaded == true and
           .theme.iconCanvas == $ec and
           .glyph.usingGlyph == true and
           .glyph.opticallyCentered == true and
           .glyph.canvasWidth == $ec and
           .glyph.canvasHeight == $ec and
           .glyph.iconSize == $ec and
           .glyph.pixelSize == $ep and
           .glyph.tint == "#ffffff" and
           (((.glyph.inkCenterX - .glyph.canvasCenterX) | if . < 0 then -. else . end) < 0.5) and
           .symbolic.preserveColors == false and
           .symbolic.imageVisible == false and
           .symbolic.effectVisible == true and
           .symbolic.preserveAspectFit == true and
           .symbolic.imageWidth == 16 and
           .symbolic.imageHeight == 16 and
           .brand.preserveColors == true and
           .brand.imageVisible == true and
           .brand.effectVisible == false
       ' "$case_root/result.json" >/dev/null &&
       runtime_log_is_environment_only "$case_root/runtime.log"; then
        pass "[isolated-runtime] bar icon contract holds at fontBaseSize $font_base (canvas=$expected_canvas, glyph=$expected_pixel)"
    else
        details="$(tr '\n' ' ' <"$case_root/runtime.log")"
        if [[ -s "$case_root/result.json" ]]; then details="$details result=$(tr '\n' ' ' <"$case_root/result.json")"; fi
        fail "[isolated-runtime] bar icon contract failed at fontBaseSize $font_base: $details"
    fi
done
