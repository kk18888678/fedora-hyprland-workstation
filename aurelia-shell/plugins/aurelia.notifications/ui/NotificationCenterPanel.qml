import QtQuick
import QtQuick.Layouts
import "../../../ui"
import "../../../theme"
import "../NotificationLogic.js" as Logic

// Keyboard-capable, bar-anchored Inbox/controls surface. It is deliberately
// one compact center rather than a second daemon: the service remains the only
// mutation owner for DND and dismissal.
AureliaKeyboardPanel {
    id: root

    property var service: null

    readonly property bool currentViewEmpty: root.service === null ||
        root.service.activeModel.count === 0

    bar: root.service ? root.service.bar : null
    ownerId: "aurelia.notifications"
    // The reference KeyboardPanel defaults to 280x200. This center keeps a
    // readable Inbox layout while applying the requested +30% width and +40%
    // height to the previous Aurelia compact bounds.
    popupWidth: Math.min(416, Math.max(320, root.width - Theme.spacingLg * 2))
    popupHeight: Math.min(root.currentViewEmpty ? 308 : 476, Math.max(280, root.height - root.margin * 2))
    contentSizingItem: centerColumn
    fitHeightToContent: true
    minPopupHeight: 280
    maxPopupHeight: 476
    contentPadding: Theme.spacingSm
    shown: root.service !== null && root.service.centerOpen
    dismissHandler: function() {
        root.close()
    }

    function close() {
        if (root.service) root.service.closeCenter()
        else root.shown = false
    }

    function closeForPopoutSwitch() { root.close() }

    FocusScope {
        id: centerFocus
        anchors.fill: parent
        focus: root.shown

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
            }
        }

        ColumnLayout {
            id: centerColumn
            anchors.fill: parent
            spacing: Theme.spacingXs

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "Notifications"
                    color: Theme.text
                    font.family: Theme.fontFamilyProse
                    font.pixelSize: Theme.fontSizeLg
                    font.weight: Theme.fontWeightBold
                }

                AureliaIconButton {
                    icon: root.service && root.service.doNotDisturb ? "notifications-disabled" : "notifications"
                    tooltip: root.service && root.service.doNotDisturb ? "Allow notifications" : "Silence notifications"
                    active: !!(root.service && root.service.doNotDisturb)
                    onTriggered: root.service.toggleDnd()
                }

                AureliaIconButton {
                    icon: "window-close"
                    tooltip: "Close notification center"
                    onTriggered: root.service.closeCenter()
                }
            }

            Text {
                Layout.fillWidth: true
                text: (root.service ? root.service.activeModel.count : 0) + " inbox · " + (root.service ? root.service.serverStatus : "") + (root.service && root.service.doNotDisturb ? " · DND on" : "")
                color: Theme.textSecondary
                font.family: Theme.fontFamilyProse
                font.pixelSize: Theme.fontSizeXs
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                Layout.minimumHeight: 20
                Layout.maximumHeight: 20

                Item { Layout.fillWidth: true }

                Text {
                    visible: !!(root.service && root.service.activeModel.count > 0)
                    text: "Dismiss all"
                    color: textDismissMouse.containsMouse ? Theme.text : Theme.textMuted
                    font.family: Theme.fontFamilyProse
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Theme.fontWeightMedium

                    MouseArea {
                        id: textDismissMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(mouse) {
                            mouse.accepted = true
                            root.service.dismissAll()
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: activeList
                    anchors.fill: parent
                    clip: true
                    spacing: Theme.spacingXs
                    model: root.service ? root.service.activeModel : null

                    delegate: Item {
                        id: activeDelegate
                        required property int index
                        required property var originalId
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
                        required property double timestamp
                        width: activeList.width
                        height: activeRow.implicitHeight

                        NotificationToast {
                            id: activeRow
                            anchors.fill: parent
                            app: String(activeDelegate.app || "")
                            appIcon: String(activeDelegate.appIcon || "")
                            desktopEntry: String(activeDelegate.desktopEntry || "")
                            summary: String(activeDelegate.summary || "")
                            body: String(activeDelegate.body || "")
                            image: String(activeDelegate.image || "")
                            glyph: String(activeDelegate.glyph || "")
                            execArgv: String(activeDelegate.execArgv || "")
                            actions: activeDelegate.actions || []
                            defaultActionText: String(activeDelegate.defaultActionText || "")
                            urgency: activeDelegate.urgency
                            identityOriginalId: activeDelegate.originalId
                            identityTimestamp: activeDelegate.timestamp
                            identityIndex: activeDelegate.index
                            timestampLabel: Logic.timestampLabel(activeDelegate.timestamp, Date.now())
                            onDismissed: function(originalId, timestamp, index) {
                                root.service.dismissAt(index, originalId, timestamp)
                            }
                            onActivated: root.service.invokeDefault(activeDelegate.index, activeDelegate.originalId, activeDelegate.timestamp)
                            onDefaultActionInvoked: root.service.invokeDefault(activeDelegate.index, activeDelegate.originalId, activeDelegate.timestamp)
                            onActionInvoked: function(identifier) {
                                var status = root.service.invokeAction(activeDelegate.index, identifier, activeDelegate.originalId, activeDelegate.timestamp)
                                // Do not let a sender-window route read as a delivered action.
                                if (status !== "delivered" && status !== "executed")
                                    console.info("[NOTIFICATIONS] action.outcome status=" + status + " identifier=" + identifier)
                            }
                            onCopyRequested: root.service.copyNotificationAt(activeDelegate.index, activeDelegate.originalId, activeDelegate.timestamp)
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.spacingXs
                    visible: root.currentViewEmpty

                    AureliaIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 24
                        height: 24
                        name: "notifications"
                        iconSize: 24
                        tint: Theme.accent
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "You’re all caught up"
                        color: Theme.text
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Theme.fontWeightBold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "New alerts will appear here automatically."
                        color: Theme.textSecondary
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeSm
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Click the bell to open this center · right-click it for DND"
                        color: Theme.textMuted
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeXs
                    }
                }
            }
        }
    }
}
