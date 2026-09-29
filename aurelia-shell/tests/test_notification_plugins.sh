#!/usr/bin/env bash

# Contract tests for Aurelia's resident notification service, center, DND
# policy, and reusable bar tooltip. These tests are static, pure-JavaScript,
# and isolated-file-operation checks; they never mutate the live notification
# bus or desktop.

set -Eeuo pipefail

plugin_root="$ROOT/plugins/aurelia.notifications"
tooltip_qml="$ROOT/ui/AureliaToolTip.qml"

# Deterministic stand-in for the production origin helper used by the isolated
# action-origin fixtures. It echoes a caller-supplied capture payload, records
# each navigate invocation to a sentinel file, and prints a caller-supplied
# navigate outcome. All behavior is environment-controlled so no fixture ever
# reaches the live session bus, compositor, or notification socket.
write_notification_origin_stub() {
    local target="$1"
    cat >"$target" <<'STUB'
#!/usr/bin/env bash
set -Eeuo pipefail
mode="${1:-}"
case "$mode" in
    capture)
        body=""
        previous=""
        for argument in "$@"; do
            if [[ "$previous" == "--body" ]]; then body="$argument"; fi
            previous="$argument"
        done
        if [[ "$body" == *"capture-slow"* ]]; then
            /usr/bin/sleep "${AURELIA_STUB_CAPTURE_SLEEP:-5}"
        fi
        if [[ "$body" == *"capture-null"* ]]; then
            printf 'null\n'
            exit 0
        fi
        if [[ "$body" == *"routed-capture"* ]]; then
            printf '%s\n' "${AURELIA_STUB_CAPTURE_ROUTED:-$AURELIA_STUB_CAPTURE}"
            exit 0
        fi
        printf '%s\n' "${AURELIA_STUB_CAPTURE:-null}"
        exit "${AURELIA_STUB_CAPTURE_EXIT:-0}"
        ;;
    navigate)
        if [[ -n "${AURELIA_STUB_NAVIGATE_SENTINEL:-}" ]]; then
            printf '%s\n' "$*" >>"$AURELIA_STUB_NAVIGATE_SENTINEL"
        fi
        if [[ "$*" == *'"notifyId":503'* ]]; then
            printf '%s\n' '{"action":"navigate","outcome":"routed","confidence":"identity","reason":"stub routed"}'
            exit 0
        fi
        printf '%s\n' "${AURELIA_STUB_NAVIGATE:-{\"action\":\"navigate\",\"outcome\":\"focused\",\"confidence\":\"exact\",\"reason\":\"stub focused\"}}"
        exit "${AURELIA_STUB_NAVIGATE_EXIT:-0}"
        ;;
    *)
        exit 2
        ;;
esac
STUB
    chmod +x "$target"
}

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
   grep -q 'AppIconResolver.themeSource' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'preserveColors: true' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'readonly property string smallIconSource: root.iconSource(root.smallIconValue)' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'AppIconResolver.isSymbolicName(root.smallIconValue)' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'objectName: "notificationSymbolicIcon"' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'implicitWidth: 416' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'sourceSize.width: smallIconSlot.width \* Screen.devicePixelRatio \* 4' "$plugin_root/ui/NotificationToast.qml" &&
   grep -Fq 'property bool showActions: defaultActionText !== "" || actionItemsCount > 0' "$plugin_root/ui/NotificationToast.qml" &&
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
   grep -q 'readonly property int actionItemsCount' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'typeof value.count === "number"' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'Layout.preferredHeight: visible ? actionFlow.implicitHeight : 0' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'horizontalAlignment: Text.AlignLeft' "$plugin_root/ui/NotificationToast.qml" &&
   ! grep -q 'horizontalAlignment: Text.AlignHCenter' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'implicitHeight: toastCard.implicitHeight' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'onActivated: root.service.invokeDefault' "$plugin_root/ui/NotificationCenterPanel.qml"; then
    pass "The Inbox uses the shared notification card with left-aligned wrapped text"
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
   grep -Fq 'if (roles[r] === "actions") model.set(i, { actions: updated.actions || [] })' "$plugin_root/Service.qml" &&
   grep -Fq 'else model.setProperty(i, roles[r], updated[roles[r]])' "$plugin_root/Service.qml" &&
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
   grep -q 'function iconResolutionInput' "$plugin_root/NotificationLogic.js" &&
   grep -q 'DEFAULT_ICON_NAME = "application-x-executable"' "$plugin_root/NotificationLogic.js" &&
   ! grep -q 'output\[role\] = ""' "$plugin_root/NotificationLogic.js" &&
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
   grep -q 'workspace.route_unavailable' "$plugin_root/Service.qml" &&
   grep -q 'function invokeDurableAction' "$plugin_root/Service.qml" &&
   grep -q 'return service.invokeDurableAction' "$plugin_root/Service.qml" &&
   ! grep -q 'if (!reference || !reference.actions) return "unavailable"' "$plugin_root/Service.qml"; then
    pass "Notification actions route to the matching Hyprland workspace with bounded retry"
else
    fail "Notification workspace routing or bounded fallback is incomplete"
fi

if grep -q 'function captureOrigin' "$plugin_root/Service.qml" &&
   grep -q 'service.captureOrigin(snapshot)' "$plugin_root/Service.qml" &&
   grep -q 'AURELIA_NOTIFICATION_TEST_HELPER' "$plugin_root/Service.qml" &&
   grep -q 'workstation-notification-focus' "$plugin_root/Service.qml" &&
   grep -q 'function navigateToOrigin' "$plugin_root/Service.qml" &&
   grep -q 'function applyCapturedOrigin' "$plugin_root/Service.qml" &&
   grep -q 'function isLiveDefaultAction' "$plugin_root/Service.qml" &&
   grep -q 'commandGuardScript' "$plugin_root/Service.qml" &&
   grep -Fq "exec \"\$cmd\" \"\$@\"" "$plugin_root/Service.qml" &&
   grep -q 'function normalizeOrigin' "$plugin_root/NotificationLogic.js" &&
   grep -q 'function originFieldValue' "$plugin_root/NotificationLogic.js" &&
   grep -q 'function parseOriginOutput' "$plugin_root/NotificationLogic.js" &&
   grep -q 'function parseNavigateOutput' "$plugin_root/NotificationLogic.js" &&
   grep -q 'notificationActionOutcome' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'actionOutcomeMessage' "$plugin_root/ui/NotificationToast.qml" &&
   grep -q 'actionOutcome: String(activeDelegate.actionOutcome' "$plugin_root/ui/NotificationCenterPanel.qml" &&
   grep -q 'actionOutcome: String(popupSlot.actionOutcome' "$plugin_root/ui/NotificationPopupSurface.qml" &&
   ! grep -Fq 'Quickshell.execDetached(guarded)' "$plugin_root/Service.qml"; then
    pass "Notification commands run through a bounded observing guard and origins are captured, persisted, and navigated honestly"
