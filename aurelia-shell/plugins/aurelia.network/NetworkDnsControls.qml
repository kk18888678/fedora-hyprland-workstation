import QtQuick
import QtQuick.Controls
import "../../theme"

// DNS provider controls kept separate from the network coordinator so the
// provider row stays compact while action/error state remains visible.
Item {
    id: root

    property var panelRoot: null
    readonly property var providers: panelRoot ? panelRoot.dnsProviders : ["DHCP", "Cloudflare", "Google", "Custom"]

    implicitHeight: dnsColumn.implicitHeight

    Column {
        id: dnsColumn
        width: parent.width
        spacing: Theme.spacingSm

        Text {
            text: "DNS PROVIDER"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            font.weight: Theme.fontWeightBold
        }

        Text {
            width: parent.width
            text: "SERVERS  " + (root.panelRoot ? root.panelRoot.dnsServers : "DHCP")
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            visible: !!root.panelRoot && (root.panelRoot.dnsError !== "" || root.panelRoot.pendingDnsProvider !== "")
            text: root.panelRoot && root.panelRoot.dnsError !== ""
                ? root.panelRoot.dnsError
                : "Applying " + (root.panelRoot ? root.panelRoot.pendingDnsProvider : "") + " DNS…"
            color: root.panelRoot && root.panelRoot.dnsError !== "" ? Theme.error : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Row {
            width: parent.width
            spacing: Theme.spacingXs

            Repeater {
                model: root.providers
                delegate: Rectangle {
                    required property string modelData
                    required property int index
                    width: (parent.width - Theme.spacingXs * 3) / 4
                    height: 32
                    radius: Theme.radiusSm
                    color: root.panelRoot && root.panelRoot.dnsProvider === modelData
                        ? Theme.selection
                        : (dnsHover.hovered ? Theme.selectionHover : Theme.surface)
                    border.color: root.panelRoot && root.panelRoot.cursorActive &&
                        root.panelRoot.focusSection === "dns" && root.panelRoot.dnsIndex === index
                        ? Theme.borderActive : Theme.border
                    border.width: Theme.borderWidthDefault

                    HoverHandler { id: dnsHover }

                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: dnsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: if (containsMouse && root.panelRoot) {
                            root.panelRoot.cursorActive = true
                            root.panelRoot.focusSection = "dns"
                            root.panelRoot.dnsIndex = index
                        }
                        onClicked: if (root.panelRoot) root.panelRoot.setDns(modelData)
                    }

                    ToolTip.visible: dnsMouse.containsMouse
                    ToolTip.text: modelData === "Custom" ? "Set custom DNS servers" : "Use " + modelData + " DNS"
                    ToolTip.delay: 400
                }
            }
        }
    }
}
