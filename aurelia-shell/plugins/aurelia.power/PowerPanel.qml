import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import "../../theme"

PanelWindow {
    id: panelRoot

    property int barSize: 26
    property var anchorWindow: null
    property string confirmAction: ""

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aurelia-power"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    implicitWidth: 0
    implicitHeight: 0
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false

    readonly property bool barAtBottom: anchorWindow && anchorWindow.position === "bottom"
    readonly property int barTopClearance: anchorWindow && anchorWindow.surfaceTop !== undefined ? anchorWindow.surfaceTop + panelRoot.barSize : panelRoot.barSize
    readonly property int barBottomClearance: anchorWindow && anchorWindow.surfaceBottom !== undefined ? anchorWindow.surfaceBottom + panelRoot.barSize : panelRoot.barSize
    readonly property int cardHeight: confirmAction === ""
        ? (Theme.spacingXl * 2 + 28 + Theme.spacingSm * 5 + 5 * 40)
        : (Theme.spacingXl * 2 + 28 + Theme.spacingSm + 2 * 40)

    function open() {
        if (anchorWindow && typeof anchorWindow.refreshSurfaceGeometry === "function") anchorWindow.refreshSurfaceGeometry()
        if (anchorWindow && typeof anchorWindow.requestPopout === "function") anchorWindow.requestPopout(panelRoot, "aurelia.power")
        confirmAction = ""
        visible = true
    }

    function close() {
        confirmAction = ""
        visible = false
        if (anchorWindow && typeof anchorWindow.releasePopout === "function") anchorWindow.releasePopout(panelRoot)
    }

    function closeForPopoutSwitch() { close() }

    function requestAction(action) {
        if (action === "reboot" || action === "shutdown") {
            confirmAction = action
            return
        }
        runAction(action)
    }

    function runAction(action) {
        var command = []
        if (action === "lock") command = ["loginctl", "lock-session"]
        else if (action === "logout") command = ["hyprctl", "dispatch", "exit"]
        else if (action === "suspend") command = ["systemctl", "suspend"]
        else if (action === "reboot") command = ["systemctl", "reboot"]
        else if (action === "shutdown") command = ["systemctl", "poweroff"]
        else return
        close()
        actionProcess.command = command
        actionProcess.running = true
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
        width: 280
        height: panelRoot.cardHeight
        anchors.right: parent.right
        anchors.top: barAtBottom ? undefined : parent.top
        anchors.bottom: barAtBottom ? parent.bottom : undefined
        anchors.topMargin: barAtBottom ? 0 : panelRoot.barTopClearance + Theme.spacingLg
        anchors.bottomMargin: barAtBottom ? panelRoot.barBottomClearance + Theme.spacingLg : 0
        anchors.rightMargin: Theme.spacingLg
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
                text: panelRoot.confirmAction === "" ? "Power" : (panelRoot.confirmAction === "reboot" ? "Restart computer?" : "Power off computer?")
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.weight: Theme.fontWeightBold
            }

            Repeater {
                model: panelRoot.confirmAction === "" ? [
                    { id: "lock", label: "Lock", icon: "system-lock-screen" },
                    { id: "logout", label: "Logout", icon: "system-log-out" },
                    { id: "suspend", label: "Suspend", icon: "system-suspend" },
                    { id: "reboot", label: "Reboot", icon: "system-reboot" },
                    { id: "shutdown", label: "Shutdown", icon: "system-shutdown" }
                ] : [
                    { id: "confirm", label: "Confirm", icon: "dialog-ok-apply" },
                    { id: "cancel", label: "Cancel", icon: "dialog-cancel" }
                ]

                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: Theme.radiusSm
                    color: powerActionHover.hovered ? Theme.selection : Theme.surface
                    HoverHandler { id: powerActionHover }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingSm
                        anchors.rightMargin: Theme.spacingSm
                        spacing: Theme.spacingSm

                        IconImage {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            source: Quickshell.iconPath(modelData.icon, "system-shutdown")
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: function(mouse) {
                            mouse.accepted = true
                            if (panelRoot.confirmAction !== "") {
                                if (modelData.id === "confirm") panelRoot.runAction(panelRoot.confirmAction)
                                else panelRoot.close()
                            } else {
                                panelRoot.requestAction(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }

    Process {
        id: actionProcess
        command: []
        onExited: function(code) {
            if (code !== 0) console.error("[POWER] action_failed code=" + code)
        }
    }
}