else
    fail "Notification origin capture or guarded command execution is incomplete"
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
   grep -q 'sourcePath: root.appIconIsLocal ? root.smallIconSource : ""' "$plugin_root/ui/NotificationToast.qml" &&
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
   grep -q 'publishScreenshot' "$ROOT/services/ScreenshotService.qml" &&
   ! grep -q 'publishScreenshot' "$ROOT/plugins/aurelia.screenshot/ui/ScreenshotBarWidget.qml" &&
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
    if node - "$plugin_root/NotificationLogic.js" "$ROOT/services/SourceUrl.js" "$ROOT/services/AppIconResolver.js" <<'NODE_LOGIC'
const logic = require(process.argv[2]);
const sourceUrl = require(process.argv[3]);
const resolver = require(process.argv[4]);

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
if (persistable.copies.length !== 0 || persistable.entry.appIcon !== 'application-x-executable') process.exit(1);

// The persistence path consumes the shared AppIconResolver owner. Every probe
// is a deterministic in-memory fake, exactly as the resolver node suite uses.
function resolution(input, opts) {
    const options = opts || {};
    return resolver.resolve(input, {}, {
        fileUsable: p => (options.files || []).indexOf(p) !== -1,
        fileSource: p => sourceUrl.fileUrl(p),
        themeUsable: n => (options.themes || []).indexOf(n) !== -1,
        themeSource: n => 'image://icon/' + n + '?fallback=application-x-executable',
        inlineUsable: s => s !== ''
    });
}
const imagesDir = '/tmp/state/images/';

// The foot fix: a themed image-path name is extracted and RETAINED as a name,
// never silently cleared.
const footResolution = resolution(logic.iconResolutionInput(
    { id: 11, originalId: 11, timestamp: 202, appIcon: '', image: 'image://icon/foot', summary: 'Foot' },
    imagesDir), { themes: ['foot'] });
if (footResolution.kind !== 'theme' || footResolution.name !== 'foot') process.exit(1);
const footPersistable = logic.persistablePopup(
    { id: 11, originalId: 11, timestamp: 202, appIcon: '', image: 'image://icon/foot' },
    imagesDir, footResolution);
if (footPersistable.copies.length !== 0) process.exit(1);
if (footPersistable.entry.appIcon !== 'foot' || footPersistable.entry.image !== '') process.exit(1);

// An embedded Chromium path is copied into our own durable store, and the
// sender's transient scoped directory is never persisted.
const chromiumEntry = { id: 9, originalId: 9, timestamp: 200, appIcon: 'image://icon//tmp/org.chromium.Chromium.scoped_dir.abc/logo.png', image: '', summary: 'Chromium' };
const chromiumResolution = resolution(logic.iconResolutionInput(chromiumEntry, imagesDir),
    { files: ['/tmp/org.chromium.Chromium.scoped_dir.abc/logo.png'] });
const chromiumPersistable = logic.persistablePopup(chromiumEntry, imagesDir, chromiumResolution);
if (chromiumResolution.kind !== 'file') process.exit(1);
if (chromiumPersistable.copies.length !== 1) process.exit(1);
if (chromiumPersistable.copies[0].from !== '/tmp/org.chromium.Chromium.scoped_dir.abc/logo.png') process.exit(1);
if (chromiumPersistable.entry.appIcon !== sourceUrl.fileUrl('/tmp/state/images/200-9-appIcon')) process.exit(1);
if (chromiumPersistable.entry.appIcon.indexOf('/tmp/org.chromium') !== -1) process.exit(1);

// A dangling durable path must fall through to the honest default, never a
// file:// path in the persisted entry.
const danglingEntry = { id: 12, originalId: 12, timestamp: 203, appIcon: 'file://' + '/tmp/does-not-exist.png', image: '' };
const danglingResolution = resolution(logic.iconResolutionInput(danglingEntry, imagesDir), {});
if (danglingResolution.kind !== 'default') process.exit(1);
const danglingPersistable = logic.persistablePopup(danglingEntry, imagesDir, danglingResolution);
if (danglingPersistable.copies.length !== 0) process.exit(1);
if (danglingPersistable.entry.appIcon !== 'application-x-executable') process.exit(1);
if (danglingPersistable.entry.appIcon.indexOf('file://') === 0) process.exit(1);

// An already-durable value from a reload is used as-is and never re-copied.
const reloadEntry = { id: 9, originalId: 9, timestamp: 200, appIcon: sourceUrl.fileUrl('/tmp/state/images/200-9-appIcon'), image: '' };
const reloadResolution = resolution(logic.iconResolutionInput(reloadEntry, imagesDir),
    { files: ['/tmp/state/images/200-9-appIcon'] });
if (reloadResolution.kind !== 'durable') process.exit(1);
const reloadPersistable = logic.persistablePopup(reloadEntry, imagesDir, reloadResolution);
if (reloadPersistable.copies.length !== 0) process.exit(1);
if (reloadPersistable.entry.appIcon !== sourceUrl.fileUrl('/tmp/state/images/200-9-appIcon')) process.exit(1);

// An inline qsimage provider is not byte-copyable; it must fall through to a
// real candidate, never persist the transient provider URL.
const inlineEntry = { id: 13, originalId: 13, timestamp: 204, appIcon: '', image: 'image://qsimage/5/0', desktopEntry: 'foot' };
const inlineResolution = resolution(logic.iconResolutionInput(inlineEntry, imagesDir),
    { themes: ['foot', 'application-x-executable'] });
