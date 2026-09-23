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
       .entryPoints.barWidget == "BarWidget.qml"
   ' "$plugin_root/manifest.json" >/dev/null; then
    pass "Notifications declares a resident service and separate bar affordance"
else
    fail "Notifications manifest is missing or does not declare both entry points"
fi

validation_output="$("$ROOT"/bin/aurelia-plugin validate --first-party "$plugin_root" 2>&1)"
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
   grep -q 'dismissPopupAt' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'dismissAt(index, originalId, timestamp)' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   ! grep -q 'dismissAt(index, originalId, timestamp)' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'notification.tracked = true' "$plugin_root/Service.qml" &&
   grep -q 'property var liveRefs' "$plugin_root/Service.qml" &&
   grep -q 'property var identityOriginalId' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'signal dismissed(var originalId, real timestamp, int index)' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'function emitDismissed' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'function dismissFromClose' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'function dismissFromPointer' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'root.dismissFromClose()' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'root.dismissFromPointer(mouse.button)' "$plugin_root/ui/NotificationToast.qml" &&
   ! grep -Eq 'root\.dismissed\([[:space:]]*\)' "$plugin_root/ui/NotificationToast.qml" &&
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
   ! grep -q 'maximumLineCount: 3' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'font.family: "Liberation Sans"' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'font.pixelSize: Theme.fontSizeSm' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'import Quickshell' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'Quickshell.iconPath' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'preserveColors: true' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'readonly property string smallIconSource: root.image.length > 0' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'implicitWidth: 416' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'sourceSize.width: smallIconSlot.width \* Screen.devicePixelRatio \* 4' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'property bool showActions: defaultActionText !== ""' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'radius: 0' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'readonly property int actionGroupWidth' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'x: Math.max(0, (root.actionContentWidth - width) / 2)' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'onWidthChanged: forceLayout()' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'objectName: "notificationActionFlow"' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'objectName: "notificationActionButton"' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'primary: false' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'border.width: 0' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'width: Theme.scaleGeometry(64)' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'centerLabel: true' "$plugin_root/ui/NotificationToast.qml" &&
   ! grep -q 'timestamp: activeDelegate.timestamp' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'timestampLabel: Logic.timestampLabel(activeDelegate.timestamp' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'timestampLabel: Logic.timestampLabel(popupSlot.timestamp' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'objectName: "notificationSourceApp"' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'objectName: "notificationTimestamp"' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'objectName: "notificationSourceIcon"' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'objectName: "notificationSummary"' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'objectName: "notificationBody"' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'horizontalAlignment: Text.AlignHCenter' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'implicitHeight: toastCard.implicitHeight' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'onActivated: root.service.invokeDefault' "$plugin_root/ui/NotificationCenterPanel.qml"; then
    pass "The Inbox uses the shared notification card with centered wrapped text"
else
    fail "Notification center still has a divergent or dead row presentation"
fi

if grep -q 'property bool showCopy: true' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'signal copyRequested()' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'readonly property bool copyRevealed' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'root.hovered || root.focus || copyButton.focus' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'visible: root.showCopy && root.copyRevealed' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'activeFocusOnTab: true' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'objectName: "notificationCopyAction"' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'icon: "edit-copy"' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'onTriggered: root.copyRequested()' "$plugin_root/ui/NotificationToast.qml" &&
   ! grep -q 'label: "Copy"' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'activeFocusOnTab: true' "$ROOT/ui/AureliaIconButton.qml" &&
   grep -q 'Keys.onPressed' "$ROOT/ui/AureliaIconButton.qml" &&
   grep -q 'function copyToClipboard' "$plugin_root/Service.qml" &&
   grep -q 'function copyNotificationAt' "$plugin_root/Service.qml" &&
   grep -q 'property string lastCopiedText' "$plugin_root/Service.qml" &&
   grep -q 'Logic.copyText' "$plugin_root/Service.qml" &&
   grep -q 'wl-copy' "$plugin_root/Service.qml" &&
   grep -q 'Quickshell.execDetached' "$plugin_root/Service.qml" &&
   grep -q 'function copyText' "$plugin_root/NotificationLogic.js" &&
   grep -q 'onCopyRequested: root.notificationService.copyNotificationAt' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'onCopyRequested: root.service.copyNotificationAt' "$plugin_root/ui/NotificationCenterPanel.qml"; then
    pass "Every notification card offers a Copy action routed through the service clipboard path"
else
    fail "Notification card Copy action or clipboard mutation owner is incomplete"
fi

if ! grep -q 'historyModel' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   ! grep -q 'History' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   ! grep -q 'clearHistory' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   ! grep -q 'StackLayout' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   ! grep -q 'historyModel' "$plugin_root/Service.qml" &&
   ! grep -q 'historyDir' "$plugin_root/Service.qml" &&
   ! grep -q 'recordHistory' "$plugin_root/Service.qml" &&
   ! grep -q 'clearHistory' "$plugin_root/Service.qml" &&
   ! grep -q 'invokeHistory' "$plugin_root/Service.qml" &&
   ! grep -q 'showHistory' "$plugin_root/Service.qml" &&
   grep -q 'currentViewEmpty' "$plugin_root/ui/NotificationCenterPanel.qml"; then
    pass "Notification center is Inbox-only with no History tab or history model"
else
    fail "Notification center still exposes a History tab or history model"
fi

