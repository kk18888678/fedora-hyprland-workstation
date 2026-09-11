import QtQuick
import QtQuick.Layouts
import "../../ui"
import "../../theme"

// A row receives a primitives-only snapshot. The panel resolves the live
// BlueZ object again at activation time, so discovery churn cannot leave a
// delegate holding a dangling QObject wrapper.
Rectangle {
    id: root

    property var dev: null
    property int rowIndex: 0
    property string sectionName: ""
    property bool isDiscovered: false
    property string pendingAction: ""
    property bool rowSelected: false
    property bool actionFocused: false
    property color hoverFill: Theme.selectionHover
    property color selectedFill: Theme.selectionActive

    signal activated()
    signal secondaryActivated()
    signal forgetRequested()
    signal cursorEntered()
    signal forgetHovered(bool hovered)

    readonly property bool isConnected: !!(dev && dev.connected)
    readonly property int devState: dev && dev.state !== undefined ? dev.state : -1
    readonly property bool forgetAvailable: !isDiscovered &&
        (sectionName === "known" || sectionName === "connected")
    readonly property string actionTooltip: isConnected
        ? "Disconnect"
        : (isDiscovered ? "Pair" : "Connect")
    readonly property string statusText: {
        if (!dev) return ""
        if (pendingAction === "forgetting") return "Forgetting…"
        if (pendingAction === "disconnecting" || devState === 2) return "Disconnecting…"
        if (isConnected) {
            if (dev.batteryAvailable) return Math.round(Number(dev.battery) * 100) + "%"
            return sectionName === "connected" ? "" : "Connected"
        }
        if (pendingAction === "connecting" || devState === 3 || dev.pairing === true)
            return "Connecting…"
        return isDiscovered ? "Available" : ""
    }

    readonly property color statusColor: isConnected || pendingAction !== ""
        ? Theme.text
        : Theme.textSecondary

    implicitHeight: Math.max(44, rowContent.implicitHeight + Theme.spacingSm * 2)
    radius: Theme.radiusSm
    color: root.rowSelected
        ? root.selectedFill
        : (rowHover.hovered ? root.hoverFill : Theme.surface)
    border.color: root.rowSelected ? Theme.borderActive : Theme.border
    border.width: root.rowSelected ? Theme.borderWidthDefault : 0

    HoverHandler {
        id: rowHover
        onHoveredChanged: if (hovered) root.cursorEntered()
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        z: 0
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.dev ? Qt.PointingHandCursor : Qt.ArrowCursor
        onContainsMouseChanged: if (containsMouse) root.cursorEntered()
        onClicked: function(mouse) {
            mouse.accepted = true
            if (mouse.button === Qt.RightButton) root.secondaryActivated()
            else root.activated()
        }
    }

    RowLayout {
        id: rowContent
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingSm
        anchors.rightMargin: Theme.spacingSm
        spacing: Theme.spacingSm
        z: 1

        AureliaIcon {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            name: root.isConnected ? "bluetooth-active" : "bluetooth"
            iconSize: 20
            tint: root.statusColor
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: root.dev ? (root.dev.deviceName || root.dev.name || "Device") : "Device"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: Theme.fontWeightMedium
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: root.statusText !== ""
                text: root.statusText
                color: root.statusColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                elide: Text.ElideRight
            }
        }

        Item {
            id: forgetHost
            Layout.preferredWidth: forgetButton.implicitWidth
            Layout.preferredHeight: forgetButton.implicitHeight
            visible: root.forgetAvailable && (rowHover.hovered || root.rowSelected)
            z: 2

            HoverHandler {
                onHoveredChanged: root.forgetHovered(hovered)
            }

            AureliaIconButton {
                id: forgetButton
                anchors.fill: parent
                icon: "user-trash"
                tooltip: "Forget"
                active: root.actionFocused && root.rowSelected
                destructive: true
                enabled: root.pendingAction !== "forgetting"
                onTriggered: root.forgetRequested()
            }
        }
    }

    AureliaToolTip {
        triggerItem: root
        bar: null
        hovered: rowHover.hovered && !root.actionFocused
        text: root.actionTooltip
    }
}