if (inlineResolution.kind === 'inline') process.exit(1);
const inlinePersistable = logic.persistablePopup(inlineEntry, imagesDir, inlineResolution);
if (inlinePersistable.entry.appIcon.indexOf('image://qsimage/') === 0) process.exit(1);
if (inlinePersistable.entry.appIcon !== 'foot') process.exit(1);

// The Ghostty desktop-entry race: the resolver still resolves a theme name for
// the desktop id even before the asynchronous Quickshell scan has run.
const ghosttyResolution = resolution(
    { appIcon: '', image: '', desktopEntry: 'com.mitchellh.ghostty', appName: 'Ghostty' },
    { themes: ['com.mitchellh.ghostty'] });
if (ghosttyResolution.kind !== 'desktop' || ghosttyResolution.name !== 'com.mitchellh.ghostty') process.exit(1);
if (logic.persistablePopup({ id: 14, originalId: 14, timestamp: 205, desktopEntry: 'com.mitchellh.ghostty' },
    imagesDir, ghosttyResolution).entry.appIcon !== 'com.mitchellh.ghostty') process.exit(1);

// A real content image (a screenshot) wins over a generic app-icon theme name.
const screenshotFile = '/tmp/aurelia-shot.png';
const screenshotResolution = resolution(
    { appIcon: 'camera-photo', image: 'file://' + screenshotFile },
    { themes: ['camera-photo'], files: [screenshotFile] });
if (screenshotResolution.kind !== 'file') process.exit(1);
if (screenshotResolution.source.indexOf(screenshotFile) === -1) process.exit(1);
const screenshotPersistable = logic.persistablePopup(
    { id: 15, originalId: 15, timestamp: 206, appIcon: 'camera-photo', image: 'file://' + screenshotFile },
    imagesDir, screenshotResolution);
if (screenshotPersistable.copies.length !== 1) process.exit(1);
if (screenshotPersistable.entry.appIcon !== sourceUrl.fileUrl('/tmp/state/images/206-15-appIcon')) process.exit(1);

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
    // A resolved icon that shares the notification stem is kept while its popup
    // lives and pruned with the notification.
    const liveIcon = path.join(images, "100-1-appIcon");
    fs.writeFileSync(liveIcon, "live-icon");
    run(fileLogic.sweepImages(`${live}/`, `${images}/`));
    if (!fs.existsSync(liveIcon)) throw new Error("live popup icon was swept");
    run(fileLogic.deletePopup(`${live}/`, `${images}/`, "100-1.json"));
    if (fs.existsSync(path.join(live, "100-1.json"))) throw new Error("popup delete failed");
    if (fs.existsSync(liveIcon)) throw new Error("deleted popup icon was not pruned");
    // A copy source that does not exist must fail the job before the JSON is
    // written, so a dangling durable path can never be recorded.
    const missingSource = path.join(root, "missing-logo.png");
    const missingPersistable = logic.persistablePopup(
        { ...entry(2, 200), appIcon: "file://" + missingSource },
        `${images}/`,
        { kind: "file", source: "file://" + missingSource, name: "", symbolic: false });
    const missingJson = { ...missingPersistable, json: logic.serializePopup(missingPersistable.entry, 1) };
    const missingCommand = fileLogic.persistPopup(missingJson, `${live}/`, `${images}/`, "200-2.json");
    const missingRun = childProcess.spawnSync(missingCommand[0], missingCommand.slice(1), { encoding: "utf8" });
    if (missingRun.status === 0) throw new Error("missing copy source did not fail closed");
    if (fs.existsSync(path.join(live, "200-2.json"))) throw new Error("dangling durable json was written");
    if (fs.existsSync(path.join(images, "200-2-appIcon"))) throw new Error("missing copy produced a file");
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

# The notification icon pipeline consumes the shared AppIconResolver owner. A
# themed image-path name (the real foot case) must be retained AS A NAME, a
# sender file must be copied into our own store, a missing source must fall
# back honestly, and the real card must render every persisted value. Each mode
# runs the production Service and the production NotificationToast in a
# disposable XDG tree; none of them touches the live shell.
durable_icon_png_b64='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
for durable_icon_mode in embedded themed missing ghostty desktop-race screenshot; do
    durable_icon_root="$(mktemp -d)"
    mkdir -p -- "$durable_icon_root/runtime" "$durable_icon_root/state" \
        "$durable_icon_root/config" "$durable_icon_root/cache" \
        "$durable_icon_root/data-home" "$durable_icon_root/data/applications" \
        "$durable_icon_root/data/icons/hicolor/48x48/apps"
    durable_icon_source=""
    durable_icon_expected='.serviceLoaded == true and .matchesExpected == true and
        .diskMatchesModel == true and .liveMatchesModel == true and
        .noProvider == true and .noSenderPath == true and
        .toastSlotVisible == true and .toastReady == true'
    case "$durable_icon_mode" in
        embedded)
            durable_icon_source="$durable_icon_root/ephemeral-logo.png"
            base64 -d >"$durable_icon_source" <<<"$durable_icon_png_b64"
            durable_icon_expected="$durable_icon_expected and
                .appIconIsFile == true and .imageCleared == true and
                .activeActionsRetained == true and .popupActionsRetained == true"
            ;;
        themed)
            durable_icon_expected="$durable_icon_expected and
                .appIconIsName == true and .activeAppIcon == \"foot\""
            ;;
        ghostty)
            durable_icon_expected="$durable_icon_expected and
                .appIconIsName == true and .activeAppIcon == \"com.mitchellh.ghostty\""
            ;;
        desktop-race)
            durable_icon_expected="$durable_icon_expected and
                .appIconIsName == true and .activeAppIcon == \"example-tool\""
            ;;
        missing)
            durable_icon_expected="$durable_icon_expected and
                .appIconIsName == true and .appIconIsFile == false and
                .activeAppIcon == \"application-x-executable\""
            ;;
        screenshot)
            durable_icon_source="$durable_icon_root/screenshot.png"
            base64 -d >"$durable_icon_source" <<<"$durable_icon_png_b64"
            durable_icon_expected="$durable_icon_expected and
                .appIconIsFile == true and .imageCleared == true and
                .noSenderPath == true"
            ;;
    esac
    for icon in foot com.mitchellh.ghostty example-tool application-x-executable; do
        base64 -d >"$durable_icon_root/data/icons/hicolor/48x48/apps/$icon.png" <<<"$durable_icon_png_b64"
    done
    cat >"$durable_icon_root/data/applications/foot.desktop" <<'FIXTURE_FOOT_DESKTOP'
