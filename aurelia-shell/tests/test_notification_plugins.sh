#!/usr/bin/env bash

# Contract tests for Aurelia's resident notification service, center, DND
# policy, and reusable bar tooltip. These tests are static, pure-JavaScript,
# and isolated-file-operation checks; they never mutate the live notification
# bus or desktop.

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

if [[ -f "$plugin_root/Service.qml" && -f "$plugin_root/BarWidget.qml" && -f "$plugin_root/NotificationLogic.js" && -f "$plugin_root/NotificationFileLogic.js" && -f "$plugin_root/ui/NotificationPopupSurface.qml" && -f "$plugin_root/ui/qmldir" ]] &&
   [[ -x "$ROOT/bin/aurelia-notification-send" ]] &&
   ! grep -q 'notify-send' "$ROOT/bin/aurelia-notification-send" &&
   [[ -f "$plugin_root/NotificationServerHost.qml" ]] &&
   grep -q 'import Quickshell.Services.Notifications' "$plugin_root/NotificationServerHost.qml" &&
   grep -q 'Loader {' "$plugin_root/Service.qml" &&
   grep -q 'NotificationServer {' "$plugin_root/NotificationServerHost.qml" &&
   grep -q 'keepOnReload: true' "$plugin_root/NotificationServerHost.qml" &&
   grep -q 'bodyMarkupSupported: true' "$plugin_root/NotificationServerHost.qml" &&
   grep -q 'pendingNotifications' "$plugin_root/NotificationServerHost.qml" &&
   grep -q 'function deliver' "$plugin_root/NotificationServerHost.qml" &&
   grep -q 'NotificationFileLogic' "$plugin_root/Service.qml" &&
   grep -q 'NotificationPopupSurface' "$plugin_root/Service.qml" &&
   grep -q 'notification.tracked = true' "$plugin_root/Service.qml" &&
   grep -q 'property var liveRefs' "$plugin_root/Service.qml" &&
   grep -q 'ListModel' "$plugin_root/Service.qml" &&
   grep -q 'onNotification:' "$plugin_root/NotificationServerHost.qml" &&
   grep -q 'NotificationToast 1.0 NotificationToast.qml' "$plugin_root/ui/qmldir" &&
   grep -q 'NotificationCenterPanel 1.0 NotificationCenterPanel.qml' "$plugin_root/ui/qmldir" &&
   grep -q 'NotificationPopupSurface 1.0 NotificationPopupSurface.qml' "$plugin_root/ui/qmldir"; then
    pass "Notification objects stay outside UI models and private QML types are explicitly registered"
else
    fail "Notification service lifecycle or private type registration is incomplete"
fi

if ! [[ -f "$plugin_root/ui/NotificationRow.qml" ]] &&
   grep -q 'NotificationToast {' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'defaultActionText' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'defaultActionInvoked' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'Flow {' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'maximumLineCount: 2' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'centerLabel: true' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'showArchive' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'label: "Archive"' "$plugin_root/ui/NotificationToast.qml" &&
   ! grep -q 'timestamp: activeDelegate.timestamp' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   ! grep -q 'timestamp: historyDelegate.timestamp' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'actions: historyDelegate.actions' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'invokeHistoryDefault' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'implicitHeight: toastCard.implicitHeight' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'onActivated: root.service.invokeDefault' "$plugin_root/ui/NotificationCenterPanel.qml"; then
    pass "Active and History views share one notification card presentation"
else
    fail "Notification center still has a divergent or dead history-row presentation"
fi

