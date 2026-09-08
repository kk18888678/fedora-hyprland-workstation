#!/usr/bin/env bash

# Contract tests for Aurelia's resident notification service, center, DND
# policy, and reusable bar tooltip. These tests are intentionally static plus
# pure-JavaScript; they never mutate the live notification bus or desktop.

set -Eeuo pipefail

plugin_root="$ROOT/plugins/aurelia.notifications"
tooltip_qml="$ROOT/ui/AureliaToolTip.qml"

section "Notification Plugin Contract"

if [[ -f "$plugin_root/manifest.json" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.notifications" and
       .name == "Notifications" and
       .keepLoaded == true and
       (.kinds | index("service")) != null and
       (.kinds | index("bar-widget")) != null and
       .entryPoints.service == "Service.qml" and
       .entryPoints["bar-widget"] == "BarWidget.qml"
   ' "$plugin_root/manifest.json" >/dev/null; then
    pass "Notifications declares a resident service and separate bar affordance"
else
    fail "Notifications manifest is missing or does not declare both entry points"
fi

validation_output="$($ROOT/bin/aurelia-plugin validate --first-party "$plugin_root" 2>&1)"
if [[ "$validation_output" == *"Valid Aurelia plugin: aurelia.notifications"* ]]; then
    pass "Notifications passes the shared first-party manifest validator"
else
    fail "Notifications manifest validation failed: $validation_output"
fi

if [[ -f "$plugin_root/Service.qml" && -f "$plugin_root/BarWidget.qml" && -f "$plugin_root/NotificationLogic.js" && -f "$plugin_root/ui/qmldir" ]] &&
   [[ -f "$plugin_root/NotificationServerHost.qml" ]] &&
   grep -q 'import Quickshell.Services.Notifications' "$plugin_root/NotificationServerHost.qml" &&
   grep -q 'Loader {' "$plugin_root/Service.qml" &&
   grep -q 'NotificationServer {' "$plugin_root/NotificationServerHost.qml" &&
   grep -q 'notification.tracked = true' "$plugin_root/Service.qml" &&
   grep -q 'property var liveRefs' "$plugin_root/Service.qml" &&
   grep -q 'ListModel' "$plugin_root/Service.qml" &&
   grep -q 'onNotification:' "$plugin_root/NotificationServerHost.qml" &&
   grep -q 'NotificationToast 1.0 NotificationToast.qml' "$plugin_root/ui/qmldir" &&
   grep -q 'NotificationRow 1.0 NotificationRow.qml' "$plugin_root/ui/qmldir" &&
   grep -q 'NotificationCenterPanel 1.0 NotificationCenterPanel.qml' "$plugin_root/ui/qmldir"; then
    pass "Notification objects stay outside UI models and private QML types are explicitly registered"
else
    fail "Notification service lifecycle or private type registration is incomplete"
fi

if grep -q 'property bool doNotDisturb' "$plugin_root/Service.qml" &&
   grep -q 'XDG_STATE_HOME' "$plugin_root/Service.qml" &&
   grep -q 'atomicWrites: true' "$plugin_root/Service.qml" &&
   grep -q 'blockWrites: true' "$plugin_root/Service.qml" &&
   grep -q 'function toggleDnd' "$plugin_root/Service.qml" &&
   grep -q 'function showHistory' "$plugin_root/Service.qml" &&
   grep -q 'function clearHistory' "$plugin_root/Service.qml" &&
   grep -q 'function dismissAll' "$plugin_root/Service.qml" &&
   grep -q 'function publishScreenshot' "$plugin_root/Service.qml" &&
   grep -q 'notificationBusProbe' "$plugin_root/Service.qml" &&
   grep -q 'busctl' "$plugin_root/Service.qml" &&
   grep -q 'server.bus_available' "$plugin_root/Service.qml" &&
   grep -q 'server.bus_owned external=true' "$plugin_root/Service.qml" &&
   grep -q 'target: "aurelia.notifications"' "$plugin_root/Service.qml"; then
    pass "DND and bounded history have an XDG-state-backed service API with center actions"
else
    fail "Notification DND/history persistence or IPC contract is incomplete"
fi

if grep -q 'aurelia-action' "$plugin_root/NotificationLogic.js" &&
   grep -q 'notify-send' "$plugin_root/NotificationLogic.js" &&
   grep -q 'shouldBypassDnd(notification, 2)' "$plugin_root/Service.qml" &&
   grep -q 'durationFor' "$plugin_root/NotificationLogic.js" &&
   grep -q 'MAX_TEXT_LENGTH' "$plugin_root/NotificationLogic.js" &&
   ! grep -R -Eiq 'noctalia' "$plugin_root"; then
    pass "DND bypass, duration bounds, input limits, and Noctalia independence are explicit"
else
    fail "Notification policy boundary or Noctalia independence is incomplete"
fi

if grep -q 'shell.call("aurelia.notifications"' "$plugin_root/BarWidget.qml" &&
   grep -q 'Qt.RightButton' "$plugin_root/BarWidget.qml" &&
   grep -q 'AureliaToolTip' "$plugin_root/BarWidget.qml" &&
   grep -q 'notifications-disabled' "$plugin_root/BarWidget.qml"; then
    pass "Notification bar widget opens the center and gives DND a discoverable right-click action"
else
    fail "Notification bar affordance or DND interaction is incomplete"
fi

if [[ -f "$ROOT/ui/AureliaIconButton.qml" ]] &&
   grep -q 'AureliaIconButton 1.0 AureliaIconButton.qml' "$ROOT/ui/qmldir" &&
   grep -q 'AureliaIconButton' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   ! grep -q 'AureliaActionButton {' "$plugin_root/ui/NotificationCenterPanel.qml"; then
    pass "Notification center uses compact icon actions and a lighter segmented layout"
else
    fail "Notification center still uses the oversized action-button-heavy layout"
fi

section "Shared Tooltip Geometry"

if [[ -f "$tooltip_qml" ]] &&
   grep -q 'PopupWindow {' "$tooltip_qml" &&
   grep -q 'anchorWindow' "$tooltip_qml" &&
   grep -q 'adjustment: PopupAdjustment.Slide' "$tooltip_qml" &&
   grep -q 'position === "bottom"' "$tooltip_qml" &&
   grep -q 'point.y = Math.max' "$tooltip_qml" &&
   grep -q 'AureliaToolTip 1.0 AureliaToolTip.qml' "$ROOT/ui/qmldir" &&
   grep -q 'AureliaToolTip {' "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotBarWidget.qml" &&
   grep -q 'publishScreenshot' "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotBarWidget.qml" &&
   ! grep -Eq '(^|[[:space:]])ToolTip[[:space:]]*\{' "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotBarWidget.qml"; then
    pass "Bar tooltips use a standalone anchored window with full below/above placement"
else
    fail "Shared tooltip placement still relies on a clipped control overlay"
fi

if grep -q 'if (hasKind(manifest, "service")) return "service"' "$ROOT/services/PluginRegistry.qml" &&
   grep -q 'aurelia.notifications' "$ROOT/services/ShellConfig.qml" &&
   grep -q 'aurelia.notifications' "$ROOT/plugins/aurelia.bar/Bar.qml"; then
    pass "Multi-kind notification plugins load their service owner before bar presentation"
else
    fail "Multi-kind plugin selection or default bar registration is incomplete"
fi

if command -v node >/dev/null 2>&1; then
    if node - "$plugin_root/NotificationLogic.js" <<'NODE_LOGIC'
const logic = require(process.argv[2]);

if (!logic.shouldBypassDnd({ appName: "aurelia-action", urgency: 1 }, 2)) process.exit(1);
if (!logic.shouldBypassDnd({ appName: "notify-send", urgency: 2 }, 2)) process.exit(1);
if (logic.shouldBypassDnd({ appName: "chat-app", urgency: 2 }, 2)) process.exit(1);
if (logic.durationFor(2, 10000) !== 0) process.exit(1);
if (logic.durationFor(1, 100) !== 8000) process.exit(1);
if (!logic.hasBusName("org.freedesktop.Notifications 123 quickshell\n", "org.freedesktop.Notifications")) process.exit(1);
if (logic.hasBusName("org.freedesktop.DBus 1 dbus\n", "org.freedesktop.Notifications")) process.exit(1);
if (!logic.screenshotSnapshot("/tmp/capture.png", 123).image.startsWith("file:///tmp/")) process.exit(1);
if (logic.screenshotSnapshot("relative.png", 123) !== null) process.exit(1);
if (logic.parseSettings('{"dnd":true}').dnd !== true) process.exit(1);
if (logic.parseSettings('{bad').ok) process.exit(1);
const snapshot = logic.snapshotOf({ id: 4, appName: "demo", summary: "Hello", body: "World", urgency: 1 }, 123);
if (snapshot.originalId !== 4 || snapshot.timestamp !== 123 || snapshot.actions.length !== 0) process.exit(1);
NODE_LOGIC
    then
        pass "Notification policy and serialization helpers pass deterministic runtime checks"
    else
        fail "Notification pure logic helpers returned an unexpected result"
    fi
else
    pass "SKIP notification logic runtime check (node unavailable)"
fi
