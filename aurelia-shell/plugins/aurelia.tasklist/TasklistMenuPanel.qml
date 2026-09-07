import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme"

// Context menu for Hyprland toplevels. This is intentionally separate from
// D-Bus tray menus: running windows expose a Wayland Toplevel handle, not a
// QsMenuHandle.
PanelWindow {
    id: panelRoot

    property var anchorWindow: null
    property int barSize: 26
    property var windowTarget: null

    readonly property bool barAtBottom: anchorWindow && anchorWindow.position === "bottom"
    readonly property string windowTitle: windowTarget ? String(windowTarget.title || "Application") : "Application"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aurelia-tasklist-menu"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    implicitWidth: 0
    implicitHeight: 0
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false

    function openForWindow(target) {
        if (!target || !target.handle) return
        if (anchorWindow && typeof anchorWindow.requestPopout === "function") anchorWindow.requestPopout(panelRoot)
        windowTarget = target
        visible = true
        Qt.callLater(function() { card.forceActiveFocus() })
    }

    function close() {
        windowTarget = null
        visible = false
        if (anchorWindow && typeof anchorWindow.releasePopout === "function") anchorWindow.releasePopout(panelRoot)
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

    MouseArea {
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.LeftButton
        onClicked: function(mouse) {
            mouse.accepted = true
            panelRoot.close()
        }
    }

    Rectangle {
        id: card
        width: 300
        height: 190
        anchors.right: parent.right
        anchors.top: barAtBottom ? undefined : parent.top
        anchors.bottom: barAtBottom ? parent.bottom : undefined
        anchors.topMargin: barAtBottom ? 0 : panelRoot.barSize + Theme.spacingLg
        anchors.bottomMargin: barAtBottom ? panelRoot.barSize + Theme.spacingLg : 0
        anchors.rightMargin: Theme.spacingLg
        z: 1
        radius: Theme.radiusLg
        color: Theme.bgBase
        border.color: Theme.border
        border.width: Theme.borderWidthDefault
        focus: panelRoot.visible

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: function(mouse) { mouse.accepted = true }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingXl
            spacing: Theme.spacingSm

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

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                panelRoot.close()
                event.accepted = true
            }
        }
    }
}
