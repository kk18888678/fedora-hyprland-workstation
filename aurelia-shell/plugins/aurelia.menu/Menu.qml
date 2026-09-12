import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../ui"

// Small on-demand Aurelia menu. Its data/provider model is independent from
// the Command Center and uses the same Aurelia tokens and panel primitives.
PanelWindow {
    id: menuRoot

    property var shell: null
    property var pluginRegistry: null
    property var pluginHost: null
    property var manifest: ({})
    property string aureliaPath: ""
    readonly property int menuHeight: Math.min(Math.max(220,
        Theme.popupPadding * 2 + Math.max(1, menuModel.rows.length) * Theme.rowHeight +
        Math.max(0, menuModel.rows.length - 1) * Theme.spacingXs),
        Math.max(220, height - Theme.spacingXxl * 2))

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aurelia-menu"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false

    MenuModel {
        id: menuModel
        shell: menuRoot.shell
        pluginRegistry: menuRoot.pluginRegistry
        pluginHost: menuRoot.pluginHost
        aureliaPath: menuRoot.aureliaPath
    }

    function open(payloadJson) {
        menuModel.open(payloadJson || "{}")
        visible = true
        Qt.callLater(function() { menuFocus.forceActiveFocus() })
    }

    function close() {
        visible = false
    }

    function toggle(payloadJson) {
        if (visible) {
            close()
            return "closed"
        }
        open(payloadJson || "{}")
        return "ok"
    }

    function activateRow(row) {
        if (menuModel.activate(row)) {
            close()
            return
        }
        menuModel.lastError = menuModel.lastError || "Menu action failed."
    }

    MouseArea {
        anchors.fill: parent
        onClicked: menuRoot.close()
    }

    Rectangle {
        id: card
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: Theme.spacingXl
        anchors.leftMargin: Theme.spacingXl
        width: Math.min(parent.width - Theme.spacingXl * 2, Theme.paletteWidth)
        height: menuRoot.menuHeight
        radius: Theme.radiusMd
        color: Theme.launcher.background
        border.color: Theme.launcher.border
        border.width: Theme.borderWidthDefault

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: function(mouse) { mouse.accepted = true }
        }

        FocusScope {
            id: menuFocus
            anchors.fill: parent
            focus: menuRoot.visible
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    menuRoot.close()
                    event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                    menuList.currentIndex = Math.min(menuList.count - 1, menuList.currentIndex + 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                    menuList.currentIndex = Math.max(0, menuList.currentIndex - 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (menuList.currentIndex >= 0 && menuList.currentIndex < menuList.count)
                        menuRoot.activateRow(menuModel.rows[menuList.currentIndex])
                    event.accepted = true
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.popupPadding
                spacing: Theme.spacingSm

                Text {
                    Layout.fillWidth: true
                    text: "Aurelia Menu"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLg
                    font.weight: Theme.fontWeightBold
                }

                ListView {
                    id: menuList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Theme.popupRowGap
                    model: menuModel.rows
                    currentIndex: 0

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: menuList.width
                        height: Theme.rowHeight
                        radius: Theme.radiusSm
                        color: ListView.isCurrentItem ? Theme.launcher.selectedBackground : "transparent"
                        border.color: ListView.isCurrentItem ? Theme.launcher.selectedBorder : Theme.border
                        border.width: ListView.isCurrentItem ? Theme.borderWidthDefault : 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingSm
                            anchors.rightMargin: Theme.spacingSm
                            spacing: Theme.spacingSm

                            Text {
                                Layout.preferredWidth: 24
                                text: modelData.icon || "󰘦"
                                color: ListView.isCurrentItem ? Theme.launcher.selectedText : Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeMd
                                horizontalAlignment: Text.AlignHCenter
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.label || modelData.id
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeMd
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.subtitle || modelData.detail || ""
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                visible: modelData.checked === true
                                text: "✓"
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeMd
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            hoverEnabled: true
                            onEntered: menuList.currentIndex = index
                            onClicked: menuRoot.activateRow(modelData)
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "aurelia.menu"
        function ping(): bool { return true }
        function open(): void { menuRoot.open("{}") }
        function close(): void { menuRoot.close() }
        function toggle(): void { menuRoot.toggle("{}") }
        function isVisible(): bool { return menuRoot.visible }
    }
}
