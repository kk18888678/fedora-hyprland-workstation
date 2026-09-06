import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../../theme"

Item {
    id: root

    property var bar: null
    property var shell: null
    property string moduleName: "aurelia.workspaces"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null

    implicitWidth: workspaceRow.implicitWidth
    implicitHeight: bar ? bar.barSize : 32

    RowLayout {
        id: workspaceRow
        anchors.centerIn: parent
        spacing: Theme.spacingXs

        Repeater {
            model: Hyprland.workspaces

            delegate: Rectangle {
                required property HyprlandWorkspace modelData
                Layout.preferredWidth: Math.max(24, workspaceLabel.implicitWidth + Theme.spacingSm * 2)
                Layout.preferredHeight: Math.max(24, root.bar ? root.bar.barSize - 6 : 26)
                radius: Theme.radiusSm
                color: modelData.focused ? Theme.accent : (workspaceHover.hovered ? Theme.selection : Theme.surface)

                Text {
                    id: workspaceLabel
                    anchors.centerIn: parent
                    text: String(modelData.id)
                    color: modelData.focused ? Theme.bgBase : Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: modelData.focused ? Theme.fontWeightBold : Theme.fontWeightMedium
                }

                HoverHandler { id: workspaceHover }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        mouse.accepted = true
                        modelData.activate()
                    }
                }
            }
        }
    }
}
