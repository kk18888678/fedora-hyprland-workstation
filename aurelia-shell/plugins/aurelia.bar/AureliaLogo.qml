import QtQuick
import "../../theme"

// Theme-aware Aurelia mark. It is intentionally drawn in QML so the bar does
// not depend on a raster asset or a fixed-color logo file.
Item {
    id: root

    property var shell: null
    property bool hovered: logoHover.hovered

    implicitWidth: 26
    implicitHeight: 26

    Canvas {
        id: logoCanvas
        anchors.fill: parent

        onPaint: {
            var context = getContext("2d")
            context.reset()
            context.lineCap = "round"
            context.lineJoin = "round"

            var pad = width * 0.18
            var apexX = width * 0.50
            var apexY = height * 0.14
            var baseY = height * 0.82

            context.strokeStyle = Theme.accent
            context.lineWidth = Math.max(1.8, width * 0.075)
            context.beginPath()
            context.moveTo(pad, baseY)
            context.lineTo(apexX, apexY)
            context.lineTo(width - pad, baseY)
            context.moveTo(width * 0.31, height * 0.58)
            context.lineTo(width * 0.69, height * 0.58)
            context.stroke()

            context.strokeStyle = Theme.accentAlt
            context.lineWidth = Math.max(1.2, width * 0.045)
            context.beginPath()
            context.ellipse(width * 0.50, height * 0.50, width * 0.38, height * 0.18)
            context.stroke()
        }

        Connections {
            target: Theme
            function onAccentChanged() { logoCanvas.requestPaint() }
            function onAccentAltChanged() { logoCanvas.requestPaint() }
        }
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
