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

    // Sizing and positioning
    implicitWidth: 720
    implicitHeight: 520
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

    // Modal surface card
    Rectangle {
        id: surfaceCard
        anchors.centerIn: parent
        width: 720
        height: 520
        radius: Theme.radiusLg
        color: Theme.background
        border.color: Theme.border
        border.width: 1
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header: Search Bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                color: Theme.surface
                border.color: Theme.highlight
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingLg
                    anchors.rightMargin: Theme.spacingLg
                    spacing: Theme.spacingMd

                    // Search icon / prompt symbol
                    Text {
                        text: "󰍉"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                    }

                    // Search text input
                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeMd
                        color: Theme.text
                        selectByMouse: true
                        selectionColor: Theme.selectionActive
                        selectedTextColor: Theme.text

                        Text {
                            anchors.fill: parent
                            text: "Search shortcuts..."
                            color: Theme.textSubtle
                            font: parent.font
                            visible: !searchInput.text && !searchInput.activeFocus
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

                    // Result count badge
                    Rectangle {
                        Layout.preferredWidth: countText.implicitWidth + 16
                        Layout.preferredHeight: 22
                        radius: Theme.radiusSm
                        color: Theme.overlay

                        Text {
                            id: countText
                            anchors.centerIn: parent
                            text: hotkeysModel.filteredItems.length + " shortcuts"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                        }
                    }
                }
            }

            // Body: Shortcut List or Empty State
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: listView
                    anchors.fill: parent
                    anchors.margins: Theme.spacingMd
                    spacing: 4
                    clip: true
                    model: hotkeysModel.filteredItems
                    currentIndex: hotkeysModel.selectedIndex

                    delegate: HotkeyRow {
                        modelData: model
                        isSelected: index === hotkeysModel.selectedIndex
                    }
                }

                // Empty state message
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Theme.spacingMd
                    visible: hotkeysModel.filteredItems.length === 0

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "󰌑"
                        color: Theme.textSubtle
                        font.family: Theme.fontFamily
                        font.pixelSize: 36
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "No matching shortcuts found"
                        color: Theme.textMuted
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeMd
                    }
                }
            }

            // Footer: Context-sensitive Action Bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                color: Theme.surface
                border.color: Theme.highlight
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingLg
                    anchors.rightMargin: Theme.spacingLg
                    spacing: Theme.spacingLg

                    // ↵ Run action (only when runnable)
                    RowLayout {
                        spacing: Theme.spacingXs
                        visible: hotkeysModel.selectedItem && hotkeysModel.selectedItem.runnable === true

                        Text {
                            text: "↵"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.bold: true
                            font.pixelSize: Theme.fontSizeSm
                        }
                        Text {
                            text: "Run"
                            color: Theme.text
                            font.family: Theme.fontFamilyProse
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    // Alt+S Set (only when editable)
                    RowLayout {
                        spacing: Theme.spacingXs
                        visible: hotkeysModel.selectedItem && hotkeysModel.selectedItem.editable === true

                        Rectangle {
                            Layout.preferredWidth: altSText.implicitWidth + 8
                            Layout.preferredHeight: 18
                            radius: 4
                            color: Theme.overlay
                            Text {
                                id: altSText
                                anchors.centerIn: parent
                                text: "Alt+S"
                                color: Theme.gold
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                            }
                        }
                        Text {
                            text: "Set"
                            color: Theme.text
                            font.family: Theme.fontFamilyProse
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    // Alt+U Unset (only when editable and bound)
                    RowLayout {
                        spacing: Theme.spacingXs
                        visible: hotkeysModel.selectedItem &&
                                 hotkeysModel.selectedItem.editable === true &&
                                 hotkeysModel.selectedItem.display_key &&
                                 hotkeysModel.selectedItem.display_key !== "None (Unbound)"

                        Rectangle {
                            Layout.preferredWidth: altUText.implicitWidth + 8
                            Layout.preferredHeight: 18
                            radius: 4
                            color: Theme.overlay
                            Text {
                                id: altUText
                                anchors.centerIn: parent
                                text: "Alt+U"
                                color: Theme.love
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                            }
                        }
                        Text {
                            text: "Unset"
                            color: Theme.text
                            font.family: Theme.fontFamilyProse
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // Esc Close (always available)
                    RowLayout {
                        spacing: Theme.spacingXs

                        Rectangle {
                            Layout.preferredWidth: escText.implicitWidth + 8
                            Layout.preferredHeight: 18
                            radius: 4
                            color: Theme.overlay
                            Text {
                                id: escText
                                anchors.centerIn: parent
                                text: "Esc"
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                            }
                        }
                        Text {
                            text: "Close"
                            color: Theme.textMuted
                            font.family: Theme.fontFamilyProse
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }
                }
            }
        }
    }
}
