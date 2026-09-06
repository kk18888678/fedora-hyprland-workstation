import QtQuick
import QtQuick.Layouts
import "../../../theme"

// The Add Action picker is a separate surface from the shortcut/application
// list. Its only job is to present type choices and translate a claimed input
// gesture into the Window controller's authoritative activation method.
Item {
    id: pickerRoot

    required property var modelController
    required property var windowController
    readonly property bool pickerVisible: modelController.activeView === "add_action_type"

    visible: pickerVisible
    focus: pickerVisible

    function focusPicker() {
        pickerRoot.forceActiveFocus()
    }

    Keys.onPressed: function(event) {
        if (!pickerRoot.pickerVisible) return
        if (windowController.isRecording) {
            windowController.handleRecordingKeyPress(event)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)) {
            windowController.cycleTopLevelView(true)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
            windowController.cycleTopLevelView(false)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Down) {
            modelController.selectNext()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Up) {
            modelController.selectPrevious()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            event.accepted = true
            if (!windowController.claimActivationKey(event)) return
            windowController.activateSelected("keyboard")
            return
        }
        if (windowController.handleComponentKey(event, "list")) return
        if (event.key === Qt.Key_Slash || event.key === Qt.Key_Backspace || (event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))) {
            event.accepted = true
            windowController.beginSearch(event.key === Qt.Key_Slash ? "" : event.text)
        }
    }

    Keys.onReleased: function(event) {
        if (windowController.handleActivationKeyRelease(event)) return
        if (windowController.isRecording) {
            windowController.handleRecordingKeyRelease(event)
            event.accepted = true
        }
    }

    function indexForKind(kind): int {
        var items = pickerRoot.modelController.filteredItems || []
        for (var i = 0; i < items.length; i++) {
            if (items[i].action_type_kind === kind) return i
        }
        return -1
    }

    function chooseKind(kind) {
        var index = indexForKind(kind)
        if (index < 0) return
        modelController.selectedIndex = index
        windowController.activateSelected("mouse")
    }

    ColumnLayout {
        id: actionTypeColumn
        anchors.fill: parent
        anchors.margins: Theme.spacingXl
        spacing: Theme.spacingSm

        Text {
            Layout.fillWidth: true
            text: "Add an action"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLg
            font.weight: Theme.fontWeightBold
        }

        Text {
            Layout.fillWidth: true
            text: "Choose how this shortcut should launch."
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacingLg

            KeybindingsActionTypeCard {
                kind: "application"
                title: "Application"
                subtitle: "Choose an installed desktop application and add it to your shortcuts."
                glyph: "▦"
                selected: pickerRoot.modelController.selectedIndex === pickerRoot.indexForKind("application")
                modelController: pickerRoot.modelController
                windowController: pickerRoot.windowController
                onChosen: pickerRoot.chooseKind("application")
            }

            KeybindingsActionTypeCard {
                kind: "executable"
                title: "Executable / Script"
                subtitle: "Register a trusted executable with an explicit path and arguments."
                glyph: "⌁"
                selected: pickerRoot.modelController.selectedIndex === pickerRoot.indexForKind("executable")
                modelController: pickerRoot.modelController
                windowController: pickerRoot.windowController
                onChosen: pickerRoot.chooseKind("executable")
            }
        }

        Item { Layout.fillHeight: true }
    }

    Text {
        anchors.centerIn: parent
        text: "No action types available"
        color: Theme.textSubtle
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        visible: pickerRoot.modelController.filteredItems.length === 0
    }
}
