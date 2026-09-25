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
    readonly property color barForeground: root.bar && root.bar.barForeground !== undefined
        ? root.bar.barForeground : Theme.text
    // Uniform bar-icon contract: one 16 px ink canvas scaled by the bar, no
    // literal icon sizes. The only non-foreground tint is the documented DND
    // alert state; hover is expressed by the slot fill, not the glyph.
    readonly property int iconCanvas: root.bar && root.bar.barIconCanvas
        ? root.bar.barIconCanvas : Theme.bar.iconCanvas

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
            width: root.iconCanvas
            height: root.iconCanvas
            name: root.doNotDisturb ? "notifications-disabled" : "notifications"
            iconSize: root.iconCanvas
            tint: root.doNotDisturb ? Theme.warning : root.barForeground
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
