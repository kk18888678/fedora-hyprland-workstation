import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../ui"
import "../../theme"

AureliaKeyboardPanel {
    id: panelRoot

    property string confirmAction: ""

    readonly property var iconGlyphs: ({
        "lock": "󰍁",
        "logout": "󰍃",
        "suspend": "󰤄",
        "reboot": "󰜉",
        "power": "󰐥",
        "confirm": "󰄬",
        "cancel": "󰅖"
    })

    ownerId: "aurelia.power"
    popupWidth: 380
    popupHeight: cardHeight
    fitHeightToContent: true
    minPopupHeight: 180
    maxPopupHeight: 560
    contentSizingItem: contentColumn
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

    function iconGlyph(name) {
        return panelRoot.iconGlyphs[name] || ""
    }

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
        id: contentColumn
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
                    { id: "lock", label: "Lock", icon: "lock" },
                    { id: "logout", label: "Logout", icon: "logout" },
                    { id: "suspend", label: "Suspend", icon: "suspend" },
                    { id: "reboot", label: "Reboot", icon: "reboot" },
                    { id: "shutdown", label: "Shutdown", icon: "power" }
                ] : [
                    { id: "confirm", label: "Confirm", icon: "confirm" },
                    { id: "cancel", label: "Cancel", icon: "cancel" }
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

                        Text {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            text: panelRoot.iconGlyph(modelData.icon)
                            color: powerActionHover.hovered ? Theme.text : Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
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
