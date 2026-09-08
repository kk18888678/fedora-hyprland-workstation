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
        width: Math.min(520, Math.max(280, parent.width - Theme.spacingLg * 2))
        height: Math.min(640, Math.max(260, parent.height - anchors.topMargin - Theme.spacingLg))
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

                    AureliaActionButton {
                        compact: true
                        label: root.service && root.service.doNotDisturb ? "DND On" : "DND Off"
                        icon: root.service && root.service.doNotDisturb ? "notifications-disabled" : "notifications"
                        primary: !!(root.service && root.service.doNotDisturb)
                        onTriggered: root.service.toggleDnd()
                    }

                    AureliaActionButton {
                        compact: true
                        label: "Close"
                        icon: "window-close"
                        onTriggered: root.service.closeCenter()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: (root.service ? root.service.activeModel.count : 0) + " active · " + (root.service ? root.service.historyModel.count : 0) + " saved"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXs

                    AureliaActionButton {
                        Layout.fillWidth: true
                        compact: true
                        label: "Active"
                        detail: root.service ? String(root.service.activeModel.count) : "0"
                        primary: !!(root.service && root.service.centerMode === "active")
                        onTriggered: root.service.centerMode = "active"
                    }

                    AureliaActionButton {
                        Layout.fillWidth: true
                        compact: true
                        label: "History"
                        detail: root.service ? String(root.service.historyModel.count) : "0"
                        primary: !!(root.service && root.service.centerMode === "history")
                        onTriggered: root.service.centerMode = "history"
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXs

                    AureliaActionButton {
                        Layout.fillWidth: true
                        compact: true
                        label: "Dismiss All"
                        icon: "edit-clear"
                        enabled: !!(root.service && root.service.activeModel.count > 0)
                        onTriggered: root.service.dismissAll()
                    }

                    AureliaActionButton {
                        Layout.fillWidth: true
                        compact: true
                        label: "Clear History"
                        icon: "user-trash"
                        enabled: !!(root.service && root.service.historyModel.count > 0)
                        onTriggered: root.service.clearHistory()
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
                                required property int urgency
                                required property double timestamp
                                width: activeList.width
                                height: activeRow.implicitHeight

                                NotificationRow {
                                    id: activeRow
                                    anchors.fill: parent
                                    app: String(activeDelegate.app || "")
                                    appIcon: String(activeDelegate.appIcon || "")
                                    summary: String(activeDelegate.summary || "")
                                    body: String(activeDelegate.body || "")
                                    urgency: activeDelegate.urgency
                                    timestamp: activeDelegate.timestamp
                                    dismissible: true
                                    onDismissRequested: root.service.dismissAt(activeDelegate.index)
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
                                required property int urgency
                                required property double timestamp
                                width: historyList.width
                                height: historyRow.implicitHeight

                                NotificationRow {
                                    id: historyRow
                                    anchors.fill: parent
                                    app: String(historyDelegate.app || "")
                                    appIcon: String(historyDelegate.appIcon || "")
                                    summary: String(historyDelegate.summary || "")
                                    body: String(historyDelegate.body || "")
                                    urgency: historyDelegate.urgency
                                    timestamp: historyDelegate.timestamp
                                    dismissible: false
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !!(root.service && root.service.centerMode === "active")
                            ? root.service.activeModel.count === 0
                            : root.service && root.service.historyModel.count === 0
                        text: root.service && root.service.centerMode === "active"
                            ? "No active notifications"
                            : "No notification history"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                    }
                }
            }
        }

        onVisibleChanged: {
            if (visible) Qt.callLater(function() { centerFocus.forceActiveFocus() })
        }
    }
}
