import QtQuick
import QtQuick.Layouts
import "../../theme"

Rectangle {
    id: rowRoot

    required property var modelData
    required property int index
    required property bool isSelected

    width: ListView.view ? ListView.view.width : (Theme.paletteWidth - Theme.spacingXl * 2)
    height: Theme.rowHeight
    radius: Theme.radiusSm
    color: isSelected ? Theme.selection : "transparent"

    // Understated horizontal highlight without box borders or card elevation
    border.width: 0

    function formattedShortcut(): string {
        if (typeof windowRoot !== "undefined" && windowRoot.isRecording && windowRoot.recordingItem && rowRoot.modelData && windowRoot.recordingItem.id === rowRoot.modelData.id) {
            return "[ Press keys... ]"
        }
        var key = rowRoot.modelData ? (rowRoot.modelData.display_key || "") : ""
        if (!key || key === "None (Unbound)") {
            return "—"
        }
        if (key.endsWith(".desktop")) {
            return key
        }
        return key.toUpperCase()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingXl
        anchors.rightMargin: Theme.spacingXl
        spacing: Theme.spacingLg

        // Column 1: Shortcut (stable width across every row)
        Text {
            Layout.preferredWidth: Theme.colShortcutWidth
            Layout.alignment: Qt.AlignVCenter
            text: rowRoot.formattedShortcut()
            color: rowRoot.isSelected ? Theme.accent : Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.weight: rowRoot.isSelected ? Theme.fontWeightMedium : Theme.fontWeightNormal
            elide: Text.ElideRight
        }

        // Column separator arrow (clearly visible, theme accent on selection)
        Text {
            Layout.preferredWidth: Theme.colSeparatorWidth
            Layout.alignment: Qt.AlignVCenter
            text: "→"
            color: rowRoot.isSelected ? Theme.accent : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.weight: rowRoot.isSelected ? Theme.fontWeightMedium : Theme.fontWeightNormal
        }

        // Column 2: Action / Application title (starts at identical horizontal position)
        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
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
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: {
            if (typeof keybindingsModel !== "undefined" && keybindingsModel.selectedIndex !== rowRoot.index) {
                keybindingsModel.selectedIndex = rowRoot.index
            }
        }
        onClicked: {
            if (typeof keybindingsModel !== "undefined") {
                console.info("[EVENT] keybindings.input.mouse_click index=" + rowRoot.index + " view=" + keybindingsModel.activeView)
                keybindingsModel.selectedIndex = rowRoot.index
                if (ListView.view) {
                    ListView.view.forceActiveFocus()
                }
                if (keybindingsModel.activeView === "add_action_type") {
                    if (typeof windowRoot !== "undefined" && typeof windowRoot.activateSelected === "function") {
                        windowRoot.activateSelected()
                    }
                }
            }
        }
        onDoubleClicked: {
            if (typeof keybindingsModel !== "undefined") {
                console.info("[EVENT] keybindings.input.mouse_double_click index=" + rowRoot.index + " view=" + keybindingsModel.activeView)
                keybindingsModel.selectedIndex = rowRoot.index
                if (ListView.view) {
                    ListView.view.forceActiveFocus()
                }
                if (keybindingsModel.activeView === "add_action_type") {
                    return
                }
                if (typeof windowRoot !== "undefined" && typeof windowRoot.activateSelected === "function") {
                    windowRoot.activateSelected()
                }
            }
        }
    }
}
