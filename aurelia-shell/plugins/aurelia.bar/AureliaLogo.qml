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
            width: 20
            height: 20
            color: root.hovered ? Theme.text : Theme.accent
            coreColor: root.hovered ? Theme.text : Theme.gold
            opacity: root.hovered ? 1.0 : 0.92
        }

    HoverHandler { id: logoHover }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            mouse.accepted = true
            if (root.shell && typeof root.shell.summon === "function") {
                root.shell.summon("aurelia.launcher", "{}")
            }
        }
    }
}
