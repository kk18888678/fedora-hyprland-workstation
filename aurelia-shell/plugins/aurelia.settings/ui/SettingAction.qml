import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "."

// Action row: labeled button that forwards a bounded CLI/IPC action.
RowLayout {
    id: root

    property var descriptor: ({})
    property string title: descriptor ? String(descriptor.title || "") : ""
    property string description: descriptor ? String(descriptor.description || "") : ""
    property string label: descriptor ? String(descriptor.label || "Run") : "Run"

    signal action()

    width: parent ? parent.width : 0
    Layout.fillWidth: true
    spacing: Theme.spacingLg

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 2

        Text {
            Layout.fillWidth: true
            text: root.title
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMd
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            text: root.description
            color: Theme.textMuted
            font.family: Theme.fontFamilyProse
            font.pixelSize: Theme.fontSizeXs
            wrapMode: Text.WordWrap
            visible: text !== ""
        }
    }

    SettingButton {
        Layout.rightMargin: Theme.spacingSm
        Layout.alignment: Qt.AlignVCenter
        label: root.label
        primary: !!descriptor && descriptor.primary === true
        onClicked: root.action()
    }
}
