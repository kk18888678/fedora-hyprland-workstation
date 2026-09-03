import QtQuick
import QtQuick.Layouts
import "../../theme"

Rectangle {
    id: rowRoot

    required property var modelData
    required property bool isSelected

    width: ListView.view ? ListView.view.width : 640
    height: 44
    radius: Theme.radiusSm
    color: isSelected ? Theme.selectionActive : "transparent"

    border.color: isSelected ? Theme.borderActive : "transparent"
    border.width: 1

    Behavior on color {
        ColorAnimation { duration: 80 }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingMd
        anchors.rightMargin: Theme.spacingMd
        spacing: Theme.spacingMd

        // Hotkey badge pill (left)
        Rectangle {
            id: keyBadge
            Layout.preferredWidth: 190
            Layout.preferredHeight: 28
            radius: Theme.radiusSm
            color: rowRoot.isSelected ? Theme.surface : Theme.overlay
            border.color: rowRoot.isSelected ? Theme.accent : Theme.highlight
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: rowRoot.modelData.display_key || "None (Unbound)"
                color: (rowRoot.modelData.display_key && rowRoot.modelData.display_key !== "None (Unbound)")
                    ? Theme.gold
                    : Theme.textSubtle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.bold: true
                elide: Text.ElideRight
            }
        }

        // Action / Application title (right)
        Text {
            Layout.fillWidth: true
            text: rowRoot.modelData.description || ""
            color: rowRoot.isSelected ? Theme.text : Theme.textMuted
            font.family: Theme.fontFamilyProse
            font.pixelSize: Theme.fontSizeMd
            font.bold: rowRoot.isSelected
            elide: Text.ElideRight
        }
    }
}