if grep -q 'property bool doNotDisturb' "$plugin_root/Service.qml" &&
   grep -q 'XDG_STATE_HOME' "$plugin_root/Service.qml" &&
   grep -q 'readonly property string popupStateDir' "$plugin_root/Service.qml" &&
   grep -q 'readonly property string historyDir' "$plugin_root/Service.qml" &&
   grep -q 'readonly property string imagesDir' "$plugin_root/Service.qml" &&
   grep -q 'function persistPopupFile' "$plugin_root/Service.qml" &&
   grep -q 'function archivePopupFileFor' "$plugin_root/Service.qml" &&
   grep -q 'function restorePopups' "$plugin_root/Service.qml" &&
   grep -q 'function isManualInboxEntry' "$plugin_root/Service.qml" &&
   grep -q 'var manualInbox = isManualInboxEntry(entry)' "$plugin_root/Service.qml" &&
   grep -q 'function sweepOrphanImages' "$plugin_root/Service.qml" &&
   grep -q 'notificationBusRetryTimer.restart' "$plugin_root/Service.qml" &&
   grep -q 'atomicWrites: true' "$plugin_root/Service.qml" &&
   grep -q 'blockWrites: true' "$plugin_root/Service.qml" &&
   grep -q 'function toggleDnd' "$plugin_root/Service.qml" &&
   grep -q 'function showHistory' "$plugin_root/Service.qml" &&
   grep -q 'function clearHistory' "$plugin_root/Service.qml" &&
   grep -q 'function dismissAll' "$plugin_root/Service.qml" &&
   grep -q 'function publishScreenshot' "$plugin_root/Service.qml" &&
   grep -q 'property var liveSnapshots' "$plugin_root/Service.qml" &&
   grep -q 'property alias popupModel' "$plugin_root/Service.qml" &&
   grep -q 'ListModel { id: popupNotificationsModel }' "$plugin_root/Service.qml" &&
   grep -q 'function removePopupByIdentity' "$plugin_root/Service.qml" &&
   grep -q 'function insertPopupSnapshot' "$plugin_root/Service.qml" &&
   grep -q 'popup.expired inbox_retained' "$plugin_root/Service.qml" &&
   grep -q 'function flushState' "$plugin_root/Service.qml" &&
   grep -q 'history.saved count=' "$plugin_root/Service.qml" &&
   grep -q 'history.recorded key=' "$plugin_root/Service.qml" &&
   grep -q 'popup.expire index=' "$plugin_root/Service.qml" &&
   grep -q 'function removeByOriginalId' "$plugin_root/Service.qml" &&
   grep -q 'function removeByIdentity' "$plugin_root/Service.qml" &&
   grep -q 'function activeIndexForIdentity' "$plugin_root/Service.qml" &&
   grep -q 'popup.archive_skipped' "$plugin_root/Service.qml" &&
   ! grep -q 'property Timer stateSaveTimer' "$plugin_root/Service.qml" &&
   grep -q 'notificationBusProbe' "$plugin_root/Service.qml" &&
   grep -q 'busctl' "$plugin_root/Service.qml" &&
   grep -q 'busOwnerPid' "$plugin_root/Service.qml" &&
   grep -q 'notificationBusHealthTimer' "$plugin_root/Service.qml" &&
   grep -q 'active: true' "$plugin_root/Service.qml" &&
   grep -q 'file_job_retry' "$plugin_root/Service.qml" &&
   grep -q 'file_job_failed' "$plugin_root/Service.qml" &&
   grep -q 'server.bus_available' "$plugin_root/Service.qml" &&
   grep -q 'server.bus_owned external=true' "$plugin_root/Service.qml" &&
   grep -q 'target: "aurelia.notifications"' "$plugin_root/Service.qml"; then
    pass "DND and bounded history have an XDG-state-backed service API with center actions"
else
    fail "Notification DND/history persistence or IPC contract is incomplete"
fi

