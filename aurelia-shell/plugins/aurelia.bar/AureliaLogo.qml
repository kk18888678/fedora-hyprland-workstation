import QtQuick
import "../../theme"
import "../../ui"

// Compact Aurelia brand mark. The same vector asset is used by the bar and the
// Fastfetch About surface so the workstation has one recognizable identity. The
// bar uses the high-resolution direct asset so its fine orbital strokes do not
// pass through a low-resolution recolor texture.
Item {
    id: root

    property var bar: null
    property var shell: null
    property bool hovered: logoHover.hovered
    readonly property color barForeground: root.bar && root.bar.barForeground !== undefined
        ? root.bar.barForeground : Theme.text
    // Uniform bar-icon contract: the brand mark uses the shared 16 px ink
    // canvas and the rest colour is the bar foreground, at full opacity.
    readonly property int iconCanvas: root.bar && root.bar.barIconCanvas
        ? root.bar.barIconCanvas : Theme.bar.iconCanvas

    function shellOwner() {
        if (root.shell && typeof root.shell.summon === "function") return root.shell
        if (root.bar && root.bar.shell && typeof root.bar.shell.summon === "function")
            return root.bar.shell
        return null
    }

    function openCommandCenter() {
        console.info("[BAR] logo_click_received")
        var controller = root.shellOwner()
        if (!controller) {
            console.error("[BAR] logo_click_failed reason=shell_unavailable")
            return "not-ready"
        }
        var result = ""
        try {
            var rawResult = controller.summon("aurelia.launcher", "{}")
            if (rawResult === true) result = "ok"
            else if (rawResult === false || rawResult === undefined || rawResult === null) result = "error"
            else result = String(rawResult)
        } catch (error) {
            console.error("[BAR] logo_click_failed reason=summon_exception")
            return "error"
        }
        if (result === "ok" || result === "pending")
            console.info("[BAR] logo_click_dispatched result=" + result)
        else
            console.error("[BAR] logo_click_failed result=" + result)
        return result
    }

    implicitWidth: bar && bar.barIconSlot ? bar.barIconSlot : 27
    implicitHeight: bar && bar.barSize ? bar.barSize : 26

    Rectangle {
        anchors.centerIn: parent
        width: root.implicitWidth
        height: width
        radius: Theme.radiusSm
        color: root.hovered ? Theme.selection : "transparent"
        border.color: root.hovered ? Theme.border : "transparent"
        border.width: root.hovered ? Theme.borderWidthDefault : 0
        opacity: root.hovered ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.effectiveDurationFast }
        }
    }

        AureliaMark {
            id: logoMark
            anchors.centerIn: parent
            width: root.iconCanvas
            height: root.iconCanvas
            color: root.barForeground
            coreColor: root.barForeground
        }

    HoverHandler { id: logoHover }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            mouse.accepted = true
            root.openCommandCenter()
        }
    }
}