if grep -q 'function restorePopups' "$plugin_root/Service.qml" &&
   ! grep -q 'insertPopupSnapshot(restored)' "$plugin_root/Service.qml" &&
   grep -q 'activeNotificationsModel.append(restored)' "$plugin_root/Service.qml" &&
   grep -q 'restoredPopups\[Logic.popupFileName(restored)\] = true' "$plugin_root/Service.qml"; then
    pass "Shell reload restores the Inbox without replaying rows as transient popups"
else
    fail "Inbox restore still re-inserts restored rows into the popup toast model"
fi

if grep -q 'property bool doNotDisturb' "$plugin_root/Service.qml" &&
   grep -q 'XDG_STATE_HOME' "$plugin_root/Service.qml" &&
   grep -q 'readonly property string popupStateDir' "$plugin_root/Service.qml" &&
   grep -q 'readonly property string imagesDir' "$plugin_root/Service.qml" &&
   grep -q 'function persistPopupFile' "$plugin_root/Service.qml" &&
   grep -q 'function applyDurablePopup' "$plugin_root/Service.qml" &&
   grep -q 'service.applyDurablePopup(snapshot, persistable.entry)' "$plugin_root/Service.qml" &&
   grep -q 'updateModelRows(activeNotificationsModel, durableEntry' "$plugin_root/Service.qml" &&
   grep -q 'updateModelRows(popupNotificationsModel, durableEntry' "$plugin_root/Service.qml" &&
   grep -q 'function deletePopupFileFor' "$plugin_root/Service.qml" &&
   grep -q 'function restorePopups' "$plugin_root/Service.qml" &&
   grep -q 'function isManualInboxEntry' "$plugin_root/Service.qml" &&
   grep -q 'var manualInbox = isManualInboxEntry(entry)' "$plugin_root/Service.qml" &&
   grep -q 'function sweepOrphanImages' "$plugin_root/Service.qml" &&
   grep -q 'notificationBusRetryTimer.restart' "$plugin_root/Service.qml" &&
   grep -q 'property OptionalFileStore settingsFile: OptionalFileStore' "$plugin_root/Service.qml" &&
   grep -q 'import "../../services"' "$plugin_root/Service.qml" &&
   grep -q 'writable: true' "$plugin_root/Service.qml" &&
   ! grep -q 'property FileView settingsFile' "$plugin_root/Service.qml" &&
   grep -q 'function toggleDnd' "$plugin_root/Service.qml" &&
   grep -q 'function releaseCenterPopout' "$plugin_root/Service.qml" &&
   grep -q 'onCenterOpenChanged' "$plugin_root/Service.qml" &&
   grep -q 'function dismissAll' "$plugin_root/Service.qml" &&
   grep -q 'function publishScreenshot' "$plugin_root/Service.qml" &&
   grep -q 'property var liveSnapshots' "$plugin_root/Service.qml" &&
   grep -q 'function identityKey' "$plugin_root/Service.qml" &&
   grep -q 'Logic.identityKey' "$plugin_root/Service.qml" &&
   grep -q 'function liveKeyForOriginalId' "$plugin_root/Service.qml" &&
   grep -q 'function removeLiveRowByKey' "$plugin_root/Service.qml" &&
   ! grep -q 'liveSnapshots\[originalId\]' "$plugin_root/Service.qml" &&
   grep -q 'property alias popupModel' "$plugin_root/Service.qml" &&
   grep -q 'ListModel { id: popupNotificationsModel }' "$plugin_root/Service.qml" &&
   grep -q 'function removePopupByIdentity' "$plugin_root/Service.qml" &&
   grep -q 'function insertPopupSnapshot' "$plugin_root/Service.qml" &&
   grep -q 'popup.expired inbox_retained' "$plugin_root/Service.qml" &&
   grep -q 'function flushState' "$plugin_root/Service.qml" &&
   grep -q 'popup.delete:' "$plugin_root/Service.qml" &&
   grep -q 'popup.expire index=' "$plugin_root/Service.qml" &&
   grep -q 'function removeByOriginalId' "$plugin_root/Service.qml" &&
   grep -q 'function removeByIdentity' "$plugin_root/Service.qml" &&
   grep -q 'function activeIndexForIdentity' "$plugin_root/Service.qml" &&
   grep -q 'function hasUsableIdentity' "$plugin_root/Service.qml" &&
   grep -q 'popup.identity_recovered' "$plugin_root/Service.qml" &&
   ! grep -q 'removeAt(indexHint, reason, originalId, timestamp)' "$plugin_root/Service.qml" &&
   ! grep -q 'property Timer stateSaveTimer' "$plugin_root/Service.qml" &&
   grep -q 'notificationBusProbe' "$plugin_root/Service.qml" &&
   grep -q 'busctl' "$plugin_root/Service.qml" &&
   grep -q 'busOwnerPid' "$plugin_root/Service.qml" &&
   grep -q 'notificationBusHealthTimer' "$plugin_root/Service.qml" &&
   grep -q 'active: !service.testMode' "$plugin_root/Service.qml" &&
   grep -q 'file_job_retry' "$plugin_root/Service.qml" &&
   grep -q 'file_job_failed' "$plugin_root/Service.qml" &&
   grep -q 'server.bus_available' "$plugin_root/Service.qml" &&
   grep -q 'server.bus_owned external=true' "$plugin_root/Service.qml" &&
   grep -q 'target: "aurelia.notifications"' "$plugin_root/Service.qml"; then
    pass "DND and popup-file persistence have an XDG-state-backed service API with center actions"
else
    fail "Notification DND/popup-file persistence or IPC contract is incomplete"