[Desktop Entry]
Type=Application
Name=Foot
Icon=foot
Exec=foot
FIXTURE_FOOT_DESKTOP
    cat >"$durable_icon_root/data/applications/com.mitchellh.ghostty.desktop" <<'FIXTURE_GHOSTTY_DESKTOP'
[Desktop Entry]
Type=Application
Name=Ghostty
Icon=com.mitchellh.ghostty
StartupWMClass=com.mitchellh.ghostty
Exec=ghostty
FIXTURE_GHOSTTY_DESKTOP
    cat >"$durable_icon_root/data/applications/com.example.tool.desktop" <<'FIXTURE_EXAMPLE_DESKTOP'
[Desktop Entry]
Type=Application
Name=Example Tool
Icon=example-tool
Exec=example-tool
FIXTURE_EXAMPLE_DESKTOP
    durable_icon_result="$durable_icon_root/result.json"
    : >"$durable_icon_result"
    durable_icon_log="$durable_icon_root/runtime.log"
    durable_icon_status=0
    AURELIA_NOTIFICATION_DURABLE_ICON_RESULT="$durable_icon_result" \
    AURELIA_NOTIFICATION_DURABLE_ICON_SERVICE_SOURCE="file://$plugin_root/Service.qml" \
    AURELIA_NOTIFICATION_DURABLE_ICON_TOAST_SOURCE="file://$plugin_root/ui/NotificationToast.qml" \
    AURELIA_NOTIFICATION_DURABLE_ICON_SOURCE="$durable_icon_source" \
    AURELIA_NOTIFICATION_DURABLE_ICON_MODE="$durable_icon_mode" \
    AURELIA_NOTIFICATION_DURABLE_ICON_METADATA_GATE="file://$ROOT/tests/fixtures/notifications/metadata-gate.qml" \
    QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$durable_icon_root/runtime" \
    XDG_STATE_HOME="$durable_icon_root/state" \
    XDG_CONFIG_HOME="$durable_icon_root/config" \
    XDG_CACHE_HOME="$durable_icon_root/cache" \
    XDG_DATA_HOME="$durable_icon_root/data-home" \
    XDG_DATA_DIRS="$durable_icon_root/data:/usr/share" \
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
    durable_icon_copy_count=0
    if [[ -d "$durable_icon_images" ]]; then
        durable_icon_copy_count="$(find "$durable_icon_images" -maxdepth 1 -type f -name '*-appIcon' | wc -l)"
    fi
    if [[ "$durable_icon_completed" -eq 1 ]] && [[ -s "$durable_icon_result" ]] &&
       runtime_log_is_environment_only "$durable_icon_log" \
           'Created graphical object was not placed in the graphics scene|FileView.*failed' &&
       ! grep -Eq 'TypeError|ReferenceError|Binding loop detected|Cannot assign|Loader\.Error|file_job_failed' "$durable_icon_log" &&
       jq -e "$durable_icon_expected" "$durable_icon_result" >/dev/null; then
        if [[ "$durable_icon_mode" == "embedded" ]] && [[ "$durable_icon_copy_count" -ne 1 ]]; then
            fail "[isolated-runtime] notification icon pipeline ($durable_icon_mode): expected exactly one durable app icon file, found $durable_icon_copy_count"
        else
            pass "[isolated-runtime] notification icon pipeline ($durable_icon_mode): resolution, persistence, and the rendered card are honest"
        fi
    else
        details="$(tail -n 48 "$durable_icon_log" || true)"
        if [[ -s "$durable_icon_result" ]]; then details="$details result=$(tr '\n' ' ' <"$durable_icon_result")"; fi
        fail "[isolated-runtime] notification icon pipeline ($durable_icon_mode) failed (status=$durable_icon_status): $details"
    fi
    rm -rf -- "$durable_icon_root"
done

# The card must tint a genuine symbolic mask and preserve a real logo. The
# symbolic decision is owned by the shared AppIconResolver; this fixture proves
# the rendered card follows it (symbolic overlay visible, colour Image hidden).
symbolic_fixture="$ROOT/tests/fixtures/notifications/symbolic-icon.qml"
if [[ ! -f "$symbolic_fixture" ]]; then
    fail "[static] symbolic notification icon fixture is missing"
elif [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] symbolic notification icon fixture (qs or timeout unavailable)"
else
    symbolic_root="$(mktemp -d)"
    mkdir -p -- "$symbolic_root/runtime" "$symbolic_root/state" \
        "$symbolic_root/config" "$symbolic_root/cache"
    symbolic_result="$symbolic_root/result.json"
    : >"$symbolic_result"
    symbolic_log="$symbolic_root/runtime.log"
    symbolic_status=0
    AURELIA_NOTIFICATION_SYMBOLIC_RESULT="$symbolic_result" \
    AURELIA_NOTIFICATION_SYMBOLIC_TOAST_SOURCE="file://$plugin_root/ui/NotificationToast.qml" \
    AURELIA_NOTIFICATION_SYMBOLIC_ICON="testfixture-symbolic" \
    QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$symbolic_root/runtime" \
    XDG_STATE_HOME="$symbolic_root/state" \
    XDG_CONFIG_HOME="$symbolic_root/config" \
    XDG_CACHE_HOME="$symbolic_root/cache" \
        /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
        --path "$symbolic_fixture" --no-color >"$symbolic_log" 2>&1 || symbolic_status=$?

    symbolic_completed=0
    if [[ "$symbolic_status" -eq 0 ]]; then
        symbolic_completed=1
    elif [[ "$symbolic_status" -eq 124 && -s "$symbolic_result" ]] &&
         grep -Fq 'Signal QQmlEngine::quit() emitted' "$symbolic_log"; then
        symbolic_completed=1
    fi
    if [[ "$symbolic_completed" -eq 1 ]] && [[ -s "$symbolic_result" ]] &&
       runtime_log_is_environment_only "$symbolic_log" \
           'Created graphical object was not placed in the graphics scene|FileView.*failed' &&
       ! grep -Eq 'TypeError|ReferenceError|Binding loop detected|Cannot assign|Loader\.Error' "$symbolic_log" &&
       jq -e '.loaded == true and .slotVisible == true and
              .symbolicNodeVisible == true and .symbolicPreservesColors == false and
              .symbolicUsesTint == true and .logoNodeVisible == false' \
           "$symbolic_result" >/dev/null; then
        pass "[isolated-runtime] a symbolic notification icon is tinted and never rendered as a colour logo"
    else
        details="$(tail -n 48 "$symbolic_log" || true)"
        if [[ -s "$symbolic_result" ]]; then details="$details result=$(tr '\n' ' ' <"$symbolic_result")"; fi
        fail "[isolated-runtime] symbolic notification icon fixture failed (status=$symbolic_status): $details"
    fi
    rm -rf -- "$symbolic_root"
