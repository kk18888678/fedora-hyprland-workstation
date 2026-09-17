import QtQuick
import QtQuick.Layouts
import "../../../theme"

// Read-only information row (path, status, recovery hints).
RowLayout {
    id: root

    property var descriptor: ({})
    property string title: descriptor ? String(descriptor.title || "") : ""
    property string value: descriptor ? String(descriptor.value || "") : ""
    property string description: descriptor ? String(descriptor.description || "") : ""

    width: parent ? parent.width : 0
    Layout.fillWidth: true
    spacing: Theme.spacingLg

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

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
                text: root.value
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                elide: Text.ElideRight
                Layout.maximumWidth: 420
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.description
            color: Theme.textMuted
            font.family: Theme.fontFamilyProse
            font.pixelSize: Theme.fontSizeXs
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            visible: text !== ""
        }
    }
}
