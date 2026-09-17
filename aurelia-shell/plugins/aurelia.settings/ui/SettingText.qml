import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "."

// Plain text entry row (e.g. keyboard layout).
RowLayout {
    id: root

    property var descriptor: ({})
    property string optionId: descriptor ? String(descriptor.id || "") : ""
    property string effective: descriptor ? String(descriptor.effective || "") : ""

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
            color: Theme.textSecondary
            font.family: Theme.fontFamilyProse
            font.pixelSize: Theme.fontSizeXs
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            visible: text !== ""
        }
    }

    TextControl {
        Layout.alignment: Qt.AlignVCenter
        Layout.minimumWidth: 170
        text: root.effective
        onAccepted: root.changed(text.trim())
    }
}