fi

if grep -q 'property bool testMode' "$plugin_root/Service.qml" &&
   grep -q 'model: service.testMode ? \[\] : Quickshell.screens' "$plugin_root/Service.qml" &&
   grep -q 'active: service.centerOpen && !service.testMode' "$plugin_root/Service.qml" &&
   grep -q 'toastSource' "$ROOT/tests/fixtures/notifications/dismissal.qml" &&
   grep -q 'function emitDismissed' "$ROOT/tests/fixtures/notifications/dismissal.qml" &&
   grep -q 'function emitCardDismissed' "$ROOT/tests/fixtures/notifications/dismissal.qml" &&
   grep -q 'popupSourceMode' "$ROOT/tests/fixtures/notifications/dismissal.qml" &&
   grep -q 'dismissPopupAt' "$ROOT/tests/fixtures/notifications/dismissal.qml" &&
   [[ -f "$ROOT/tests/fixtures/notifications/identity-collision.qml" ]] &&
   grep -q 'liveFirst' "$ROOT/tests/fixtures/notifications/identity-collision.qml" &&
   grep -q 'popupMalformedCovered' "$ROOT/tests/fixtures/notifications/identity-collision.qml" &&
   grep -q 'function onDismissed' "$ROOT/tests/fixtures/notifications/dismissal.qml" &&
   grep -q 'service.dismissAt' "$ROOT/tests/fixtures/notifications/dismissal.qml"; then
    pass "[static] notification dismissal has a production-Service fixture boundary without live bus or desktop ownership"
else
    fail "[static] notification dismissal fixture boundary is incomplete"
fi

if grep -q 'aurelia-action' "$plugin_root/NotificationLogic.js" &&
   grep -q 'notify-send' "$plugin_root/NotificationLogic.js" &&
   grep -q 'function styledBody' "$plugin_root/NotificationLogic.js" &&
   grep -q 'function parseExecArgv' "$plugin_root/NotificationLogic.js" &&
   grep -q 'function persistablePopup' "$plugin_root/NotificationLogic.js" &&
   grep -q 'source.indexOf("image://") === 0' "$plugin_root/NotificationLogic.js" &&
   grep -q 'function popupPlacement' "$plugin_root/NotificationLogic.js" &&
   grep -q 'shouldBypassDnd(notification, 2)' "$plugin_root/Service.qml" &&
   grep -q 'durationFor' "$plugin_root/NotificationLogic.js" &&
   grep -q 'isInboxPersistent' "$plugin_root/NotificationLogic.js" &&
   grep -q 'appIcon: String(popupSlot.appIcon || "")' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'image: String(popupSlot.image || "")' "$plugin_root/ui/NotificationPopupSurface.qml" &&
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
   grep -q 'popupWidth: Math.min(416' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'popupHeight: Math.min' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'minPopupHeight: 280' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'maxPopupHeight: 476' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'contentPadding: Theme.spacingSm' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'anchorItemFor("aurelia.notifications")' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'var targetScreen = root.screenModel' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'visible: root.notificationService !== null && root.notificationService.popupModel.count > 0 && root.anchored' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'Math.min(416' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'popupOrigin' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   grep -q 'appIconIsLocal' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'sourcePath: root.appIconIsLocal ? root.appIcon : ""' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'AureliaIconButton' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'currentViewEmpty' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   caught_up_text=$'You\u2019re all caught up' &&
   grep -q "$caught_up_text" "$plugin_root/ui/NotificationCenterPanel.qml" &&
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
   grep -q 'root.anchorWindow.mapFromItem(target, localX, localY)' "$tooltip_qml" &&
   ! grep -q 'root.anchorWindow.contentItem.mapFromItem' "$tooltip_qml" &&
   grep -q 'root.anchorWindow.mapFromItem(root.anchorSlot, 0, 0)' "$ROOT/plugins/aurelia.notifications/ui/NotificationPopupSurface.qml" &&
   ! grep -q 'mapToItem(root.anchorWindow.contentItem' "$ROOT/plugins/aurelia.notifications/ui/NotificationPopupSurface.qml" &&
   grep -q 'AureliaToolTip 1.0 AureliaToolTip.qml' "$ROOT/ui/qmldir" &&
   grep -q 'AureliaToolTip {' "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotBarWidget.qml" &&
   grep -q 'publishScreenshot' "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotBarWidget.qml" &&
   ! grep -Eq '(^|[[:space:]])ToolTip[[:space:]]*\{' "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotBarWidget.qml"; then
    pass "Bar tooltips use a standalone anchored window with full below/above placement"
else
    fail "Shared tooltip placement still relies on a clipped control overlay"
fi

if grep -q 'if (hasKind(manifest, "service")) return "service"' "$ROOT/services/PluginRegistry.qml" &&
   grep -q 'aurelia.notifications' "$ROOT/config/bar-default.json" &&
   grep -q 'aurelia.notifications' "$ROOT/plugins/aurelia.notifications/manifest.json"; then
    pass "Multi-kind notification plugins load their service owner before bar presentation"
else
    fail "Multi-kind plugin selection or default bar registration is incomplete"
fi

if command -v node >/dev/null; then
    if node - "$plugin_root/NotificationLogic.js" "$ROOT/services/SourceUrl.js" <<'NODE_LOGIC'