fi

# Herdr (the terminal workspace manager pi runs inside) sends a raw
# "<label> · <number> · <count>" body with no action. The logic must render
# that in words and keep the visible "Open" label; what the action actually
# runs is resolved by the reviewed per-application cooperation registry, not by
# a synthesized shell string. The registry is a narrow table keyed by stable
# application id and action identifier whose values are argv vectors or URIs;
# an unknown pair or a malformed entry fails closed.
if command -v node >/dev/null; then
    herdr_logic_test="$(mktemp --suffix=.js)"
    sed '/^\.pragma library/d' "$plugin_root/NotificationLogic.js" >"$herdr_logic_test"
    cat >>"$herdr_logic_test" <<'HERDR_EXPORTS'
module.exports = { herdrRoute, herdrBody, styledBody, snapshotOf };
HERDR_EXPORTS
    if node -e '
const L = require(process.argv[1]);
const R = require(process.argv[2]);
function eq(actual, expected, label) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a !== e) { console.error("FAIL " + label + ": " + a + " !== " + e); process.exit(1); }
}
const n = { id: 7, appName: "Herdr", summary: "pi finished", body: "sutradhar \u00b7 2 \u00b7 3", urgency: 1 };
const snap = L.snapshotOf(n, 1700000000000);
const built = R.buildDefaultRegistry();
const reg = built.registry;
// The visible label is unchanged and the old synthesized shell argv is gone.
eq(snap.defaultActionText, "Open", "herdr label");
eq(snap.execArgv, "", "herdr execArgv is no longer a synthesized shell string");
eq(L.herdrBody("sutradhar \u00b7 2 \u00b7 3", "Herdr"), "sutradhar \u00b7 workspace 2", "herdr body");
eq(L.herdrRoute({ appName: "foot", body: "a \u00b7 1 \u00b7 1" }), null, "non-herdr route");
eq(L.snapshotOf({ appName: "Herdr", body: "x \u00b7 1", actions: [{ identifier: "default", text: "Reply" }] }, 1).defaultActionText,
   "Reply", "sender default label wins");
// Exact argv/URI for every registered entry, with no shell anywhere.
eq(built.rejected, [], "default registry validates cleanly");
eq(R.resolveAction(reg, "chromium-browser", "settings", {}),
   { kind: "argv", argv: ["/usr/bin/gtk-launch", "chromium-browser", "chrome://settings/content/notifications"] },
   "chromium settings argv");
eq(R.resolveAction(reg, "com.ulaa.Ulaa", "settings", {}),
   { kind: "argv", argv: ["/usr/bin/flatpak", "run", "com.ulaa.Ulaa", "chrome://settings/content/notifications"] },
   "ulaa settings argv");
// Herdr prefers the captured environment and falls back to the body number.
const captured = { originVersion: 1, captureQuality: "exact",
    tab: { kind: "herdr", workspaceId: "w1P", tabId: "w1T", paneId: "w1P:p2" } };
eq(R.resolveAction(reg, "Herdr", "default", { origin: captured, herdrNumber: 9 }).origin, captured,
   "captured herdr origin wins");
const fallback = R.resolveAction(reg, "Herdr", "default", { origin: null, herdrNumber: 2 });
eq(fallback.kind, "origin", "herdr fallback kind");
eq(fallback.origin.tab, { kind: "herdr", workspaceId: "2", tabId: null, paneId: null }, "herdr fallback tab");
// Fail closed for unknown apps/actions and sender-controlled fallback text.
eq(R.resolveAction(reg, "unregistered-app", "settings", {}), null, "unknown app");
eq(R.resolveAction(reg, "chromium-browser", "reply", {}), null, "unknown action");
eq(R.resolveAction(reg, "Herdr", "default", { origin: null, herdrNumber: "2; touch /tmp/pwned" }), null,
   "shell-shaped herdr number is rejected");
eq(R.resolveAction(reg, "Herdr", "default", { origin: null, herdrNumber: -1 }), null, "negative herdr number");
eq(R.resolveAction(reg, "Herdr", "default", { origin: null, herdrNumber: 1.5 }), null, "non-integer herdr number");
// Malformed entries are rejected at load, never used.
const malformed = R.buildRegistry([
    { id: "", action: "settings", argv: ["/bin/true"] },
    { id: "Google Chrome", action: "settings", argv: ["/bin/true"] },
    { id: "foo", action: "settings", argv: "rm -rf /" },
    { id: "foo", action: "settings", argv: ["/bin/true", 5] },
    { id: "foo", action: "settings", uri: 5 },
    { id: "foo", action: "settings", uri: "no-scheme" },
    { id: "foo", action: "settings" },
    { id: "foo", action: "settings", argv: ["/bin/true"], uri: "x:y" },
    { id: "foo", action: "", argv: ["/bin/true"] }
]);
eq(malformed.rejected.length, 9, "malformed entry count");
eq(malformed.registry.foo, undefined, "malformed entries are not inserted");
// No registry value is a shell command and no argv is a shell invocation.
for (const entry of R.DEFAULT_ENTRIES) {
    if (entry.argv) {
        const first = entry.argv[0];
        if (first === "bash" || first === "sh" || first === "/bin/bash" || first === "/bin/sh") {
            console.error("FAIL registry entry uses a shell: " + JSON.stringify(entry)); process.exit(1);
        }
    }
}
process.exit(0);
' "$herdr_logic_test" "$plugin_root/NotificationActionRegistry.js" >/dev/null; then
        pass "[unit] Herdr keeps the Open label and every registry entry resolves to an exact argv/URI or captured origin"
    else
        fail "[unit] Herdr projection or the notification action registry contract failed"
    fi
    rm -f -- "$herdr_logic_test"
