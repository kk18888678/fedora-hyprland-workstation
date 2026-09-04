import QtQuick
import QtQuick.Layouts
import "../../theme"

Rectangle {
    id: rowRoot

    required property var modelData
    required property int index
    required property bool isSelected

    width: ListView.view ? ListView.view.width : 600
    height: 34
    radius: 4
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
        return key.toUpperCase()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 0

        // Column 1: Shortcut (stable width across every row)
        Text {
            Layout.preferredWidth: 200
            Layout.alignment: Qt.AlignVCenter
            text: rowRoot.formattedShortcut()
            color: rowRoot.isSelected ? Theme.accent : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.weight: rowRoot.isSelected ? Font.Medium : Font.Normal
            elide: Text.ElideRight
        }

        // Column separator arrow (subtle, fixed position)
        Text {
            Layout.preferredWidth: 28
            Layout.alignment: Qt.AlignVCenter
            text: "→"
            color: Theme.textSubtle
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }

        // Column 2: Action / Application title (starts at identical horizontal position)
        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: rowRoot.modelData ? (rowRoot.modelData.description || "") : ""
            color: rowRoot.isSelected ? Theme.text : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.weight: rowRoot.isSelected ? Font.Medium : Font.Normal
            elide: Text.ElideRight
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: {
            if (typeof hotkeysModel !== "undefined") {
                hotkeysModel.selectedIndex = rowRoot.index
            }
        }
        onClicked: {
            if (typeof hotkeysModel !== "undefined") {
                hotkeysModel.selectedIndex = rowRoot.index
                if (hotkeysModel.selectedItem && hotkeysModel.selectedItem.runnable) {
                    if (hotkeysModel.runSelected() && typeof windowRoot !== "undefined") {
                        windowRoot.visible = false
                    }
                }
            }
        }
    }
}