const logic = require(process.argv[2]);
const sourceUrl = require(process.argv[3]);

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
if (logic.screenshotSnapshot("/tmp/capture.png", 123).image !== sourceUrl.fileUrl("/tmp/capture.png")) process.exit(1);
if (logic.screenshotSnapshot("relative.png", 123) !== null) process.exit(1);
if (logic.parseSettings('{"dnd":true}').dnd !== true) process.exit(1);
if (logic.parseSettings('{bad').ok) process.exit(1);
if (logic.identityKey(1, 100) !== "100|1") process.exit(1);
if (logic.identityKey("1", "100") !== logic.identityKey(1, 100)) process.exit(1);
if (logic.identityKey(1, 0) !== "" || logic.identityKey(undefined, 100) !== "") process.exit(1);
const labelNow = new Date(2026, 2, 10, 12, 0, 0).getTime();
if (logic.timestampLabel(0, labelNow) !== "" || logic.timestampLabel("bad", labelNow) !== "") process.exit(1);
if (logic.timestampLabel(labelNow - 5000, labelNow) !== "Just now") process.exit(1);
if (logic.timestampLabel(labelNow - 5 * 60000, labelNow) !== "5m ago") process.exit(1);
if (logic.timestampLabel(labelNow - 3 * 3600000, labelNow) !== "3h ago") process.exit(1);
if (logic.timestampLabel(new Date(2026, 2, 9, 14, 30, 0).getTime(), labelNow) !== "Yesterday 14:30") process.exit(1);
if (logic.timestampLabel(new Date(2026, 2, 7, 9, 5, 0).getTime(), labelNow) !== "Sat 09:05") process.exit(1);
if (logic.timestampLabel(new Date(2026, 0, 4, 8, 0, 0).getTime(), labelNow) !== "4 Jan 08:00") process.exit(1);
if (logic.timestampLabel(new Date(2025, 11, 24, 18, 45, 0).getTime(), labelNow) !== "24 Dec 2025") process.exit(1);
const repeatedIdentityA = logic.snapshotOf({ id: 1, appName: "ChatGPT", summary: "A" }, 100);
const repeatedIdentityB = logic.snapshotOf({ id: 1, appName: "ChatGPT", summary: "B" }, 200);
if (logic.identityKey(repeatedIdentityA.originalId, repeatedIdentityA.timestamp) ===
    logic.identityKey(repeatedIdentityB.originalId, repeatedIdentityB.timestamp)) process.exit(1);
if (logic.busOwnerPid("NAME=org.freedesktop.Notifications\nPID=1234\n") !== 1234) process.exit(1);
if (logic.busOwnerPid("NAME=org.freedesktop.Notifications\nPID=0\n") !== 0) process.exit(1);
if (logic.styledBody('<b>bold</b>\n<img src="https://example.invalid/x">second', 'Chromium', '') !== '<b>bold</b><br/>second') process.exit(1);
if (logic.copyText({ app: 'Signal', summary: 'New message', body: 'Hello there' }) !== 'Signal\nNew message\nHello there') process.exit(1);
if (logic.copyText({ app: '', summary: 'Only summary', body: '' }) !== 'Only summary') process.exit(1);
if (logic.copyText({ app: 'Chromium', summary: 'S', body: '<img src="https://example.invalid/x">Real body' }) !== 'Chromium\nS\nReal body') process.exit(1);
if (logic.copyText({}) !== '') process.exit(1);
if (JSON.stringify(logic.parseExecArgv('["xdg-open","/tmp/a b"]')) !== '["xdg-open","/tmp/a b"]') process.exit(1);
if (logic.parseExecArgv('["--bad"]') !== null) process.exit(1);
const popup = { id: 7, originalId: 7, timestamp: 100, appIcon: sourceUrl.fileUrl('/tmp/avatar.png'), summary: 'Saved' };
if (logic.popupFileName(popup) !== '100-7.json') process.exit(1);
if (logic.popupFileName({ summary: 'missing identity' }) !== '') process.exit(1);
if (!logic.hasPopupIdentity(popup) || logic.hasPopupIdentity({ summary: 'missing identity' })) process.exit(1);
if (logic.popupFileName({ id: 7, originalId: 7, timestamp: 0, summary: 'zero timestamp' }) !== '') process.exit(1);
if (logic.parsePopupFiles(JSON.stringify({ id: 7, originalId: 7, timestamp: 0, summary: 'invalid' }), 1).length !== 0) process.exit(1);
const persistable = logic.persistablePopup(popup, '/tmp/state/images/');
if (persistable.copies.length !== 1 || persistable.entry.appIcon !== sourceUrl.fileUrl('/tmp/state/images/100-7-appIcon')) process.exit(1);
// Quickshell provider URLs with an embedded absolute path must be copied like
// appIcon instead of being dropped; themed provider names must stay untouched.
const imageIconPopup = { id: 9, originalId: 9, timestamp: 200, appIcon: 'image://icon//tmp/org.chromium.Chromium.scoped_dir.abc/logo.png', image: 'image://icon//tmp/org.chromium.Chromium.scoped_dir.abc/icon.png', summary: 'Chromium' };
const imagePersistable = logic.persistablePopup(imageIconPopup, '/tmp/state/images/');
if (imagePersistable.copies.length !== 2) process.exit(1);
if (imagePersistable.entry.appIcon !== sourceUrl.fileUrl('/tmp/state/images/200-9-appIcon')) process.exit(1);
if (imagePersistable.entry.image !== sourceUrl.fileUrl('/tmp/state/images/200-9-image')) process.exit(1);
const themedIcon = logic.persistablePopup({ id: 10, originalId: 10, timestamp: 201, appIcon: 'image://icon/application-x-executable' }, '/tmp/state/images/');
if (themedIcon.copies.length !== 0 || themedIcon.entry.appIcon !== '') process.exit(1);
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
const normalizedEntry = logic.popupEntry({
    id: 8,
    originalId: 8,
    timestamp: 777,
    summary: "Saved",
    body: "A notification",
    actions: [{ identifier: "default", text: "Open" }, { identifier: "reply", text: "Reply" }],
    defaultActionText: "Open"
}, 1);
if (normalizedEntry.defaultActionText !== "Open" || normalizedEntry.actions.length !== 1 || normalizedEntry.actions[0].identifier !== "reply") process.exit(1);
const chatRoute = logic.workspaceRouteData({ desktopEntry: "chatgpt.desktop", appName: "ChatGPT" });
if (!chatRoute.enabled || logic.workspaceRouteScore(chatRoute, { appId: "chatgpt", className: "chatgpt", activated: false }) <= 0) process.exit(1);
const nativeChatScore = logic.workspaceRouteScore(chatRoute, { appId: "chatgpt", className: "Chatgpt", title: "ChatGPT", activated: false });
const browserChatScore = logic.workspaceRouteScore(chatRoute, { appId: "chatgpt", className: "chatgpt", title: "(1) Home / X - Chromium", initialTitle: "New Tab - Chromium", activated: true });
if (nativeChatScore <= browserChatScore) process.exit(1);
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
    skip "notification logic runtime check (node unavailable)"
