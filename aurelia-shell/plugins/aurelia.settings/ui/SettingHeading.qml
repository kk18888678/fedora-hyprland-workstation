import QtQuick
import QtQuick.Layouts
import "../../../theme"

// Section heading separator inside a page.
Item {
    id: root

    property string title: ""
    property var descriptor: ({})

    width: parent ? parent.width : 0
    Layout.fillWidth: true
    Layout.preferredHeight: 34
    Layout.topMargin: Theme.spacingLg

    Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        text: root.title || (root.descriptor && root.descriptor.title ? root.descriptor.title : "")
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
    }
}
