import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../ui"
import "../../theme"

AureliaKeyboardPanel {
    id: panelRoot

    property string confirmAction: ""

    ownerId: "aurelia.power"
    popupWidth: 280
    popupHeight: cardHeight
    shown: false
    readonly property int cardHeight: confirmAction === ""
        ? (Theme.spacingXl * 2 + 28 + Theme.spacingSm * 5 + 5 * 40)
        : (Theme.spacingXl * 2 + 28 + Theme.spacingSm + 2 * 40)

    function open() {
        confirmAction = ""
        shown = true
    }

    function close() {
        confirmAction = ""
        shown = false
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

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingSm
        focus: panelRoot.shown

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

    Item {
        width: 0
        height: 0
        visible: false

        Process {
            id: actionProcess
            command: []
            onExited: function(code) {
                if (code !== 0) console.error("[POWER] action_failed code=" + code)
            }
        }
    }
}