fi

if command -v node >/dev/null; then
    if node - "$plugin_root/NotificationLogic.js" "$plugin_root/NotificationFileLogic.js" <<'NODE_FILES'
const fs = require("fs");
const path = require("path");
const childProcess = require("child_process");
const logic = require(process.argv[2]);
const fileLogic = require(process.argv[3]);
const root = fs.mkdtempSync("/tmp/aurelia-notification-files-");
const live = path.join(root, "live");
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
    // An orphan image not referenced by any live popup is swept.
    fs.writeFileSync(path.join(images, "999-9-appIcon"), "orphan");
    run(fileLogic.sweepImages(`${live}/`, `${images}/`));
    if (fs.existsSync(path.join(images, "999-9-appIcon"))) throw new Error("orphan image was not swept");
    run(fileLogic.deletePopup(`${live}/`, `${images}/`, "100-1.json"));
    if (fs.existsSync(path.join(live, "100-1.json"))) throw new Error("popup delete failed");
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
    skip "notification file operation check (node unavailable)"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] production notification dismissal fixture (qs or timeout unavailable)"
    return 0
fi

dismissal_root="$(mktemp -d)"
trap 'rm -rf -- "$dismissal_root"  || true' RETURN
mkdir -p -- "$dismissal_root/runtime" "$dismissal_root/state" \
    "$dismissal_root/config" "$dismissal_root/cache"
dismissal_result="$dismissal_root/result.json"
: >"$dismissal_result"
mkdir -p -- "$dismissal_root/state/aurelia"
: >"$dismissal_root/state/aurelia/notifications.json"
dismissal_log="$dismissal_root/runtime.log"
dismissal_status=0
AURELIA_NOTIFICATION_DISMISSAL_RESULT="$dismissal_result" \
AURELIA_NOTIFICATION_SERVICE_SOURCE="file://$plugin_root/Service.qml" \
AURELIA_NOTIFICATION_TOAST_SOURCE="file://$plugin_root/ui/NotificationToast.qml" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$dismissal_root/runtime" \
XDG_STATE_HOME="$dismissal_root/state" \
XDG_CONFIG_HOME="$dismissal_root/config" \
XDG_CACHE_HOME="$dismissal_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/notifications/dismissal.qml" --no-color \
    >"$dismissal_log" 2>&1 || dismissal_status=$?

dismissal_completed=0
if [[ "$dismissal_status" -eq 0 ]]; then
    dismissal_completed=1
elif [[ "$dismissal_status" -eq 124 && -s "$dismissal_result" ]] &&
     grep -Fq 'Signal QQmlEngine::quit() emitted' "$dismissal_log"; then
    dismissal_completed=1
fi
if [[ "$dismissal_completed" -eq 1 ]] && [[ -s "$dismissal_result" ]] &&
   runtime_log_is_environment_only "$dismissal_log" &&
   ! grep -Eq 'invalid_identity|TypeError|ReferenceError|Binding loop detected|Cannot assign|Loader\.Error|file_job_(retry|failed)' "$dismissal_log" &&
   jq -e '.serviceLoaded == true and .activeCount == 0 and .popupCount == 0 and
          .popupFiles == 0 and
          .dismissedIds == [42, 41, 43] and
          .malformedFallback == true and .mismatchedIdentityPreserved == true and
          .pointerPathCovered == true and .popupMalformedIdentityCovered == true and
          .firstDismissCalls == 1 and
          .secondDismissCalls == 1 and .thirdDismissCalls == 1' \
       "$dismissal_result" >/dev/null; then
    pass "[isolated-runtime] production Service and real Toast dismissal wiring preserve identity across index churn and re-entrant sender close"
else
    details="$(tail -n 48 "$dismissal_log"  || true)"
    if [[ -s "$dismissal_result" ]]; then details="$details result=$(tr '\n' ' ' <"$dismissal_result")"; fi
    fail "[isolated-runtime] notification cross-button dismissal fixture failed (status=$dismissal_status): $details"
fi

