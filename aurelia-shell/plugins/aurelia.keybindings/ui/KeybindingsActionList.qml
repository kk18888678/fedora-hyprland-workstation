import QtQuick
import QtQuick.Controls
import "."
import "../../../theme"

// List presentation and list-context keyboard routing. The model and Window
// controller are passed explicitly so delegate creation does not depend on
// implicit ids from a monolithic parent component.
Item {
    id: actionListRoot

    required property var modelController
    required property var windowController
    property alias listView: listView

    readonly property bool listVisible: modelController.activeView !== "add_action_type" && modelController.activeView !== "add_exec" && modelController.activeView !== "settings"
    visible: listVisible

    function focusList() {
        listView.forceActiveFocus()
    }

    ListView {
        id: listView
        anchors.fill: parent
        spacing: Theme.rowSpacing
        clip: true
        model: actionListRoot.modelController.filteredItems
        currentIndex: actionListRoot.modelController.selectedIndex
        focus: true

        delegate: KeybindingRow {
            isSelected: index === actionListRoot.modelController.selectedIndex
            modelController: actionListRoot.modelController
            windowController: actionListRoot.windowController
        }

        Keys.onReleased: function(event) {
            if (actionListRoot.windowController.handleActivationKeyRelease(event)) {
                return
            }
            if (actionListRoot.windowController.isRecording) {
                actionListRoot.windowController.handleRecordingKeyRelease(event)
                event.accepted = true
            }
        }

        Keys.onPressed: function(event) {
            if (actionListRoot.windowController.isRecording) {
                actionListRoot.windowController.handleRecordingKeyPress(event)
                event.accepted = true
                return
            }

            if (actionListRoot.modelController.operationState === "conflict" || actionListRoot.modelController.operationState === "error" || actionListRoot.modelController.operationState === "success") {
                if (event.key === Qt.Key_Escape) {
                    actionListRoot.windowController.cancelCapture()
                    event.accepted = true
                    return
                }
            }

            if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)) {
                actionListRoot.windowController.cycleTopLevelView(true)
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                actionListRoot.windowController.cycleTopLevelView(false)
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_Escape) {
                actionListRoot.windowController.goBack()
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_Down) {
                actionListRoot.modelController.selectNext()
                listView.positionViewAtIndex(actionListRoot.modelController.selectedIndex, ListView.Contain)
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_Up) {
                if (actionListRoot.modelController.selectedIndex === 0) {
                    actionListRoot.windowController.focusSearch()
                } else {
                    actionListRoot.modelController.selectPrevious()
                    listView.positionViewAtIndex(actionListRoot.modelController.selectedIndex, ListView.Contain)
                }
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                event.accepted = true
                if (!actionListRoot.windowController.claimActivationKey(event)) {
                    return
                }
                console.info("[EVENT] keybindings.input.enter target=listView activeView=" + actionListRoot.modelController.activeView)
                actionListRoot.windowController.activateSelected("keyboard")
                return
            }

            if (actionListRoot.windowController.handleComponentKey(event, "list")) {
                return
            }

            if (event.key === Qt.Key_Slash || event.key === Qt.Key_Backspace || (event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))) {
                actionListRoot.windowController.focusSearch()
                if (event.key !== Qt.Key_Slash) {
                    actionListRoot.windowController.appendSearchText(event.text)
                }
                event.accepted = true
            }
        }

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            width: Theme.scrollBarWidth
            contentItem: Rectangle {
                color: Theme.selection
                radius: Theme.radiusSm / 2
            }
        }
    }

    Text {
        anchors.centerIn: parent
        text: (actionListRoot.modelController.activeView === "add_app") ? (actionListRoot.modelController.isLoadingApps ? "Discovering installed applications..." : "No matching applications found") : (actionListRoot.modelController.activeView === "unbound" ? ("No unbound shortcuts (press " + Theme.shortcutAddAction + " to add an action)") : "No matching shortcuts")
        color: Theme.textSubtle
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        visible: actionListRoot.modelController.filteredItems.length === 0 && (actionListRoot.modelController.activeView === "bound" || actionListRoot.modelController.activeView === "unbound" || actionListRoot.modelController.activeView === "add_app")
    }
}
