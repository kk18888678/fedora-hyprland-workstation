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
            windowController.focusSearch()
            if (event.key !== Qt.Key_Slash) windowController.appendSearchText(event.text)
            event.accepted = true
        }
    }

    Keys.onReleased: function(event) {
        if (windowController.handleActivationKeyRelease(event)) return
        if (windowController.isRecording) {
            windowController.handleRecordingKeyRelease(event)
            event.accepted = true
        }
    }

    ColumnLayout {
        id: actionTypeColumn
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.spacingXl * 2, 680)
        spacing: Theme.spacingSm

        Text {
            Layout.fillWidth: true
            text: "Choose an action type"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            font.weight: Theme.fontWeightMedium
        }

        Repeater {
            model: pickerRoot.modelController.filteredItems

            delegate: KeybindingsActionTypeRow {
                width: actionTypeColumn.width
                modelController: pickerRoot.modelController
                windowController: pickerRoot.windowController
                isSelected: index === pickerRoot.modelController.selectedIndex
            }
        }
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