else
    skip "[unit] Herdr notification projection and action registry (node unavailable)"
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
    AURELIA_NOTIFICATION_RENDER_SERVICE_SOURCE="file://$plugin_root/Service.qml" \
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
       runtime_log_is_environment_only "$render_log" \
           'Created graphical object was not placed in the graphics scene' &&
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
            .actionButtonCountInitial == 2 and
            .actionButtonsSameRowInitial == true and
            .serviceReady == true and
            .actionButtonCountAfterRawSetProperty == 1 and
            .rawActionsRoleUndefined == true and
            .actionButtonCountAfterProductionUpdate == 2 and
            .actionsCountAfterProductionUpdate == 1 and
            .actionsRoleUndefinedAfterProductionUpdate == false and
            .actionOneRowHeight == 28 and
            .actionWrappedHeight > .actionOneRowHeight and
            .actionWrappedButtonCount == 7 and
            .actionFlowWidth > 0 and
            .copyIcon == "edit-copy" and
            .copyIsIconControl == true and
            .copySameRowAsTitle == true and
            .copyAfterTitleInRow == true and
            .summaryLeftAligned == true and
            .bodyLeftAligned == true and
            .fallbackSourcePath == $icon and
            .fallbackName == "" and
            .emptyAppHidden == true and
            .emptyTimestampHidden == true
       ' "$render_result" >/dev/null; then
        pass "[isolated-runtime] shared notification card keeps every non-default action after the production ListModel update path"
    else
        details="$(tail -n 48 "$render_log" || true)"
        if [[ -s "$render_result" ]]; then details="$details result=$(tr '\n' ' ' <"$render_result")"; fi
        fail "[isolated-runtime] notification card render fixture failed (status=$render_status): $details"
    fi
fi

# A retained Inbox row must keep resolving its non-default action after the
# sender destroys the live notification. Chromium closes its notification
# object on send, which deletes the live reference while the Inbox row stays
# rendered. invokeAction must resolve the durable row instead of returning an
# index miss. Because this isolated row carries no captured origin, the honest
# result is "unavailable", the row is retained, and the outcome is surfaced on
# the card rather than silently removing it.
invoke_fixture="$ROOT/tests/fixtures/notifications/invoke-action.qml"
if [[ ! -f "$invoke_fixture" ]]; then
    fail "[static] notification retained-action invoke fixture is missing"
elif [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] notification retained-action invoke fixture (qs or timeout unavailable)"
else
    invoke_root="$(mktemp -d)"
    trap 'rm -rf -- "$invoke_root"  || true' RETURN
    mkdir -p -- "$invoke_root/runtime" "$invoke_root/state" \
        "$invoke_root/config" "$invoke_root/cache"
    invoke_result="$invoke_root/result.json"
    : >"$invoke_result"
    invoke_log="$invoke_root/runtime.log"
    invoke_status=0
    AURELIA_NOTIFICATION_INVOKE_RESULT="$invoke_result" \
    AURELIA_NOTIFICATION_INVOKE_SERVICE_SOURCE="file://$plugin_root/Service.qml" \
    AURELIA_NOTIFICATION_INVOKE_TOAST_SOURCE="file://$plugin_root/ui/NotificationToast.qml" \
    QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$invoke_root/runtime" \
    XDG_STATE_HOME="$invoke_root/state" \
    XDG_CONFIG_HOME="$invoke_root/config" \
    XDG_CACHE_HOME="$invoke_root/cache" \
        /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
        --path "$invoke_fixture" --no-color >"$invoke_log" 2>&1 || invoke_status=$?

    invoke_completed=0
    if [[ "$invoke_status" -eq 0 ]]; then
        invoke_completed=1
    elif [[ "$invoke_status" -eq 124 && -s "$invoke_result" ]] &&
         grep -Fq 'Signal QQmlEngine::quit() emitted' "$invoke_log"; then
        invoke_completed=1
    fi
    if [[ "$invoke_completed" -eq 1 ]] && [[ -s "$invoke_result" ]] &&
       runtime_log_is_environment_only "$invoke_log" \
           'Created graphical object was not placed in the graphics scene|Unable to find hyprland socket|quickshell\.hyprland\.ipc: Error making request' &&
       ! grep -Eq 'TypeError|ReferenceError|Binding loop detected|Cannot assign|Loader\.Error' "$invoke_log" &&
       jq -e '
            .serviceLoaded == true and
            .senderClosed == true and
            .activeCountAfterClose == 1 and
            .actionsCountAfterClose == 1 and
            .actionsRoleUndefinedAfterClose == false and
            .firstActionIdentifier == "settings" and
            .invokeResult == "unavailable" and
            .invokeOutcome == "unavailable" and
            .invokeRowRetained == true and
            .retainedSettingsButtonCount == 1 and
            .nonDefaultOnlyContainerVisible == true and
            .nonDefaultOnlySettingsButtonCount == 1
       ' "$invoke_result" >/dev/null; then
        pass "[isolated-runtime] retained Inbox row resolves its non-default action after the sender closes and the card renders the settings identifier"
    else
        details="$(tail -n 48 "$invoke_log" || true)"
        if [[ -s "$invoke_result" ]]; then details="$details result=$(tr '\n' ' ' <"$invoke_result")"; fi
        fail "[isolated-runtime] retained notification action fixture failed (status=$invoke_status): $details"
    fi
fi

# The action-result contract must be honest. A live action.invoke() that ran is
# "delivered"; a notification-level execArgv that was merely spawned is
# "executed"; an index/identity miss is "none". None of these may collapse back
# into a blanket "ok".
outcomes_fixture="$ROOT/tests/fixtures/notifications/invoke-outcomes.qml"
if [[ ! -f "$outcomes_fixture" ]]; then
    fail "[static] notification action-outcome fixture is missing"