if grep -q 'aurelia-action' "$plugin_root/NotificationLogic.js" &&
   grep -q 'notify-send' "$plugin_root/NotificationLogic.js" &&
   grep -q 'function styledBody' "$plugin_root/NotificationLogic.js" &&
   grep -q 'function parseExecArgv' "$plugin_root/NotificationLogic.js" &&
   grep -q 'function persistablePopup' "$plugin_root/NotificationLogic.js" &&
   grep -q 'function popupPlacement' "$plugin_root/NotificationLogic.js" &&
   grep -q 'shouldBypassDnd(notification, 2)' "$plugin_root/Service.qml" &&
   grep -q 'durationFor' "$plugin_root/NotificationLogic.js" &&
   grep -q 'isInboxPersistent' "$plugin_root/NotificationLogic.js" &&
   grep -q 'popupSlot.appIcon' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'MAX_TEXT_LENGTH' "$plugin_root/NotificationLogic.js" &&
   ! grep -R -Eiq 'noctalia' "$plugin_root"; then
    pass "DND bypass, duration bounds, input limits, and Noctalia independence are explicit"
else
    fail "Notification policy boundary or Noctalia independence is incomplete"
fi

if grep -q 'import Quickshell.Hyprland' "$plugin_root/Service.qml" &&
   grep -q 'workspaceRouteData' "$plugin_root/Service.qml" &&
   grep -q 'workspaceRouteScore' "$plugin_root/Service.qml" &&
   grep -q 'Hyprland.dispatch' "$plugin_root/Service.qml" &&
   grep -q 'workspace.activate' "$plugin_root/Service.qml" &&
   grep -q 'workspace.switch_requested' "$plugin_root/Service.qml" &&
   grep -q 'workspace.routed' "$plugin_root/Service.qml" &&
   grep -q 'workspace.route_unavailable' "$plugin_root/Service.qml"; then
    pass "Notification actions route to the matching Hyprland workspace with bounded retry"
else
    fail "Notification workspace routing or bounded fallback is incomplete"
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
   grep -q '^AureliaKeyboardPanel {' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'bar: root.service ? root.service.bar : null' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'ownerId: "aurelia.notifications"' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'popupWidth: Math.min(400' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'popupHeight: Math.min' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'anchorItemFor("aurelia.notifications")' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'var targetScreen = root.screenModel' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'visible: root.notificationService !== null && root.notificationService.popupModel.count > 0 && root.anchored' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'showArchive: true' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'showArchive: true' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'function archiveByIdentity' "$plugin_root/Service.qml" &&
   grep -q 'inbox.archived' "$plugin_root/Service.qml" &&
   grep -q 'popupOrigin' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'AureliaIconButton' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'currentViewEmpty' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'Layout.maximumHeight: 32' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'You’re all caught up' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   ! grep -q 'AureliaActionButton {' "$plugin_root/ui/NotificationCenterPanel.qml"; then
    pass "Notification center uses compact icon actions, a lighter segmented layout, and a dynamic bar anchor"