collision_root="$(mktemp -d)"
trap 'rm -rf -- "$collision_root"  || true' RETURN
mkdir -p -- "$collision_root/runtime" "$collision_root/state" \
    "$collision_root/config" "$collision_root/cache"
collision_result="$collision_root/result.json"
: >"$collision_result"
mkdir -p -- "$collision_root/state/aurelia"
: >"$collision_root/state/aurelia/notifications.json"
collision_log="$collision_root/runtime.log"
collision_status=0
AURELIA_NOTIFICATION_COLLISION_RESULT="$collision_result" \
AURELIA_NOTIFICATION_COLLISION_SERVICE_SOURCE="file://$plugin_root/Service.qml" \
AURELIA_NOTIFICATION_COLLISION_TOAST_SOURCE="file://$plugin_root/ui/NotificationToast.qml" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$collision_root/runtime" \
XDG_STATE_HOME="$collision_root/state" \
XDG_CONFIG_HOME="$collision_root/config" \
XDG_CACHE_HOME="$collision_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/notifications/identity-collision.qml" --no-color \
    >"$collision_log" 2>&1 || collision_status=$?

collision_completed=0
if [[ "$collision_status" -eq 0 ]]; then
    collision_completed=1
elif [[ "$collision_status" -eq 124 && -s "$collision_result" ]] &&
     grep -Fq 'Signal QQmlEngine::quit() emitted' "$collision_log"; then
    collision_completed=1
fi
if [[ "$collision_completed" -eq 1 ]] && [[ -s "$collision_result" ]] &&
   runtime_log_is_environment_only "$collision_log" &&
   ! grep -Eq 'invalid_identity|TypeError|ReferenceError|Binding loop detected|Cannot assign|Loader\.Error|file_job_(retry|failed)' "$collision_log" &&
   jq -e '.loaded == true and .phase == 4 and .activeCount == 0 and
          .popupCount == 0 and .popupFiles == 0 and
          .popupMalformedCovered == true and
          .secondPopupMalformedCovered == true and
          .replacementPreservedRestored == true and
          .firstDismissCalls == 1 and .secondDismissCalls == 1' \
       "$collision_result" >/dev/null; then
    pass "[isolated-runtime] repeated numeric notification IDs retain composite identity across restored rows, replacement, and popup dismissal"
else
    details="$(tail -n 48 "$collision_log"  || true)"
    if [[ -s "$collision_result" ]]; then details="$details result=$(tr '\n' ' ' <"$collision_result")"; fi
    fail "[isolated-runtime] repeated notification identity collision fixture failed (status=$collision_status): $details"
fi

# Shell reload restores persisted Inbox rows without replaying them as toasts.
restore_root="$(mktemp -d)"
mkdir -p -- "$restore_root/runtime" "$restore_root/state" \
    "$restore_root/config" "$restore_root/cache"
restore_result="$restore_root/result.json"
: >"$restore_result"
mkdir -p -- "$restore_root/state/aurelia"
: >"$restore_root/state/aurelia/notifications.json"
restore_log="$restore_root/runtime.log"
restore_status=0
AURELIA_NOTIFICATION_RESTORE_RESULT="$restore_result" \
AURELIA_NOTIFICATION_RESTORE_SERVICE_SOURCE="file://$plugin_root/Service.qml" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$restore_root/runtime" \
XDG_STATE_HOME="$restore_root/state" \
XDG_CONFIG_HOME="$restore_root/config" \
XDG_CACHE_HOME="$restore_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/notifications/restore-silent.qml" --no-color \
    >"$restore_log" 2>&1 || restore_status=$?

restore_completed=0
if [[ "$restore_status" -eq 0 ]]; then
    restore_completed=1
elif [[ "$restore_status" -eq 124 && -s "$restore_result" ]] &&
     grep -Fq 'Signal QQmlEngine::quit() emitted' "$restore_log"; then
    restore_completed=1
fi
if [[ "$restore_completed" -eq 1 ]] && [[ -s "$restore_result" ]] &&
   runtime_log_is_environment_only "$restore_log" &&
   ! grep -Eq 'invalid_identity|TypeError|ReferenceError|Binding loop detected|Cannot assign|Loader\.Error|file_job_(retry|failed)' "$restore_log" &&
   jq -e '.serviceLoaded == true and .restoredActive == 2 and .restoredPopup == 0 and
          .restoredMarked == true and
          .restoredSummaries == ["Restored Two", "Restored One"] and
          .afterNewActive == 3 and .afterNewPopup == 1' \
       "$restore_result" >/dev/null; then
    pass "[isolated-runtime] shell reload restores the Inbox silently and only genuinely new notifications toast"
else
    details="$(tail -n 48 "$restore_log" || true)"
    if [[ -s "$restore_result" ]]; then details="$details result=$(tr '\n' ' ' <"$restore_result")"; fi
    fail "[isolated-runtime] silent Inbox restore fixture failed (status=$restore_status): $details"
fi
rm -rf -- "$restore_root"

# The Copy action projects app/summary/body through the service clipboard owner
# for the transient toast and the Inbox.
copy_root="$(mktemp -d)"
mkdir -p -- "$copy_root/runtime" "$copy_root/state" \
    "$copy_root/config" "$copy_root/cache"
