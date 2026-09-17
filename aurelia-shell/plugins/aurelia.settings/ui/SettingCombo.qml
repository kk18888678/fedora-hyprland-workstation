import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "."

// Combo (enum) row.
RowLayout {
    id: root

    property var descriptor: ({})
    property string optionId: descriptor ? String(descriptor.id || "") : ""
    property string effective: descriptor ? String(descriptor.effective || "") : ""
    property var enumOptions: descriptor && descriptor.enumOptions ? descriptor.enumOptions : []
    property string actionId: descriptor ? String(descriptor.actionId || "") : ""

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

    ComboControl {
        id: combo
        Layout.alignment: Qt.AlignVCenter
        Layout.minimumWidth: 190
        model: root.enumOptions
        textRole: "label"
        valueRole: "value"
        currentIndex: {
            var index = -1
            var target = String(root.effective)
            for (var i = 0; i < root.enumOptions.length; i++) {
                if (String(root.enumOptions[i].value) === target) { index = i; break }
            }
            return index
        }
        onActivated: function(index) {
            root.changed(root.enumOptions[index].value)
        }
    }
}
