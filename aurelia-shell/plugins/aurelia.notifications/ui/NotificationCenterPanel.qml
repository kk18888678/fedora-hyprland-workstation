import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../../ui"
import "../../../theme"

// Keyboard-capable history/controls surface. It is deliberately one compact
// center rather than a second daemon: the service remains the only mutation
// owner for DND, dismissal, and persisted history.
PanelWindow {
    id: root

    property var service: null

    readonly property bool currentViewEmpty: root.service === null ||
        (root.service.centerMode === "history"
            ? root.service.historyModel.count === 0
            : root.service.activeModel.count === 0)

    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: root.service !== null && root.service.centerOpen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aurelia-notification-center"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: function(mouse) {
            mouse.accepted = true
            root.service.closeCenter()
        }
    }

    Rectangle {
        id: centerCard
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: Theme.spacingLg
        anchors.topMargin: root.service && root.service.barClearance > Theme.spacingLg
            ? root.service.barClearance + Theme.spacingLg
            : Theme.spacingLg
        width: Math.min(400, Math.max(300, parent.width - Theme.spacingLg * 2))
        height: Math.min(root.currentViewEmpty ? 360 : 520, Math.max(260, parent.height - anchors.topMargin - Theme.spacingLg))
        radius: Theme.radiusLg
        color: Theme.bgBase
        border.color: Theme.borderActive
        border.width: Theme.borderWidthDefault

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) { mouse.accepted = true }
        }

        FocusScope {
            id: centerFocus
            anchors.fill: parent
            anchors.margins: Theme.popupPadding
            focus: root.visible

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    root.service.closeCenter()
                    event.accepted = true
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: "Notifications"
                        color: Theme.text
                        font.family: Theme.fontFamily
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
                    text: (root.service ? root.service.activeModel.count : 0) + " active · " + (root.service ? root.service.historyModel.count : 0) + " saved · " + (root.service ? root.service.serverStatus : "") + (root.service && root.service.doNotDisturb ? " · DND on" : "")
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    Layout.minimumHeight: 32
                    Layout.maximumHeight: 32
                    spacing: Theme.spacingMd

                    Item {
                        Layout.fillWidth: true
                        height: 32

                        Text {
                            anchors.centerIn: parent
                            text: "Active  " + (root.service ? root.service.activeModel.count : 0)
                            color: root.service && root.service.centerMode === "active" ? Theme.text : Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 2
                            color: Theme.accent
                            visible: !!(root.service && root.service.centerMode === "active")
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: function(mouse) {
                                mouse.accepted = true
                                root.service.centerMode = "active"
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        height: 32

                        Text {
                            anchors.centerIn: parent
                            text: "History  " + (root.service ? root.service.historyModel.count : 0)
                            color: root.service && root.service.centerMode === "history" ? Theme.text : Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 2
                            color: Theme.accent
                            visible: !!(root.service && root.service.centerMode === "history")
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: function(mouse) {
                                mouse.accepted = true
                                root.service.centerMode = "history"
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    Layout.minimumHeight: 24
                    Layout.maximumHeight: 24

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: !!(root.service && root.service.activeModel.count > 0)
                        text: "Dismiss all"
                        color: textDismissMouse.containsMouse ? Theme.text : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs

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

                    Text {
                        visible: !!(root.service && root.service.historyModel.count > 0)
                        text: "Clear history"
                        color: textClearMouse.containsMouse ? Theme.text : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs

                        MouseArea {
                            id: textClearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) {
                                mouse.accepted = true
                                root.service.clearHistory()
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    StackLayout {
                        anchors.fill: parent
                        currentIndex: root.service && root.service.centerMode === "history" ? 1 : 0

                        ListView {
                            id: activeList
                            clip: true
                            spacing: Theme.spacingXs
                            model: root.service ? root.service.activeModel : null

                            delegate: Item {
                                id: activeDelegate
                                required property int index
                                required property var app
                                required property var appIcon
                                required property var summary
                                required property var body
                                required property var image
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
                                    summary: String(activeDelegate.summary || "")
                                    body: String(activeDelegate.body || "")
                                    image: String(activeDelegate.image || "")
                                    actions: activeDelegate.actions || []
                                    defaultActionText: String(activeDelegate.defaultActionText || "")
                                    urgency: activeDelegate.urgency
                                    onDismissed: root.service.dismissAt(activeDelegate.index)
                                    onActivated: root.service.invokeDefault(activeDelegate.index)
                                    onDefaultActionInvoked: root.service.invokeDefault(activeDelegate.index)
                                    onActionInvoked: function(identifier) { root.service.invokeAction(activeDelegate.index, identifier) }
                                }
                            }
                        }

                        ListView {
                            id: historyList
                            clip: true
                            spacing: Theme.spacingXs
                            model: root.service ? root.service.historyModel : null

                            delegate: Item {
                                id: historyDelegate
                                required property int index
                                required property var app
                                required property var appIcon
                                required property var summary
                                required property var body
                                required property var image
                                required property int urgency
                                required property double timestamp
                                width: historyList.width
                                height: historyRow.implicitHeight

                                NotificationToast {
                                    id: historyRow
                                    anchors.fill: parent
                                    app: String(historyDelegate.app || "")
                                    appIcon: String(historyDelegate.appIcon || "")
                                    summary: String(historyDelegate.summary || "")
                                    body: String(historyDelegate.body || "")
                                    image: String(historyDelegate.image || "")
                                    urgency: historyDelegate.urgency
                                    interactive: false
                                    showDismiss: false
                                    showActions: false
                                    timestampLabel: historyDelegate.timestamp > 0
                                        ? Qt.formatTime(new Date(historyDelegate.timestamp), "HH:mm")
                                        : ""
                                }
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.spacingXs
                        visible: root.currentViewEmpty

                        AureliaIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 28
                            height: 28
                            name: root.service && root.service.centerMode === "history"
                                ? "document-open-recent"
                                : "notifications"
                            iconSize: 28
                            tint: Theme.accent
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.service && root.service.centerMode === "history"
                                ? "No saved notifications"
                                : "You’re all caught up"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.service && root.service.centerMode === "history"
                                ? "History will appear here after a notification is dismissed."
                                : "New alerts will appear here automatically."
                            color: Theme.textSecondary
                            font.family: Theme.fontFamilyProse
                            font.pixelSize: Theme.fontSizeXs
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Click the bell to open this center · right-click it for DND"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                        }
                    }
                }
            }
        }

        onVisibleChanged: {
            if (visible) Qt.callLater(function() { centerFocus.forceActiveFocus() })
        }
    }
}
