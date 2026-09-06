import QtQuick
import QtQuick.Layouts
import "../../../theme"

Rectangle {
    id: rowRoot

    required property var modelData
    required property int index
    required property bool isSelected
    // The row is intentionally explicit about its controllers.  Relying on
    // ids from the instantiating Window makes delegate event ownership
    // dependent on creation-context lookup and is especially fragile when a
    // model change destroys the pressed delegate.
    required property var modelController
    required property var windowController
    // Compatibility names keep the row's local behavior readable while the
    // actual dependencies remain explicit and unambiguous at the boundary.
    readonly property var keybindingsModel: modelController
    readonly property var windowRoot: windowController

    width: ListView.view ? ListView.view.width : (KeybindingsConfig.palettePreferredWidth - KeybindingsConfig.rowPaddingHorizontal * 2)
    height: KeybindingsConfig.rowHeight
    radius: KeybindingsConfig.rowRadius
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
        anchors.leftMargin: KeybindingsConfig.rowPaddingHorizontal
        anchors.rightMargin: KeybindingsConfig.rowPaddingHorizontal
        spacing: Theme.spacingLg

        // Column 1: Shortcut (stable width across every row)
        Text {
            Layout.preferredWidth: KeybindingsConfig.shortcutColumnWidth
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
            Layout.preferredWidth: KeybindingsConfig.separatorColumnWidth
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
        preventStealing: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onEntered: {
            if (keybindingsModel && keybindingsModel.selectedIndex !== rowRoot.index) {
                keybindingsModel.selectedIndex = rowRoot.index
            }
        }
        onPressed: function(mouse) {
            // Claim the pointer event before any synchronous model transition.
            // Without this, destroying the delegate during onClicked can leave
            // the full-screen dismissal surface eligible for the same gesture.
            mouse.accepted = true
        }
        onReleased: function(mouse) {
            mouse.accepted = true
        }
        onClicked: function(mouse) {
            mouse.accepted = true
            var viewAtClick = keybindingsModel.activeView
            console.info("[EVENT] keybindings.input.mouse_click index=" + rowRoot.index + " view=" + viewAtClick)
            keybindingsModel.selectedIndex = rowRoot.index
            if (ListView.view) {
                ListView.view.forceActiveFocus()
            }
            // A type-picker click owns exactly one navigation gesture. The
            // destination view only receives later explicit input.
            if (viewAtClick === "add_action_type" && windowRoot && typeof windowRoot.activateSelected === "function") {
                windowRoot.activateSelected("mouse")
            }
        }
    }
}
