import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"

// Toggle row: title + description on the left, switch on the right.
RowLayout {
    id: root

    property var descriptor: ({})
    property string optionId: descriptor ? String(descriptor.id || "") : ""
    property bool effective: descriptor && descriptor.effective === true

    signal changed(var value)

    width: parent ? parent.width : 0
    Layout.fillWidth: true
    spacing: Theme.spacingLg

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 2

        Text {
            Layout.fillWidth: true
            text: descriptor.title || ""
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMd
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            text: descriptor.description || ""
            color: Theme.textMuted
            font.family: Theme.fontFamilyProse
            font.pixelSize: Theme.fontSizeXs
            wrapMode: Text.WordWrap
            visible: text !== ""
        }
    }

    Switch {
        id: switchControl
        Layout.alignment: Qt.AlignVCenter
        checked: root.effective
        onToggled: root.changed(checked)
    }
}