copy_result="$copy_root/result.json"
: >"$copy_result"
mkdir -p -- "$copy_root/state/aurelia"
: >"$copy_root/state/aurelia/notifications.json"
copy_log="$copy_root/runtime.log"
copy_status=0
AURELIA_NOTIFICATION_COPY_RESULT="$copy_result" \
AURELIA_NOTIFICATION_COPY_SERVICE_SOURCE="file://$plugin_root/Service.qml" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$copy_root/runtime" \
XDG_STATE_HOME="$copy_root/state" \
XDG_CONFIG_HOME="$copy_root/config" \
XDG_CACHE_HOME="$copy_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/notifications/copy-action.qml" --no-color \
    >"$copy_log" 2>&1 || copy_status=$?

copy_completed=0
if [[ "$copy_status" -eq 0 ]]; then
    copy_completed=1
elif [[ "$copy_status" -eq 124 && -s "$copy_result" ]] &&
     grep -Fq 'Signal QQmlEngine::quit() emitted' "$copy_log"; then
    copy_completed=1
fi
if [[ "$copy_completed" -eq 1 ]] && [[ -s "$copy_result" ]] &&
   runtime_log_is_environment_only "$copy_log" &&
   ! grep -Eq 'invalid_identity|TypeError|ReferenceError|Binding loop detected|Cannot assign|Loader\.Error|file_job_(retry|failed)' "$copy_log" &&
   jq -e '.serviceLoaded == true and
          .activeCopy == "Signal\nNew message\nHello there" and .activeCopied == true and
          .popupCopy == "Signal\nNew message\nHello there" and .popupCopied == true and
          .activeResult == "ok" and .popupResult == "ok" and
          .missingResult == "none" and .lastCopiedPreserved == true' \
       "$copy_result" >/dev/null; then
    pass "[isolated-runtime] notification Copy projects app/summary/body through the service clipboard owner in the toast and Inbox"
else
    details="$(tail -n 48 "$copy_log" || true)"
    if [[ -s "$copy_result" ]]; then details="$details result=$(tr '\n' ' ' <"$copy_result")"; fi
    fail "[isolated-runtime] notification Copy fixture failed (status=$copy_status): $details"
fi
rm -rf -- "$copy_root"

# The durable app icon must reach the live models, not just the on-disk JSON.
# Chromium hands the card an ephemeral image://icon//tmp/... path and then
# deletes it, so the copied path has to be pushed back into the UI state.
durable_icon_root="$(mktemp -d)"
mkdir -p -- "$durable_icon_root/runtime" "$durable_icon_root/state" \
    "$durable_icon_root/config" "$durable_icon_root/cache"
durable_icon_source="$durable_icon_root/ephemeral-logo.png"
printf 'ephemeral-image-bytes' > "$durable_icon_source"
durable_icon_result="$durable_icon_root/result.json"
: >"$durable_icon_result"
durable_icon_log="$durable_icon_root/runtime.log"
durable_icon_status=0
AURELIA_NOTIFICATION_DURABLE_ICON_RESULT="$durable_icon_result" \
AURELIA_NOTIFICATION_DURABLE_ICON_SERVICE_SOURCE="file://$plugin_root/Service.qml" \
AURELIA_NOTIFICATION_DURABLE_ICON_SOURCE="$durable_icon_source" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$durable_icon_root/runtime" \
XDG_STATE_HOME="$durable_icon_root/state" \
XDG_CONFIG_HOME="$durable_icon_root/config" \
XDG_CACHE_HOME="$durable_icon_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/notifications/durable-icon.qml" --no-color \
    >"$durable_icon_log" 2>&1 || durable_icon_status=$?

durable_icon_completed=0
if [[ "$durable_icon_status" -eq 0 ]]; then
    durable_icon_completed=1
elif [[ "$durable_icon_status" -eq 124 && -s "$durable_icon_result" ]] &&
     grep -Fq 'Signal QQmlEngine::quit() emitted' "$durable_icon_log"; then
    durable_icon_completed=1
fi
durable_icon_images="$durable_icon_root/state/aurelia/notifications/images"
durable_icon_copy=""
if [[ -d "$durable_icon_images" ]]; then
    durable_icon_copy="$(find "$durable_icon_images" -maxdepth 1 -type f -name '*-appIcon' -print -quit)"
fi
if [[ "$durable_icon_completed" -eq 1 ]] && [[ -s "$durable_icon_result" ]] &&
   [[ -n "$durable_icon_copy" ]] &&
   runtime_log_is_environment_only "$durable_icon_log" &&
   ! grep -Eq 'TypeError|ReferenceError|Binding loop detected|Cannot assign|Loader\.Error|file_job_(retry|failed)' "$durable_icon_log" &&
   jq -e '.serviceLoaded == true and
          .appIconRetained == true and .imageRetained == true and
          .popupRetained == true and .liveRetained == true and
          .diskMatchesModel == true' \
       "$durable_icon_result" >/dev/null; then
    pass "[isolated-runtime] ephemeral image:// app icons propagate the durable copied path into the live models, snapshots, and on-disk JSON"
else
    details="$(tail -n 48 "$durable_icon_log" || true)"
    if [[ -s "$durable_icon_result" ]]; then details="$details result=$(tr '\n' ' ' <"$durable_icon_result")"; fi
    fail "[isolated-runtime] durable notification icon fixture failed (status=$durable_icon_status): $details"
fi
rm -rf -- "$durable_icon_root"

# Herdr (the terminal workspace manager pi runs inside) sends a raw
# "<label> · <number> · <count>" body with no action. The logic must render
# that in words and synthesize a jump-back-to-the-chat action.
if command -v node >/dev/null; then
    herdr_logic_test="$(mktemp --suffix=.js)"
    sed '/^\.pragma library/d' "$plugin_root/NotificationLogic.js" >"$herdr_logic_test"
    cat >>"$herdr_logic_test" <<'HERDR_EXPORTS'
