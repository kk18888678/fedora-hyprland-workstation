import QtQuick
import QtQuick.Layouts
import "../../../ui"
import "../../../theme"

// Keyboard-capable, bar-anchored history/controls surface. It is deliberately
// one compact center rather than a second daemon: the service remains the only
// mutation owner for DND, dismissal, and persisted history.
AureliaKeyboardPanel {
    id: root

    property var service: null

    readonly property bool currentViewEmpty: root.service === null ||
        (root.service.centerMode === "history"
            ? root.service.historyModel.count === 0
            : root.service.activeModel.count === 0)

    bar: root.service ? root.service.bar : null
    ownerId: "aurelia.notifications"
    // The reference KeyboardPanel defaults to 280x200. This center keeps a
    // readable two-tab layout while applying the requested +30% width and
    // +40% height to the previous Aurelia compact bounds.
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
                text: (root.service ? root.service.activeModel.count : 0) + " inbox · " + (root.service ? root.service.historyModel.count : 0) + " saved · " + (root.service ? root.service.serverStatus : "") + (root.service && root.service.doNotDisturb ? " · DND on" : "")
                color: Theme.textSecondary
                font.family: Theme.fontFamilyProse
                font.pixelSize: Theme.fontSizeXs
                elide: Text.ElideRight
            }

            RowLayout {
                id: viewTabs
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                Layout.minimumHeight: 26
                Layout.maximumHeight: 26
                spacing: Theme.spacingMd

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Text {
                        anchors.centerIn: parent
                        text: "Inbox  " + (root.service ? root.service.activeModel.count : 0)
                        color: root.service && root.service.centerMode === "active"
                            ? Theme.text : Theme.textMuted
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Theme.fontWeightMedium
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
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
                    Layout.fillHeight: true

                    Text {
                        anchors.centerIn: parent
                        text: "History  " + (root.service ? root.service.historyModel.count : 0)
                        color: root.service && root.service.centerMode === "history"
                            ? Theme.text : Theme.textMuted
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Theme.fontWeightMedium
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
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

                Text {
                    visible: !!(root.service && root.service.historyModel.count > 0)
                    text: "Clear history"
                    color: textClearMouse.containsMouse ? Theme.text : Theme.textMuted
                    font.family: Theme.fontFamilyProse
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Theme.fontWeightMedium

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
                                timestampLabel: activeDelegate.timestamp > 0
                                    ? Qt.formatTime(new Date(activeDelegate.timestamp), "HH:mm")
                                    : ""
                                showArchive: false
                                onDismissed: root.service.dismissAt(activeDelegate.index, activeDelegate.originalId, activeDelegate.timestamp)
                                onActivated: root.service.invokeDefault(activeDelegate.index, activeDelegate.originalId, activeDelegate.timestamp)
                                onDefaultActionInvoked: root.service.invokeDefault(activeDelegate.index, activeDelegate.originalId, activeDelegate.timestamp)
                                onActionInvoked: function(identifier) { root.service.invokeAction(activeDelegate.index, identifier, activeDelegate.originalId, activeDelegate.timestamp) }
                                onArchiveRequested: root.service.archiveByIdentity(activeDelegate.originalId, activeDelegate.timestamp)
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
                            width: historyList.width
                            height: historyRow.implicitHeight

                            NotificationToast {
                                id: historyRow
                                anchors.fill: parent
                                app: String(historyDelegate.app || "")
                                appIcon: String(historyDelegate.appIcon || "")
                                desktopEntry: String(historyDelegate.desktopEntry || "")
                                summary: String(historyDelegate.summary || "")
                                body: String(historyDelegate.body || "")
                                image: String(historyDelegate.image || "")
                                glyph: String(historyDelegate.glyph || "")
                                execArgv: String(historyDelegate.execArgv || "")
                                actions: historyDelegate.actions || []
                                defaultActionText: String(historyDelegate.defaultActionText || "")
                                urgency: historyDelegate.urgency
                                interactive: false
                                showDismiss: false
                                onDefaultActionInvoked: root.service.invokeHistoryDefault(historyDelegate.index)
                                onActionInvoked: function(identifier) { root.service.invokeHistoryAction(historyDelegate.index, identifier) }
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
                        width: 24
                        height: 24
                        name: root.service && root.service.centerMode === "history"
                            ? "document-open-recent"
                            : "notifications"
                        iconSize: 24
                        tint: Theme.accent
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.service && root.service.centerMode === "history"
                            ? "No saved notifications"
                            : "You’re all caught up"
                        color: Theme.text
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Theme.fontWeightBold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.service && root.service.centerMode === "history"
                            ? "History will appear here after a notification is dismissed."
                            : "New alerts will appear here automatically."
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