elif [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] notification action-outcome fixture (qs or timeout unavailable)"
else
    outcomes_root="$(mktemp -d)"
    trap 'rm -rf -- "$outcomes_root"  || true' RETURN
    mkdir -p -- "$outcomes_root/runtime" "$outcomes_root/state" \
        "$outcomes_root/config" "$outcomes_root/cache"
    outcomes_result="$outcomes_root/result.json"
    : >"$outcomes_result"
    outcomes_log="$outcomes_root/runtime.log"
    outcomes_status=0
    AURELIA_NOTIFICATION_INVOKE_RESULT="$outcomes_result" \
    AURELIA_NOTIFICATION_INVOKE_SERVICE_SOURCE="file://$plugin_root/Service.qml" \
    AURELIA_NOTIFICATION_INVOKE_SENTINEL="$outcomes_root/executed.sentinel" \
    QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$outcomes_root/runtime" \
    XDG_STATE_HOME="$outcomes_root/state" \
    XDG_CONFIG_HOME="$outcomes_root/config" \
    XDG_CACHE_HOME="$outcomes_root/cache" \
        /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
        --path "$outcomes_fixture" --no-color >"$outcomes_log" 2>&1 || outcomes_status=$?

    outcomes_completed=0
    if [[ "$outcomes_status" -eq 0 ]]; then
        outcomes_completed=1
    elif [[ "$outcomes_status" -eq 124 && -s "$outcomes_result" ]] &&
         grep -Fq 'Signal QQmlEngine::quit() emitted' "$outcomes_log"; then
        outcomes_completed=1
    fi
    if [[ "$outcomes_completed" -eq 1 ]] && [[ -s "$outcomes_result" ]] &&
       runtime_log_is_environment_only "$outcomes_log" \
           'Created graphical object was not placed in the graphics scene|Unable to find hyprland socket|quickshell\.hyprland\.ipc: Error making request' &&
       ! grep -Eq 'TypeError|ReferenceError|Binding loop detected|Cannot assign|Loader\.Error' "$outcomes_log" &&
       jq -e '
            .serviceLoaded == true and
            .liveActionInvoked == true and
            .liveDeliveredResult == "delivered" and
            .liveRowRemoved == true and
            .executedSyncResult == "executed" and
            .execRowRemoved == true and
            .sentinelExists == true and
            .missingSyncResult == "executed" and
            .missingOutcome == "unavailable" and
            .missingRowRetained == true and
            .noneIndexResult == "none" and
            .noneIdentityResult == "none"
       ' "$outcomes_result" >/dev/null; then
        pass "[isolated-runtime] notification action results distinguish delivered, executed, unavailable, and none"
    else
        details="$(tail -n 48 "$outcomes_log" || true)"
        if [[ -s "$outcomes_result" ]]; then details="$details result=$(tr '\n' ' ' <"$outcomes_result")"; fi
        fail "[isolated-runtime] notification action-outcome fixture failed (status=$outcomes_status): $details"
    fi
fi

# Notification origin round trip. The production Service captures an origin at
# arrival, persists it with the popup JSON, restores it through restorePopups,
# and navigates with the same origin on click. The deterministic helper stub
# also proves honest negative behavior: a null capture, a timed-out capture,
# and corrupt or unknown-version origins all keep the notification displayed
# with no origin and report "unavailable" rather than crashing or claiming
# success.
origin_fixture="$ROOT/tests/fixtures/notifications/origin-roundtrip.qml"
if [[ ! -f "$origin_fixture" ]]; then
    fail "[static] notification origin round-trip fixture is missing"
elif [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] notification origin round-trip fixture (qs or timeout unavailable)"
else
    origin_root="$(mktemp -d)"
    trap 'rm -rf -- "$origin_root"  || true' RETURN
    mkdir -p -- "$origin_root/runtime" "$origin_root/state" \
        "$origin_root/config" "$origin_root/cache" "$origin_root/bin"
    origin_result="$origin_root/result.json"
    : >"$origin_result"
    origin_log="$origin_root/runtime.log"
    origin_sentinel="$origin_root/navigate.sentinel"
    write_notification_origin_stub "$origin_root/bin/workstation-notification-focus"
    capture_origin='{"originVersion":1,"capturedAt":1700000000000,"notifyId":501,"captureQuality":"exact","captureSource":"bus-monitor","sender":{"pid":4242},"notify":{"appName":"Chromium"},"compositor":{"address":"0xabc","workspaceId":2},"tab":{},"originUrl":"http://127.0.0.1:8899/"}'
    capture_origin_routed='{"originVersion":1,"capturedAt":1700000000000,"notifyId":503,"captureQuality":"exact","captureSource":"bus-monitor","sender":{"pid":4242},"notify":{"appName":"Chromium"},"compositor":{"address":"0xabc","workspaceId":2},"tab":{},"originUrl":"http://127.0.0.1:8899/"}'
    origin_status=0
    AURELIA_ORIGIN_RESULT="$origin_result" \
    AURELIA_ORIGIN_SERVICE_SOURCE="file://$plugin_root/Service.qml" \
    AURELIA_NOTIFICATION_TEST_HELPER="$origin_root/bin/workstation-notification-focus" \
    AURELIA_NOTIFICATION_TEST_HELPER_TIMEOUT_MS=1000 \
    AURELIA_STUB_CAPTURE="$capture_origin" \
    AURELIA_STUB_CAPTURE_ROUTED="$capture_origin_routed" \
    AURELIA_STUB_NAVIGATE_SENTINEL="$origin_sentinel" \
    QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$origin_root/runtime" \
    XDG_STATE_HOME="$origin_root/state" \
    XDG_CONFIG_HOME="$origin_root/config" \
    XDG_CACHE_HOME="$origin_root/cache" \
        /usr/bin/timeout --kill-after=1s 14s /usr/bin/qs --no-duplicate \
        --path "$origin_fixture" --no-color >"$origin_log" 2>&1 || origin_status=$?

    origin_completed=0
    if [[ "$origin_status" -eq 0 ]]; then
        origin_completed=1
    elif [[ "$origin_status" -eq 124 && -s "$origin_result" ]] &&
         grep -Fq 'Signal QQmlEngine::quit() emitted' "$origin_log"; then
        origin_completed=1
    fi
    if [[ "$origin_completed" -eq 1 ]] && [[ -s "$origin_result" ]] &&
       runtime_log_is_environment_only "$origin_log" \
           'Created graphical object was not placed in the graphics scene|Unable to find hyprland socket|quickshell\.hyprland\.ipc: Error making request' &&
       ! grep -Eq 'TypeError|ReferenceError|Binding loop detected|Cannot assign|Loader\.Error' "$origin_log" &&
       jq -e --arg exact "$capture_origin" --arg routed "$capture_origin_routed" '
            .serviceLoaded == true and
            .capturedOrigin == $exact and
            .liveOrigin == $exact and
            .diskOrigin == $exact and
            .restoredOrigin == $exact and
            (.clickSentinel | contains("http://127.0.0.1:8899/")) and
            (.clickSentinel | contains("\"notifyId\":501")) and
            .clickRowRemoved == true and
            .routedOrigin == $routed and
            .routedOutcome == "routed" and
            .routedRowRetained == true and
            .nullRowRetained == true and .nullOrigin == "" and
            .slowRowRetained == true and .slowOrigin == "" and
            .corruptRowRetained == true and .corruptOutcome == "unavailable" and
            .unknownRowRetained == true and .unknownOutcome == "unavailable"
       ' "$origin_result" >/dev/null; then
        pass "[isolated-runtime] notification origin capture, persistence, restore, and navigation round trip honestly"
    else
        details="$(tail -n 48 "$origin_log" || true)"
        if [[ -s "$origin_result" ]]; then details="$details result=$(tr '\n' ' ' <"$origin_result")"; fi
        fail "[isolated-runtime] notification origin round-trip fixture failed (status=$origin_status): $details"
    fi
