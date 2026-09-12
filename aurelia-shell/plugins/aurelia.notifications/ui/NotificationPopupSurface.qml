import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../../theme"
import "."
import "../NotificationLogic.js" as Logic

// Passive notification surface. Its position is derived from the live bar
// slot on every geometry/layout change; there is no fixed top-right fallback.
PanelWindow {
    id: root

    property var notificationService: null
    property var screenModel: null

    readonly property var bar: root.notificationService ? root.notificationService.bar : null
    readonly property var anchorSlot: {
        var revision = root.bar ? root.bar.widgetRevision : 0
        return root.bar && typeof root.bar.anchorItemFor === "function"
            ? root.bar.anchorItemFor("aurelia.notifications")
            : null
    }
    readonly property var anchorWindow: root.anchorSlot && root.anchorSlot.QsWindow && root.anchorSlot.QsWindow.window
        ? root.anchorSlot.QsWindow.window
        : (root.bar && root.bar.contentItem ? root.bar : null)
    readonly property point anchorPosition: {
        var revision = root.bar ? root.bar.widgetRevision : 0
        var slotX = root.anchorSlot ? root.anchorSlot.x : 0
        var slotY = root.anchorSlot ? root.anchorSlot.y : 0
        var slotWidth = root.anchorSlot ? root.anchorSlot.width : 0
        var slotHeight = root.anchorSlot ? root.anchorSlot.height : 0
        if (!root.anchorSlot || !root.anchorWindow || !root.anchorWindow.contentItem) return Qt.point(0, 0)
        return root.anchorSlot.mapToItem(root.anchorWindow.contentItem, 0, 0)
    }
    readonly property bool anchored: {
        // Read the declared model screen instead of the PanelWindow.screen
        // binding. The latter is compositor-managed and can feed back into
        // this visibility calculation while the bar layer is being remapped.
        var targetScreen = root.screenModel
        var screenName = targetScreen && targetScreen.name ? String(targetScreen.name) : ""
        var anchorScreenName = root.anchorWindow && root.anchorWindow.screen && root.anchorWindow.screen.name
            ? String(root.anchorWindow.screen.name)
            : ""
        return root.anchorSlot !== null && root.anchorWindow !== null &&
            root.anchorSlot.visible && root.bar && root.bar.barHidden !== true &&
            targetScreen !== null &&
            (root.anchorWindow.screen === targetScreen || (screenName !== "" && screenName === anchorScreenName))
    }
    readonly property real columnWidth: Math.max(1, Math.min(416, root.width - Theme.spacingMd * 2))
    readonly property point popupOrigin: {
        var revision = root.bar ? root.bar.widgetRevision : 0
        var columnHeight = popupColumn.implicitHeight
        var x = root.anchorPosition.x + (root.anchorSlot ? root.anchorSlot.width / 2 : 0) - root.columnWidth / 2
        var y = Theme.spacingMd
        var barSize = root.bar ? Number(root.bar.barSize || 0) : 0

        if (!root.anchored) return Qt.point(-root.columnWidth, -columnHeight)
        if (root.bar.position === "bottom") {
            y = root.height - barSize - columnHeight - Theme.popupMargin
        } else if (root.bar.position === "left") {
            x = barSize + Theme.popupMargin
            y = root.anchorPosition.y + (root.anchorSlot ? root.anchorSlot.height / 2 : 0) - columnHeight / 2
        } else if (root.bar.position === "right") {
            x = root.width - barSize - root.columnWidth - Theme.popupMargin
            y = root.anchorPosition.y + (root.anchorSlot ? root.anchorSlot.height / 2 : 0) - columnHeight / 2
        } else {
            y = barSize + Theme.popupMargin
        }

        x = Math.max(Theme.spacingMd, Math.min(x, root.width - root.columnWidth - Theme.spacingMd))
        y = Math.max(Theme.spacingMd, Math.min(y, root.height - columnHeight - Theme.spacingMd))
        return Qt.point(Math.round(x), Math.round(y))
    }

    screen: root.screenModel
    visible: root.notificationService !== null && root.notificationService.popupModel.count > 0 && root.anchored
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aurelia-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: popupColumn }

    ColumnLayout {
        id: popupColumn
        x: root.popupOrigin.x
        y: root.popupOrigin.y
        width: root.columnWidth
        spacing: Theme.spacingSm
        visible: root.anchored

        Repeater {
            model: root.notificationService ? root.notificationService.popupModel : null

            delegate: Item {
                id: popupSlot
                required property int index
                required property var originalId
                required property double timestamp
                required property var app
                required property var appIcon
                required property var desktopEntry
                required property var summary
                required property var body
                required property var image
                required property var glyph
                required property var execArgv
                required property var actions
                required property var defaultActionText
                required property int urgency
                required property double expireTimeout

                Layout.preferredWidth: notificationToast.implicitWidth
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: notificationToast.implicitWidth
                implicitHeight: notificationToast.implicitHeight

                property int remainingLifetime: Math.round(Logic.durationFor(
                    popupSlot.urgency, popupSlot.expireTimeout, popupSlot.app, popupSlot.desktopEntry, popupSlot.appIcon))
                property double timerStartedAt: 0
                readonly property bool hovered: notificationToast.hovered

                function startLifetime() {
                    if (remainingLifetime <= 0 || popupSlot.hovered) return
                    timerStartedAt = Date.now()
                    expiryTimer.interval = remainingLifetime
                    expiryTimer.restart()
                }

                function pauseLifetime() {
                    if (!expiryTimer.running || remainingLifetime <= 0) return
                    remainingLifetime = Math.max(1, remainingLifetime - (Date.now() - timerStartedAt))
                    expiryTimer.stop()
                }

                function restartLifetime() {
                    remainingLifetime = Math.round(Logic.durationFor(
                        popupSlot.urgency, popupSlot.expireTimeout, popupSlot.app, popupSlot.desktopEntry, popupSlot.appIcon))
                    startLifetime()
                }

                onHoveredChanged: hovered ? pauseLifetime() : startLifetime()
                onSummaryChanged: restartLifetime()
                onBodyChanged: restartLifetime()
                onImageChanged: restartLifetime()
                Component.onCompleted: startLifetime()

                Timer {
                    id: expiryTimer
                    repeat: false
                    onTriggered: root.notificationService.expireAt(popupSlot.index, popupSlot.originalId, popupSlot.timestamp)
                }

                NotificationToast {
                    id: notificationToast
                    anchors.fill: parent
                    app: popupSlot.app
                    appIcon: popupSlot.appIcon
                    desktopEntry: popupSlot.desktopEntry
                    summary: popupSlot.summary
                    body: popupSlot.body
                    image: popupSlot.image
                    glyph: popupSlot.glyph
                    execArgv: popupSlot.execArgv
                    actions: popupSlot.actions
                    defaultActionText: String(popupSlot.defaultActionText || "")
                    urgency: popupSlot.urgency
                    showArchive: false
                    onDismissed: root.notificationService.dismissAt(popupSlot.index, popupSlot.originalId, popupSlot.timestamp)
                    onActivated: root.notificationService.invokeDefault(popupSlot.index, popupSlot.originalId, popupSlot.timestamp)
                    onDefaultActionInvoked: root.notificationService.invokeDefault(popupSlot.index, popupSlot.originalId, popupSlot.timestamp)
                    onActionInvoked: function(identifier) { root.notificationService.invokeAction(popupSlot.index, identifier, popupSlot.originalId, popupSlot.timestamp) }
                    onArchiveRequested: root.notificationService.archiveByIdentity(popupSlot.originalId, popupSlot.timestamp)
                }
            }
        }
    }
}
