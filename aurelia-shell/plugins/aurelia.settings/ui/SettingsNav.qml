import QtQuick
import QtQuick.Layouts
import "../../../theme"

// Left-hand section navigation for the Settings hub.
Item {
    id: root

    property var sections: []
    property string activeId: ""
    signal selectSection(string sectionId)

    ColumnLayout {
        anchors.fill: parent
        spacing: 2

        Repeater {
            model: root.sections

            delegate: Rectangle {
                required property var modelData
                id: sectionItem

                Layout.fillWidth: true
                Layout.preferredHeight: 38
                radius: Theme.radiusMd
                color: modelData.id === root.activeId ? Theme.selection : "transparent"
                clip: true

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    width: 3
                    height: 18
                    radius: 2
                    color: modelData.id === root.activeId ? Theme.accent : "transparent"
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    text: modelData.name
                    color: modelData.id === root.activeId ? Theme.text : Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: modelData.id === root.activeId ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                    width: parent.width - 28
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.selectSection(modelData.id)
                    onEntered: if (modelData.id !== root.activeId) parent.color = Theme.selectionHover
                    onExited: if (modelData.id !== root.activeId) parent.color = "transparent"
                }
            }
        }
    }
}
