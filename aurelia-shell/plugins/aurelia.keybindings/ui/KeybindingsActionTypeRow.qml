import QtQuick
import QtQuick.Layouts
import "../../../theme"

// Dedicated Add Action type row. It is intentionally not a ListView delegate:
// selecting a type replaces the entire picker surface, so this row claims the
// pointer gesture before the model transition can destroy its parent.
Rectangle {
    id: rowRoot

    required property var modelData
    required property int index
    required property bool isSelected
    required property var modelController
    required property var windowController

    width: parent ? parent.width : KeybindingsConfig.palettePreferredWidth
    height: KeybindingsConfig.rowHeight
    Layout.fillWidth: true
    Layout.preferredHeight: KeybindingsConfig.rowHeight
    radius: KeybindingsConfig.rowRadius
    color: isSelected ? Theme.selection : "transparent"

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: KeybindingsConfig.rowPaddingHorizontal
        anchors.rightMargin: KeybindingsConfig.rowPaddingHorizontal
        spacing: Theme.spacingXl

        Text {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: 0
            text: rowRoot.modelData ? (rowRoot.modelData.display_key || "") : ""
            color: rowRoot.isSelected ? Theme.accent : Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.weight: rowRoot.isSelected ? Theme.fontWeightMedium : Theme.fontWeightNormal
            elide: Text.ElideRight
        }

        Text {
            Layout.preferredWidth: KeybindingsConfig.separatorColumnWidth
            text: "→"
            color: rowRoot.isSelected ? Theme.accent : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: 0
            text: rowRoot.modelData ? (rowRoot.modelData.description || "") : ""
            color: rowRoot.isSelected ? Theme.text : Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.weight: rowRoot.isSelected ? Theme.fontWeightMedium : Theme.fontWeightNormal
            elide: Text.ElideRight
        }
    }

    MouseArea {
        anchors.fill: parent
        preventStealing: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor

        onEntered: {
            rowRoot.modelController.selectedIndex = rowRoot.index
        }

        onPressed: function(mouse) {
            mouse.accepted = true
        }

        onReleased: function(mouse) {
            mouse.accepted = true
        }

        onClicked: function(mouse) {
            mouse.accepted = true
            var viewAtClick = rowRoot.modelController.activeView
            rowRoot.modelController.selectedIndex = rowRoot.index
            console.info("[EVENT] keybindings.add_action_type.click index=" + rowRoot.index + " view=" + viewAtClick)
            if (viewAtClick === "add_action_type") rowRoot.windowController.activateSelected("mouse")
        }
    }
}