fi

# Per-application cooperation registry. The registry is the single owner of
# "what does a retained row's non-default or synthesized default action
# actually run". This fixture drives the real Service with durable rows that
# have no live sender, proves the Herdr default prefers the captured origin and
# falls back to the body workspace number, proves a registry argv genuinely
# runs (a sentinel side effect), and proves an unregistered pair fails closed.
registry_fixture="$ROOT/tests/fixtures/notifications/action-registry.qml"
if [[ ! -f "$registry_fixture" ]]; then
    fail "[static] notification action-registry fixture is missing"
elif [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] notification action-registry fixture (qs or timeout unavailable)"
else
    registry_root="$(mktemp -d)"
    trap 'rm -rf -- "$registry_root"  || true' RETURN
    mkdir -p -- "$registry_root/runtime" "$registry_root/state" \
        "$registry_root/config" "$registry_root/cache" "$registry_root/bin"
    registry_result="$registry_root/result.json"
    : >"$registry_result"
    registry_log="$registry_root/runtime.log"
    registry_navigate_sentinel="$registry_root/navigate.sentinel"
    registry_argv_sentinel="$registry_root/registry-argv.sentinel"
    write_notification_origin_stub "$registry_root/bin/workstation-notification-focus"
    registry_override="$(jq -c -n --arg sentinel "$registry_argv_sentinel" \
        '[{id:"fixture-registry",action:"settings",argv:["/usr/bin/touch",$sentinel]}]')"
    registry_status=0
    AURELIA_REGISTRY_RESULT="$registry_result" \
    AURELIA_REGISTRY_SERVICE_SOURCE="file://$plugin_root/Service.qml" \
    AURELIA_NOTIFICATION_TEST_HELPER="$registry_root/bin/workstation-notification-focus" \
    AURELIA_NOTIFICATION_TEST_REGISTRY="$registry_override" \
    AURELIA_NOTIFICATION_TEST_HELPER_TIMEOUT_MS=1000 \
    AURELIA_STUB_NAVIGATE_SENTINEL="$registry_navigate_sentinel" \
    AURELIA_REGISTRY_ARGV_SENTINEL="$registry_argv_sentinel" \
    QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$registry_root/runtime" \
    XDG_STATE_HOME="$registry_root/state" \
    XDG_CONFIG_HOME="$registry_root/config" \
    XDG_CACHE_HOME="$registry_root/cache" \
        /usr/bin/timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
        --path "$registry_fixture" --no-color >"$registry_log" 2>&1 || registry_status=$?

    registry_completed=0
    if [[ "$registry_status" -eq 0 ]]; then
        registry_completed=1
    elif [[ "$registry_status" -eq 124 && -s "$registry_result" ]] &&
         grep -Fq 'Signal QQmlEngine::quit() emitted' "$registry_log"; then
        registry_completed=1
    fi
    if [[ "$registry_completed" -eq 1 ]] && [[ -s "$registry_result" ]] &&
       runtime_log_is_environment_only "$registry_log" \
           'Created graphical object was not placed in the graphics scene|Unable to find hyprland socket|quickshell\.hyprland\.ipc: Error making request' &&
       ! grep -Eq 'TypeError|ReferenceError|Binding loop detected|Cannot assign|Loader\.Error' "$registry_log" &&
       jq -e '
            .serviceLoaded == true and
            .capturedInvokeResult == "routed" and
            .capturedRowRemoved == true and
            (.navigateSentinel | contains("\"workspaceId\":\"w1P\"")) and
            (.navigateSentinel | contains("\"tabId\":\"w1T\"")) and
            .fallbackInvokeResult == "routed" and
            .fallbackRowRemoved == true and
            (.navigateSentinel | contains("\"workspaceId\":\"7\"")) and
            .argvInvokeResult == "delivered" and
            .argvRowRemoved == true and
            .argvSentinelExists == true and
            .unknownInvokeResult == "unavailable" and
            .unknownRowRetained == true and
            .unknownOutcome == "unavailable"
       ' "$registry_result" >/dev/null; then
        pass "[isolated-runtime] action registry resolves retained rows and fails closed for unknown pairs"
    else
        details="$(tail -n 48 "$registry_log" || true)"
        if [[ -s "$registry_result" ]]; then details="$details result=$(tr '\n' ' ' <"$registry_result")"; fi
        fail "[isolated-runtime] notification action-registry fixture failed (status=$registry_status): $details"
    fi
fi
