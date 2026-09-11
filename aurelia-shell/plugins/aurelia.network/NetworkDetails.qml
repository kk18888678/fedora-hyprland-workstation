import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"

// Detail grid matching Omarchy's stable rows: late probes render as --,
// totals remain visible, and address values are explicitly copyable.
Item {
    id: root

    property var panelRoot: null
    readonly property bool ready: !!panelRoot && !!panelRoot.info.iface

    visible: ready
    implicitHeight: ready ? detailsGrid.implicitHeight : 0

    GridLayout {
        id: detailsGrid
        width: parent.width
        columns: 4
        columnSpacing: Theme.spacingSm
        rowSpacing: Theme.spacingXs

        DetailLabel { text: "Ping" }
        DetailValue { text: root.panelRoot ? root.panelRoot.formatPing(root.panelRoot.internetPingLatency) : "--" }
        DetailLabel { text: "Packet Loss" }
        DetailValue {
            text: root.panelRoot ? root.panelRoot.formatLoss(root.panelRoot.internetPingPacketLoss) : "--"
            valueColor: root.panelRoot && root.panelRoot.internetPingPacketLoss > 0 ? Theme.warning : Theme.textSecondary
        }

        DetailLabel { text: "Receiving" }
        DetailValue { text: root.panelRoot && root.panelRoot.hasTransferStats ? root.panelRoot.formatRate(root.panelRoot.downloadRate) : "--" }
        DetailLabel { text: "Sending" }
        DetailValue { text: root.panelRoot && root.panelRoot.hasTransferStats ? root.panelRoot.formatRate(root.panelRoot.uploadRate) : "--" }

        DetailLabel { text: "Downloaded" }
        DetailValue { text: root.panelRoot && root.panelRoot.hasTransferStats ? root.panelRoot.formatBytes(root.panelRoot.info.rx_bytes) : "--" }
        DetailLabel { text: "Uploaded" }
        DetailValue { text: root.panelRoot && root.panelRoot.hasTransferStats ? root.panelRoot.formatBytes(root.panelRoot.info.tx_bytes) : "--" }

        DetailLabel { text: "IP Address" }
        DetailValue {
            text: root.panelRoot ? (root.panelRoot.info.ip || "--") : "--"
            copyable: !!(root.panelRoot && root.panelRoot.info.ip)
            tooltipText: "Copy IP address"
        }
        DetailLabel { text: "Gateway" }
        DetailValue {
            text: root.panelRoot ? (root.panelRoot.info.gateway || "--") : "--"
            copyable: !!(root.panelRoot && root.panelRoot.info.gateway)
            tooltipText: "Copy gateway"
        }
    }

    component DetailLabel: Text {
        color: Theme.textMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeXs
    }

    component DetailValue: Text {
        property bool copyable: false
        property color valueColor: Theme.textSecondary
        property string tooltipText: "Copy value"

        Layout.fillWidth: true
        color: valueColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeXs
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft

        MouseArea {
            id: valueMouse
            anchors.fill: parent
            enabled: parent.copyable && parent.text !== ""
            hoverEnabled: enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (root.panelRoot) root.panelRoot.copyToClipboard(parent.text)
        }

        ToolTip.visible: valueMouse.containsMouse && valueMouse.enabled
        ToolTip.text: tooltipText
        ToolTip.delay: 400
    }
}
