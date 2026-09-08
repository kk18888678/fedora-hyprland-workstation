import QtQuick
import "../../theme"

// Compact, theme-aware Aurelia mark. It is intentionally drawn in QML so the
// bar does not depend on a raster asset or a fixed-color logo file.
Item {
    id: root

    property var shell: null
    property bool hovered: logoHover.hovered

    // Keep a comfortable click target while giving the painted mark enough
    // breathing room inside the 26 px bar.
    readonly property int markSize: 20
    implicitWidth: 24
    implicitHeight: 26

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

    Canvas {
        id: logoCanvas
        anchors.centerIn: parent
        width: root.markSize
        height: root.markSize
        scale: root.hovered ? 1.04 : 1

        Behavior on scale {
            NumberAnimation { duration: Theme.effectiveDurationFast }
        }

        onPaint: {
            var context = getContext("2d")
            context.reset()
            context.lineCap = "round"
            context.lineJoin = "round"

            var centerX = width * 0.50
            var apexY = height * 0.12
            var baseY = height * 0.82
            var crossbarY = height * 0.59

            context.strokeStyle = Theme.accent
            context.lineWidth = Math.max(1.7, width * 0.095)
            context.beginPath()
            context.moveTo(width * 0.20, baseY)
            context.lineTo(centerX, apexY)
            context.lineTo(width * 0.80, baseY)
            context.moveTo(width * 0.33, crossbarY)
            context.lineTo(width * 0.67, crossbarY)
            context.stroke()

            context.strokeStyle = Theme.accentAlt
            context.globalAlpha = root.hovered ? 1 : 0.88
            context.lineWidth = Math.max(1.05, width * 0.06)
            var orbitWidth = width * 0.76
            var orbitHeight = height * 0.34
            context.beginPath()
            // A light orbit gives the mark its Aurelia identity without
            // competing with the A at the bar's small scale.
            // Canvas ellipse() uses the orbit's top-left bounding-box point.
            context.ellipse(centerX - orbitWidth / 2, height * 0.33, orbitWidth, orbitHeight)
            context.stroke()

            context.globalAlpha = root.hovered ? 1 : 0.78
            context.fillStyle = Theme.accentAlt
            context.beginPath()
            context.arc(width * 0.80, height * 0.18, Math.max(0.7, width * 0.045), 0, Math.PI * 2, false)
            context.fill()
        }

        Connections {
            target: Theme
            function onAccentChanged() { logoCanvas.requestPaint() }
            function onAccentAltChanged() { logoCanvas.requestPaint() }
        }
    }

    onHoveredChanged: logoCanvas.requestPaint()

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
