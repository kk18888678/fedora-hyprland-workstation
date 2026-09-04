import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../../theme"

PanelWindow {
    id: windowRoot

    // Layer-shell Wayland configuration: centered overlay surface with exclusive focus
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Window dimensions: restrained command palette proportions (800x480)
    implicitWidth: 800
    implicitHeight: 480
    color: "transparent"

    onVisibleChanged: {
        if (visible) {
            hotkeysModel.searchQuery = ""
            hotkeysModel.reload()
            searchInput.forceActiveFocus()
        }
    }

    HotkeysModel {
        id: hotkeysModel
    }

    // Modal surface: clean floating card with single subtle border and Rosé Pine Moon background
    Rectangle {
        id: surfaceCard
        anchors.fill: parent
        radius: Theme.radiusMd
        color: Theme.background
        border.color: Theme.border
        border.width: 1
        clip: true

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

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "keybindings_"
                        color: Theme.textSubtle
                        font: parent.font
                        visible: !searchInput.text
                    }

                    onTextChanged: {
                        hotkeysModel.searchQuery = text
                    }

                    Keys.onPressed: function(event) {
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
                                hotkeysModel.setShortcut(hotkeysModel.selectedItem.id)
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

                    // ↵ Run (only when runnable)
                    RowLayout {
                        spacing: 4
                        visible: hotkeysModel.selectedItem && hotkeysModel.selectedItem.runnable === true

                        Text {
                            text: "↵"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                        Text {
                            text: "Run"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    // Alt+S Set (only when editable)
                    RowLayout {
                        spacing: 4
                        visible: hotkeysModel.selectedItem && hotkeysModel.selectedItem.editable === true

                        Text {
                            text: "Alt+S"
                            color: Theme.gold
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                        Text {
                            text: "Set"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    // Alt+U Unset (only when editable and bound)
                    RowLayout {
                        spacing: 4
                        visible: hotkeysModel.selectedItem &&
                                 hotkeysModel.selectedItem.editable === true &&
                                 hotkeysModel.selectedItem.display_key &&
                                 hotkeysModel.selectedItem.display_key !== "None (Unbound)"

                        Text {
                            text: "Alt+U"
                            color: Theme.love
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                        Text {
                            text: "Unset"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    Item {
                        Layout.fillWidth: true
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