else
    fail "Notification center layout or dynamic bar anchoring is incomplete"
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
if (!logic.isInboxPersistent("ChatGPT", "chatgpt", "chatgpt")) process.exit(1);
if (logic.durationFor(1, 0, "ChatGPT", "chatgpt", "chatgpt") !== 0) process.exit(1);
if (logic.durationFor(1, 0, "Other", "other", "other") !== 8000) process.exit(1);
if (!logic.hasBusName("org.freedesktop.Notifications 123 quickshell\n", "org.freedesktop.Notifications")) process.exit(1);
if (logic.hasBusName("org.freedesktop.DBus 1 dbus\n", "org.freedesktop.Notifications")) process.exit(1);
if (!logic.screenshotSnapshot("/tmp/capture.png", 123).image.startsWith("file:///tmp/")) process.exit(1);
if (logic.screenshotSnapshot("relative.png", 123) !== null) process.exit(1);
if (logic.parseSettings('{"dnd":true}').dnd !== true) process.exit(1);
if (logic.parseSettings('{bad').ok) process.exit(1);
if (logic.isRenderableHistoryEntry({ summary: "" })) process.exit(1);
if (!logic.isRenderableHistoryEntry({ summary: "Agent complete" })) process.exit(1);
if (logic.historyKey({ originalId: 2, timestamp: 10 }) !== "10|2") process.exit(1);
if (logic.busOwnerPid("NAME=org.freedesktop.Notifications\nPID=1234\n") !== 1234) process.exit(1);
if (logic.busOwnerPid("NAME=org.freedesktop.Notifications\nPID=0\n") !== 0) process.exit(1);
if (logic.styledBody('<b>bold</b>\n<img src="https://example.invalid/x">second', 'Chromium', '') !== '<b>bold</b><br/>second') process.exit(1);
if (JSON.stringify(logic.parseExecArgv('["xdg-open","/tmp/a b"]')) !== '["xdg-open","/tmp/a b"]') process.exit(1);
if (logic.parseExecArgv('["--bad"]') !== null) process.exit(1);
const popup = { id: 7, originalId: 7, timestamp: 100, appIcon: 'file:///tmp/avatar.png', summary: 'Saved' };
if (logic.popupFileName(popup) !== '100-7.json') process.exit(1);
if (logic.popupFileName({ summary: 'missing identity' }) !== '') process.exit(1);
if (!logic.hasPopupIdentity(popup) || logic.hasPopupIdentity({ summary: 'missing identity' })) process.exit(1);
const persistable = logic.persistablePopup(popup, '/tmp/state/images/');
if (persistable.copies.length !== 1 || persistable.entry.appIcon !== 'file:///tmp/state/images/100-7-appIcon') process.exit(1);
if (logic.popupExpired({ timestamp: 100 }, 8000, 9000) !== true) process.exit(1);
if (logic.popupPlacement('top', 32, 6).margins.top !== 32) process.exit(1);
const snapshot = logic.snapshotOf({ id: 4, appName: "demo", summary: "Hello", body: "World", urgency: 1 }, 123);
if (snapshot.originalId !== 4 || snapshot.timestamp !== 123 || snapshot.actions.length !== 0 || snapshot.defaultActionText !== "") process.exit(1);
if (snapshot.deadline !== 8123) process.exit(1);
const chatSnapshot = logic.snapshotOf({ id: 6, appName: "ChatGPT", appIcon: "chatgpt", desktopEntry: "chatgpt", summary: "Complete" }, 456);
if (chatSnapshot.deadline !== 0 || logic.durationFor(chatSnapshot.urgency, chatSnapshot.expireTimeout, chatSnapshot.app, chatSnapshot.desktopEntry, chatSnapshot.appIcon) !== 0) process.exit(1);
if (logic.snapshotOf({ id: 7, appName: "Mail", summary: "Inbox" }, 789).transient) process.exit(1);
if (!logic.screenshotSnapshot("/tmp/capture.png", 789).transient) process.exit(1);
const actionSnapshot = logic.snapshotOf({ id: 5, actions: [{ identifier: "default", text: "" }] }, 456);
if (actionSnapshot.actions.length !== 0 || actionSnapshot.defaultActionText !== "Open") process.exit(1);
const historySnapshot = logic.historyEntry({
    summary: "Saved",
    body: "A historical notification",
    actions: [{ identifier: "default", text: "Open" }, { identifier: "reply", text: "Reply" }],
    defaultActionText: "Open"
});
if (historySnapshot.defaultActionText !== "Open" || historySnapshot.actions.length !== 1 || historySnapshot.actions[0].identifier !== "reply") process.exit(1);
const parsedHistory = logic.parseHistory(JSON.stringify({ notifications: [historySnapshot] }), 50);
if (parsedHistory.length !== 1 || parsedHistory[0].actions.length !== 1 || parsedHistory[0].defaultActionText !== "Open") process.exit(1);
const chatRoute = logic.workspaceRouteData({ desktopEntry: "chatgpt.desktop", appName: "ChatGPT" });
if (!chatRoute.enabled || logic.workspaceRouteScore(chatRoute, { appId: "chatgpt", className: "chatgpt", activated: false }) <= 0) process.exit(1);
if (logic.workspaceRouteScore(chatRoute, { appId: "org.mozilla.firefox", className: "firefox", activated: false }) !== 0) process.exit(1);
if (logic.workspaceRouteScore(logic.workspaceRouteData({ appName: "chat" }), { appId: "chatgpt", className: "chatgpt" }) !== 0) process.exit(1);
if (logic.workspaceRouteScore(chatRoute, { appId: "chatgpt", activated: true }) <= logic.workspaceRouteScore(chatRoute, { appId: "chatgpt", activated: false })) process.exit(1);
NODE_LOGIC
    then
        pass "Notification policy and serialization helpers pass deterministic runtime checks"
    else
        fail "Notification pure logic helpers returned an unexpected result"
    fi
