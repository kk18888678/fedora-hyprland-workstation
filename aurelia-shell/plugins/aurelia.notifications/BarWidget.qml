import QtQuick
import "../../theme"
import "../../ui"

// Small notification-center affordance. Left click opens the center; right
// click toggles DND. The widget delegates state mutation to the resident
// service over shell IPC and never duplicates the notification daemon.
Item {
    id: root

    property var bar: null
    property var shell: null
    property var pluginRegistry: null
    property string aureliaPath: ""
    property string moduleName: "aurelia.notifications"
    property var settings: ({})
    property var manifest: ({})
    property bool doNotDisturb: false

    implicitWidth: bar ? bar.barSize : 26
    implicitHeight: bar ? bar.barSize : 26

    function serviceCall(method, argument) {
        if (!shell || typeof shell.call !== "function") return "not-ready"
        return String(shell.call("aurelia.notifications", method, argument || "") || "")
    }

    function refreshDnd() {
        var state = serviceCall("dndState", "")
        if (state === "on" || state === "off") doNotDisturb = state === "on"
    }

    function openCenterFromBar() {
        serviceCall("openCenter", "")
        refreshDnd()
    }

    function toggleDndFromBar() {
        var state = serviceCall("toggleDnd", "")
        if (state === "on" || state === "off") doNotDisturb = state === "on"
    }

    Component.onCompleted: refreshDnd()

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: hover.hovered ? Theme.selection : "transparent"

        HoverHandler { id: hover }

        Connections {
            target: hover
            function onHoveredChanged() {
                if (hover.hovered) root.refreshDnd()
            }
        }

        AureliaIcon {
            anchors.centerIn: parent
            width: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            height: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            name: root.doNotDisturb ? "notifications-disabled" : "notifications"
            iconSize: root.bar && root.bar.barIconFont ? root.bar.barIconFont : 13
            tint: hover.hovered ? Theme.text : (root.doNotDisturb ? Theme.warning : Theme.accent)
        }

        AureliaToolTip {
            triggerItem: root
            bar: root.bar
            hovered: hover.hovered
            text: root.doNotDisturb
                ? "Notifications silenced · right-click to allow"
                : "Notifications · right-click for DND"
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                mouse.accepted = true
                if (mouse.button === Qt.RightButton) root.toggleDndFromBar()
                else root.openCenterFromBar()
            }
        }
    }
}
