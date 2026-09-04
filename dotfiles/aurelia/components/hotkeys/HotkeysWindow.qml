import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../../theme"

PanelWindow {
    id: windowRoot

    // Layer-shell Wayland configuration: centered overlay surface with on-demand focus
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // Window dimensions: restrained command palette proportions (640x460)
    implicitWidth: 640
    implicitHeight: 460
    color: "transparent"

    property bool isRecording: false
    property var recordingItem: null

    function formatKeyEvent(event): string {
        var k = event.key
        if (k === Qt.Key_Control || k === Qt.Key_Shift || k === Qt.Key_Alt || k === Qt.Key_Meta) {
            return ""
        }

        var parts = []
        if (event.modifiers & Qt.MetaModifier) parts.push("SUPER")
        if (event.modifiers & Qt.ControlModifier) parts.push("CTRL")
        if (event.modifiers & Qt.AltModifier) parts.push("ALT")
        if (event.modifiers & Qt.ShiftModifier) parts.push("SHIFT")

        var keyName = ""
        if (k >= Qt.Key_A && k <= Qt.Key_Z) {
            keyName = String.fromCharCode(k)
        } else if (k >= Qt.Key_0 && k <= Qt.Key_9) {
            keyName = String.fromCharCode(k)
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            keyName = "RETURN"
        } else if (k === Qt.Key_Space) {
            keyName = "SPACE"
        } else if (k === Qt.Key_Tab) {
            keyName = "TAB"
        } else if (k === Qt.Key_Left) {
            keyName = "LEFT"
        } else if (k === Qt.Key_Right) {
            keyName = "RIGHT"
        } else if (k === Qt.Key_Up) {
            keyName = "UP"
        } else if (k === Qt.Key_Down) {
            keyName = "DOWN"
        } else if (k >= Qt.Key_F1 && k <= Qt.Key_F12) {
            keyName = "F" + (k - Qt.Key_F1 + 1)
        } else if (event.text && event.text.length > 0) {
            keyName = event.text.toUpperCase()
        }

        if (keyName && keyName !== "") {
            parts.push(keyName)
            return parts.join(" + ")
        }
        return ""
    }

    onVisibleChanged: {
        if (visible) {
            var openT0 = Date.now()
            isRecording = false
            recordingItem = null
            hotkeysModel.searchQuery = ""
            hotkeysModel.selectedIndex = 0
            hotkeysModel.reload()
            searchInput.forceActiveFocus()
            console.info("[PERF] HotkeysWindow: Window displayed and input focused in " + (Date.now() - openT0) + "ms")
        } else {
            console.info("[PERF] HotkeysWindow: Window hidden")
        }
    }

    HotkeysModel {
        id: hotkeysModel
    }

    Connections {
        target: hotkeysModel
        function onSelectedIndexChanged() {
            if (hotkeysModel.selectedIndex >= 0 && hotkeysModel.selectedIndex < listView.count) {
                listView.positionViewAtIndex(hotkeysModel.selectedIndex, ListView.Contain)
            }
        }
    }

    // Modal surface: clean floating card with dynamic active border highlight on hover/focus
    Rectangle {
        id: surfaceCard
        anchors.fill: parent
        radius: Theme.radiusMd
        color: Theme.background
        border.color: (surfaceHover.hovered || searchInput.activeFocus) ? Theme.accent : Theme.border
        border.width: (surfaceHover.hovered || searchInput.activeFocus) ? 2 : 1
        clip: true

        HoverHandler {
            id: surfaceHover
        }

        Behavior on border.color {
            ColorAnimation { duration: 120 }
        }
        Behavior on border.width {
            NumberAnimation { duration: 120 }
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (windowRoot.isRecording) {
                    windowRoot.isRecording = false
                    windowRoot.recordingItem = null
                } else {
                    windowRoot.visible = false
                }
                event.accepted = true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header: Minimal search input area (keybindings_ prompt style, no box/border)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 16
                Layout.bottomMargin: 6

                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    color: Theme.text
                    selectByMouse: true
                    selectionColor: Theme.selection
                    selectedTextColor: Theme.text
                    readOnly: windowRoot.isRecording

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "keybindings_"
                        color: Theme.textSubtle
                        font: parent.font
                        visible: !searchInput.text && !windowRoot.isRecording
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: windowRoot.isRecording ? ("Set " + (windowRoot.recordingItem ? windowRoot.recordingItem.description : "Shortcut") + " — press key combination...") : ""
                        color: Theme.accent
                        font: parent.font
                        visible: windowRoot.isRecording
                    }

                    onTextChanged: {
                        if (!windowRoot.isRecording) {
                            hotkeysModel.searchQuery = text
                        }
                    }

                    Keys.onPressed: function(event) {
                        if (windowRoot.isRecording) {
                            if (event.key === Qt.Key_Escape) {
                                windowRoot.isRecording = false
                                windowRoot.recordingItem = null
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
                                if (windowRoot.recordingItem) {
                                    hotkeysModel.unsetShortcut(windowRoot.recordingItem.id)
                                }
                                windowRoot.isRecording = false
                                windowRoot.recordingItem = null
                                event.accepted = true
                                return
                            }
                            var formatted = windowRoot.formatKeyEvent(event)
                            if (formatted && formatted !== "") {
                                if (windowRoot.recordingItem) {
                                    hotkeysModel.setShortcut(windowRoot.recordingItem.id, formatted)
                                }
                                windowRoot.isRecording = false
                                windowRoot.recordingItem = null
                            }
                            event.accepted = true
                            return
                        }

                        if (event.key === Qt.Key_Escape) {
                            windowRoot.visible = false
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down) {
                            hotkeysModel.selectNext()
                            listView.positionViewAtIndex(hotkeysModel.selectedIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            hotkeysModel.selectPrevious()
                            listView.positionViewAtIndex(hotkeysModel.selectedIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (hotkeysModel.runSelected()) {
                                windowRoot.visible = false
                            }
                            event.accepted = true
                        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_S) {
                            if (hotkeysModel.selectedItem && hotkeysModel.selectedItem.editable === true) {
                                windowRoot.recordingItem = hotkeysModel.selectedItem
                                windowRoot.isRecording = true
                            }
                            event.accepted = true
                        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_U) {
                            if (hotkeysModel.selectedItem && hotkeysModel.selectedItem.editable === true) {
                                hotkeysModel.unsetShortcut(hotkeysModel.selectedItem.id)
                            }
                            event.accepted = true
                        }
                    }
                }
            }

            // Body: Shortcut List or Restrained Empty State
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12

                ListView {
                    id: listView
                    anchors.fill: parent
                    spacing: 2
                    clip: true
                    model: hotkeysModel.filteredItems
                    currentIndex: hotkeysModel.selectedIndex

                    delegate: HotkeyRow {
                        isSelected: index === hotkeysModel.selectedIndex
                    }

                    // Extremely subtle scrollbar indicator
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        width: 4
                        contentItem: Rectangle {
                            color: Theme.highlight
                            radius: 2
                        }
                    }
                }

                // Minimal empty state message (no oversized cards or icons)
                Text {
                    anchors.centerIn: parent
                    text: "No matching shortcuts"
                    color: Theme.textSubtle
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    visible: hotkeysModel.filteredItems.length === 0
                }
            }

            // Footer: Subtle low-emphasis keyboard hint text (no button widgets)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.bottomMargin: 10

                RowLayout {
                    anchors.fill: parent
                    spacing: 16

                    // ↵ Run (active when runnable, crisp muted when non-executable)
                    RowLayout {
                        spacing: 4
                        property bool isRunnable: hotkeysModel.selectedItem ? (hotkeysModel.selectedItem.runnable === true) : false

                        Text {
                            text: "↵"
                            color: parent.isRunnable ? Theme.accent : Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: parent.isRunnable
                        }
                        Text {
                            text: "Run"
                            color: parent.isRunnable ? Theme.text : Theme.textSubtle
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    // Alt+S Set (active when editable, crisp muted when fixed)
                    RowLayout {
                        spacing: 4
                        property bool isEditable: hotkeysModel.selectedItem ? (hotkeysModel.selectedItem.editable === true) : false

                        Text {
                            text: "Alt+S"
                            color: parent.isEditable ? Theme.gold : Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: parent.isEditable
                        }
                        Text {
                            text: "Set"
                            color: parent.isEditable ? Theme.text : Theme.textSubtle
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    // Alt+U Unset (active when editable and bound, crisp muted otherwise)
                    RowLayout {
                        spacing: 4
                        property bool canUnset: hotkeysModel.selectedItem ? (hotkeysModel.selectedItem.editable === true &&
                                                                             hotkeysModel.selectedItem.display_key &&
                                                                             hotkeysModel.selectedItem.display_key !== "None (Unbound)") : false

                        Text {
                            text: "Alt+U"
                            color: parent.canUnset ? Theme.love : Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: parent.canUnset
                        }
                        Text {
                            text: "Unset"
                            color: parent.canUnset ? Theme.text : Theme.textSubtle
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // Right grouping: status context + Esc Close
                    RowLayout {
                        spacing: 16
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                        // Context indicator for non-editable system bindings
                        Text {
                            text: (hotkeysModel.selectedItem && hotkeysModel.selectedItem.editable === false) ? "• System Binding" : ""
                            color: Theme.foam
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            visible: text !== ""
                        }

                        // Esc Close (always available)
                        RowLayout {
                            spacing: 4

                            Text {
                                text: "Esc"
                                color: Theme.textSubtle
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                            }
                            Text {
                                text: "Close"
                                color: Theme.textSubtle
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                            }
                        }
                    }
                }
            }
        }
    }
}