else
    pass "SKIP notification logic runtime check (node unavailable)"
fi

if command -v node >/dev/null 2>&1; then
    if node - "$plugin_root/NotificationLogic.js" "$plugin_root/NotificationFileLogic.js" <<'NODE_FILES'
const fs = require("fs");
const path = require("path");
const childProcess = require("child_process");
const logic = require(process.argv[2]);
const fileLogic = require(process.argv[3]);
const root = fs.mkdtempSync("/tmp/aurelia-notification-files-");
const live = path.join(root, "live");
const history = path.join(root, "history");
const images = path.join(root, "images");

function run(command) {
    const result = childProcess.spawnSync(command[0], command.slice(1), { encoding: "utf8" });
    if (result.status !== 0) throw new Error(`command failed (${result.status}): ${result.stderr}`);
    return result.stdout;
}

function entry(id, timestamp) {
    return {
        id,
        originalId: id,
        timestamp,
        app: "test",
        summary: `Notification ${id}`,
        body: "body",
        image: "",
        appIcon: "",
        actions: [],
        defaultActionText: "",
        urgency: 1,
        expireTimeout: 0
    };
}

try {
    fs.mkdirSync(live, { recursive: true });
    fs.mkdirSync(history, { recursive: true });
    fs.mkdirSync(images, { recursive: true });
    const first = entry(1, 100);
    const firstPersistable = logic.persistablePopup(first, `${images}/`);
    run(fileLogic.persistPopup(
        { ...firstPersistable, json: logic.serializePopup(firstPersistable.entry, 1) },
        `${live}/`, `${images}/`, logic.popupFileName(first)
    ));
    if (!fs.existsSync(path.join(live, "100-1.json"))) throw new Error("live popup was not persisted");
    if (fs.readdirSync(live).some(name => name.includes(".tmp."))) throw new Error("live temp file remained");
    if (!run(fileLogic.readDirectory(`${live}/`)).includes("Notification 1")) throw new Error("live popup was not readable");
    run(fileLogic.archivePopup(`${history}/`, `${live}/`, `${images}/`, "100-1.json", 2));
    if (!fs.existsSync(path.join(history, "100-1.json"))) throw new Error("popup archive failed");
    for (const value of [entry(2, 200), entry(3, 300), entry(4, 400)]) {
        const persistable = logic.persistablePopup(value, `${images}/`);
        run(fileLogic.writeHistory(
            { ...persistable, json: logic.serializePopup(persistable.entry, 1) },
            `${history}/`, `${images}/`, logic.popupFileName(value), 2
        ));
    }
    const names = fs.readdirSync(history).filter(name => name.endsWith(".json")).sort();
    if (JSON.stringify(names) !== JSON.stringify(["300-3.json", "400-4.json"])) throw new Error(`history trim failed: ${names}`);
    run(fileLogic.clearHistory(`${history}/`, `${images}/`));
    if (fs.readdirSync(history).some(name => name.endsWith(".json"))) throw new Error("history clear failed");
} finally {
    fs.rmSync(root, { recursive: true, force: true });
}
NODE_FILES
    then
        pass "Notification state files use bounded, atomic isolated operations"
    else
        fail "Notification state file operation contract failed"
    fi
else
    pass "SKIP notification file operation check (node unavailable)"
fi
