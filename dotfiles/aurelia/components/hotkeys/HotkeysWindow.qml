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

    // Window dimensions: restrained command palette proportions (800x480)
    implicitWidth: 800
    implicitHeight: 480
    color: "transparent"

    property bool isRecording: false
    property var recordingItem: null
    property alias hotkeysModel: hotkeysModel

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
            if (!hotkeysModel.allItems || hotkeysModel.allItems.length === 0) {
                hotkeysModel.reload()
            }
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

    // Modal surface: clean floating card with dynamic theme-aware active border highlight on hover/focus
    Rectangle {
        id: surfaceCard
        anchors.fill: parent
        radius: Theme.radiusMd
        color: Theme.background
        border.color: (surfaceHover.hovered || searchInput.activeFocus) ? Theme.borderActive : Theme.border
        border.width: 2
        clip: true

        HoverHandler {
            id: surfaceHover
        }

        Behavior on border.color {
            ColorAnimation { duration: 100 }
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
                    spacing: 3
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

            // Footer: High-contrast keyboard hint text and contextual actions
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.bottomMargin: 10

                RowLayout {
                    anchors.fill: parent
                    spacing: 16

                    // ↵ Run (active when runnable)
                    RowLayout {
                        spacing: 4
                        visible: hotkeysModel.selectedItem ? (hotkeysModel.selectedItem.runnable === true) : false

                        Text {
                            text: "↵"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Run"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.Medium
                        }
                    }

                    // Alt+S Set (active when editable)
                    RowLayout {
                        spacing: 4
                        visible: hotkeysModel.selectedItem ? (hotkeysModel.selectedItem.editable === true) : false

                        Text {
                            text: "Alt+S"
                            color: Theme.gold
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Set"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.Medium
                        }
                    }

                    // Alt+U Unset (active when editable and bound)
                    RowLayout {
                        spacing: 4
                        visible: hotkeysModel.selectedItem ? (hotkeysModel.selectedItem.editable === true &&
                                                              hotkeysModel.selectedItem.display_key &&
                                                              hotkeysModel.selectedItem.display_key !== "None (Unbound)") : false

                        Text {
                            text: "Alt+U"
                            color: Theme.love
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Unset"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.Medium
                        }
                    }

                    // Mouse Control Info (active when selecting mouse gestures / drag / resize)
                    RowLayout {
                        spacing: 8
                        visible: hotkeysModel.selectedItem ? (hotkeysModel.selectedItem.category === "Mouse Controls" || hotkeysModel.selectedItem.mouse === true) : false

                        Text {
                            text: "🖱 Mouse Action"
                            color: Theme.foam
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Compositor window gesture"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.Medium
                        }
                    }

                    // System Binding Info (active when selecting non-editable system bindings)
                    RowLayout {
                        spacing: 8
                        visible: hotkeysModel.selectedItem ? (hotkeysModel.selectedItem.editable === false && hotkeysModel.selectedItem.category !== "Mouse Controls" && !hotkeysModel.selectedItem.mouse) : false

                        Text {
                            text: "• System Binding"
                            color: Theme.foam
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Compositor managed"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.Medium
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // Esc Close (always available with high contrast)
                    RowLayout {
                        spacing: 6
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                        Text {
                            text: "Esc"
                            color: Theme.rose
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Close"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }
    }
}
