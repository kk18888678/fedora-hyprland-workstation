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
    popupWidth: 300
    popupHeight: 190
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
        anchors.fill: parent
        spacing: Theme.spacingSm
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
                Layout.preferredHeight: 36
                radius: Theme.radiusSm
                color: focusHover.hovered ? Theme.selection : Theme.surface
                HoverHandler { id: focusHover }
                Text { anchors.centerIn: parent; text: "Focus window"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true; panelRoot.activateWindow() } }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: Theme.radiusSm
                color: fullscreenHover.hovered ? Theme.selection : Theme.surface
                HoverHandler { id: fullscreenHover }
                Text { anchors.centerIn: parent; text: "Toggle fullscreen"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true; panelRoot.toggleFullscreen() } }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: Theme.radiusSm
                color: closeHover.hovered ? Theme.error : Theme.surface
                HoverHandler { id: closeHover }
                Text { anchors.centerIn: parent; text: "Close window"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true; panelRoot.closeWindow() } }
            }
    }
}