module.exports = { herdrRoute, herdrBody, styledBody, snapshotOf };
HERDR_EXPORTS
    if node -e '
const L = require(process.argv[1]);
const n = { id: 7, appName: "Herdr", summary: "pi finished", body: "sutradhar \u00b7 2 \u00b7 3", urgency: 1 };
const snap = L.snapshotOf(n, 1700000000000);
const ok =
    L.herdrRoute(n) && L.herdrRoute(n).label === "sutradhar" && L.herdrRoute(n).number === 2 &&
    L.herdrBody("sutradhar \u00b7 2 \u00b7 3", "Herdr") === "sutradhar \u00b7 workspace 2" &&
    snap.defaultActionText === "Open" &&
    (function () {
        var argv = JSON.parse(snap.execArgv);
        var joined = argv.join(" ");
        return argv[0] === "bash" && joined.indexOf("workstation-herdr-focus") >= 0 && joined.indexOf(" 2") >= 0;
    })() &&
    L.herdrRoute({ appName: "foot", body: "a \u00b7 1 \u00b7 1" }) === null &&
    L.snapshotOf({ appName: "Herdr", body: "x \u00b7 1", actions: [{ identifier: "default", text: "Reply" }] }, 1).defaultActionText === "Reply";
process.exit(ok ? 0 : 1);
' "$herdr_logic_test" >/dev/null; then
        pass "[unit] Herdr notifications render a clear body and offer a chat jump action"
    else
        fail "[unit] Herdr notification projection failed"
    fi
    rm -f -- "$herdr_logic_test"
else
    skip "[unit] Herdr notification projection (node unavailable)"
fi

# The shared card must render the source application name, source application
# icon, and computed timestamp label. Static property wiring is not enough: an
# isolated runtime fixture loads the real NotificationToast and records the
# Text/Image values present in the rendered tree, then clears the fields and
# proves they disappear.
render_fixture="$ROOT/tests/fixtures/notifications/render.qml"
render_icon="$ROOT/config/branding/aurelia-mark.png"
if [[ ! -f "$render_fixture" || ! -f "$render_icon" ]]; then
    fail "[static] notification card render fixture or source icon is missing"
elif [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] notification card render fixture (qs or timeout unavailable)"
else
    render_root="$(mktemp -d)"
    trap 'rm -rf -- "$render_root"  || true' RETURN
    mkdir -p -- "$render_root/runtime" "$render_root/state" \
        "$render_root/config" "$render_root/cache"
    render_result="$render_root/result.json"
    : >"$render_result"
    render_log="$render_root/runtime.log"
    render_status=0
    AURELIA_NOTIFICATION_RENDER_RESULT="$render_result" \
    AURELIA_NOTIFICATION_RENDER_TOAST_SOURCE="file://$plugin_root/ui/NotificationToast.qml" \
    AURELIA_NOTIFICATION_RENDER_ICON="file://$render_icon" \
    QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$render_root/runtime" \
    XDG_STATE_HOME="$render_root/state" \
    XDG_CONFIG_HOME="$render_root/config" \
    XDG_CACHE_HOME="$render_root/cache" \
        /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
        --path "$render_fixture" --no-color >"$render_log" 2>&1 || render_status=$?

    render_completed=0
    if [[ "$render_status" -eq 0 ]]; then
        render_completed=1
    elif [[ "$render_status" -eq 124 && -s "$render_result" ]] &&
         grep -Fq 'Signal QQmlEngine::quit() emitted' "$render_log"; then
        render_completed=1
    fi
    if [[ "$render_completed" -eq 1 ]] && [[ -s "$render_result" ]] &&
       runtime_log_is_environment_only "$render_log" &&
       ! grep -Eq 'TypeError|ReferenceError|Binding loop detected|Cannot assign|Loader\.Error' "$render_log" &&
       jq -e --arg icon "file://$render_icon" --arg app "Aurelia Render Fixture With An Extremely Long Application Name" '
            .loaded == true and
            .iconReady == true and
            .appText == $app and
            .appVisible == true and
            .appElideRight == true and
            .appMaxLines == 1 and
            .timestampText == "Yesterday 14:30" and
            .timestampVisible == true and
            .iconSource == $icon and
            .iconVisible == true and
            .copyVisibleDefault == false and
            .copyVisibleWhenFocused == true and
            .copyHiddenAfterBlur == true and
            .actionOneRowHeight == 28 and
            .actionWrappedHeight > .actionOneRowHeight and
            .actionFlowWidth > 0 and
            .copyIcon == "edit-copy" and
            .copyIsIconControl == true and
            .copySameRowAsTitle == true and
            .copyAfterTitleInRow == true and
            .summaryCentered == true and
            .bodyCentered == true and
            .fallbackSourcePath == $icon and
            .fallbackName == "" and
            .emptyAppHidden == true and
            .emptyTimestampHidden == true
       ' "$render_result" >/dev/null; then
        pass "[isolated-runtime] shared notification card centers wrapped text and keeps an icon Copy control with the real app-icon source"
    else
        details="$(tail -n 48 "$render_log" || true)"
        if [[ -s "$render_result" ]]; then details="$details result=$(tr '\n' ' ' <"$render_result")"; fi
        fail "[isolated-runtime] notification card render fixture failed (status=$render_status): $details"
    fi
fi
