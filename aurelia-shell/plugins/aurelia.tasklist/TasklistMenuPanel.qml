import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../ui"
import "../../theme"

// Context menu for Hyprland toplevels. This is intentionally separate from
// D-Bus tray menus: running windows expose a Wayland Toplevel handle, not a
// QsMenuHandle.
AureliaKeyboardPanel {
    id: panelRoot

    property var windowTarget: null

    readonly property string windowTitle: windowTarget ? String(windowTarget.title || "Application") : "Application"

    ownerId: "aurelia.tasklist"
    popupWidth: 280
    popupHeight: 160
    contentPadding: Theme.popupPadding
    contentSizingItem: menuColumn
    fitHeightToContent: true
    minPopupHeight: 132
    maxPopupHeight: 220
    shown: false

    function openForWindow(target, itemAnchor) {
        if (!target || !target.handle) return
        windowTarget = target
        anchorItem = itemAnchor || anchorItem
        shown = true
    }

    function close() {
        windowTarget = null
        shown = false
    }

    function closeForPopoutSwitch() { close() }

    function activateWindow() {
        if (windowTarget && windowTarget.handle) windowTarget.handle.activate()
        close()
    }

    function closeWindow() {
        if (windowTarget && windowTarget.handle) windowTarget.handle.close()
        close()
    }

    function toggleFullscreen() {
        if (windowTarget && windowTarget.handle) windowTarget.handle.fullscreen = !windowTarget.handle.fullscreen
        close()
    }

    ColumnLayout {
        id: menuColumn
        anchors.fill: parent
        spacing: Theme.popupRowGap
        focus: panelRoot.shown

            Text {
                Layout.fillWidth: true
                text: panelRoot.windowTitle
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                font.weight: Theme.fontWeightBold
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.rowHeight
                radius: Theme.radiusSm
                color: focusHover.hovered ? Theme.selectionHover : "transparent"
                HoverHandler { id: focusHover }

                Rectangle {
                    visible: focusHover.hovered
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingXs
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: Math.max(14, parent.height - Theme.spacingSm)
                    radius: width / 2
                    color: Theme.accent
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingMd
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Focus window"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    onClicked: function(mouse) { mouse.accepted = true; panelRoot.activateWindow() }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.rowHeight
                radius: Theme.radiusSm
                color: fullscreenHover.hovered ? Theme.selectionHover : "transparent"
                HoverHandler { id: fullscreenHover }

                Rectangle {
                    visible: fullscreenHover.hovered
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingXs
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: Math.max(14, parent.height - Theme.spacingSm)
                    radius: width / 2
                    color: Theme.accent
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingMd
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Toggle fullscreen"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    onClicked: function(mouse) { mouse.accepted = true; panelRoot.toggleFullscreen() }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.rowHeight
                radius: Theme.radiusSm
                color: closeHover.hovered
                    ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.16)
                    : "transparent"
                HoverHandler { id: closeHover }

                Rectangle {
                    visible: closeHover.hovered
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingXs
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: Math.max(14, parent.height - Theme.spacingSm)
                    radius: width / 2
                    color: Theme.error
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingMd
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Close window"
                    color: closeHover.hovered ? Theme.error : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    onClicked: function(mouse) { mouse.accepted = true; panelRoot.closeWindow() }
                }
            }
    }
}
