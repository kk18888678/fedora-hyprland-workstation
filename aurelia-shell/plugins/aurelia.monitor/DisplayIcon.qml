import QtQuick

// Small outline icons used by the display card. The reference card uses a
// consistent black line icon family; drawing these locally avoids depending on
// whichever Nerd Font glyph happens to be active in the user's theme.
Item {
    id: root

    property string kind: "monitor"
    property color color: Theme.text
    property real strokeWidth: 2.4

    implicitWidth: 40
    implicitHeight: 40

    Canvas {
        id: canvas
        anchors.fill: parent

        function point(value) { return value * Math.min(width, height) / 40 }

        onPaint: {
            var ctx = getContext("2d")
            var scale = Math.min(width, height) / 40
            ctx.clearRect(0, 0, width, height)
            ctx.setTransform(1, 0, 0, 1, 0, 0)
            ctx.save()
            ctx.scale(scale, scale)
            ctx.strokeStyle = root.color
            ctx.fillStyle = root.color
            ctx.lineWidth = root.strokeWidth / scale
            ctx.lineCap = "round"
            ctx.lineJoin = "round"

            if (root.kind === "monitor" || root.kind === "identify" || root.kind === "compositor") {
                ctx.strokeRect(5.5, 7.5, 29, 20)
                ctx.beginPath()
                ctx.moveTo(20, 27.5)
                ctx.lineTo(20, 33)
                ctx.moveTo(14, 33.5)
                ctx.lineTo(26, 33.5)
                ctx.stroke()
                if (root.kind === "identify") {
                    ctx.lineWidth = 1.8
                    ctx.beginPath()
                    ctx.moveTo(20, 12)
                    ctx.lineTo(20, 23)
                    ctx.moveTo(14.5, 17.5)
                    ctx.lineTo(25.5, 17.5)
                    ctx.stroke()
                }
            } else if (root.kind === "back") {
                ctx.beginPath()
                ctx.moveTo(31, 20)
                ctx.lineTo(9, 20)
                ctx.moveTo(9, 20)
                ctx.lineTo(17, 12)
                ctx.moveTo(9, 20)
                ctx.lineTo(17, 28)
                ctx.stroke()
            } else if (root.kind === "brightness" || root.kind === "night") {
                ctx.beginPath()
                ctx.arc(20, 20, 7, 0, Math.PI * 2)
                ctx.stroke()
                for (var i = 0; i < 8; i++) {
                    var angle = i * Math.PI / 4
                    ctx.beginPath()
                    ctx.moveTo(20 + Math.cos(angle) * 11, 20 + Math.sin(angle) * 11)
                    ctx.lineTo(20 + Math.cos(angle) * 15, 20 + Math.sin(angle) * 15)
                    ctx.stroke()
                }
            } else if (root.kind === "refresh" || root.kind === "orientation") {
                ctx.beginPath()
                ctx.arc(20, 20, 10, -0.65, Math.PI * 1.45)
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(29, 8)
                ctx.lineTo(29, 14)
                ctx.lineTo(23, 13)
                ctx.stroke()
            } else if (root.kind === "adaptive") {
                ctx.beginPath()
                ctx.moveTo(4, 22)
                ctx.lineTo(10, 22)
                ctx.lineTo(13, 13)
                ctx.lineTo(17, 28)
                ctx.lineTo(21, 18)
                ctx.lineTo(24, 22)
                ctx.lineTo(36, 22)
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(31, 17)
                ctx.lineTo(36, 22)
                ctx.lineTo(31, 27)
                ctx.stroke()
            } else if (root.kind === "position") {
                ctx.beginPath()
                ctx.moveTo(20, 4)
                ctx.lineTo(20, 14)
                ctx.moveTo(20, 4)
                ctx.lineTo(16, 8)
                ctx.moveTo(20, 4)
                ctx.lineTo(24, 8)
                ctx.moveTo(36, 20)
                ctx.lineTo(26, 20)
                ctx.moveTo(36, 20)
                ctx.lineTo(32, 16)
                ctx.moveTo(36, 20)
                ctx.lineTo(32, 24)
                ctx.moveTo(20, 36)
                ctx.lineTo(20, 26)
                ctx.moveTo(20, 36)
                ctx.lineTo(16, 32)
                ctx.moveTo(20, 36)
                ctx.lineTo(24, 32)
                ctx.moveTo(4, 20)
                ctx.lineTo(14, 20)
                ctx.moveTo(4, 20)
                ctx.lineTo(8, 16)
                ctx.moveTo(4, 20)
                ctx.lineTo(8, 24)
                ctx.stroke()
                ctx.strokeRect(16, 16, 8, 8)
            } else if (root.kind === "layers") {
                for (var layer = 0; layer < 3; layer++) {
                    var offset = layer * 4
                    ctx.beginPath()
                    ctx.moveTo(20, 5 + offset)
                    ctx.lineTo(33, 12 + offset)
                    ctx.lineTo(20, 19 + offset)
                    ctx.lineTo(7, 12 + offset)
                    ctx.closePath()
                    ctx.stroke()
                }
            } else if (root.kind === "star") {
                ctx.beginPath()
                for (var starPoint = 0; starPoint < 10; starPoint++) {
                    var starAngle = -Math.PI / 2 + starPoint * Math.PI / 5
                    var starRadius = starPoint % 2 === 0 ? 15 : 7
                    var starX = 20 + Math.cos(starAngle) * starRadius
                    var starY = 20 + Math.sin(starAngle) * starRadius
                    if (starPoint === 0) ctx.moveTo(starX, starY)
                    else ctx.lineTo(starX, starY)
                }
                ctx.closePath()
                ctx.stroke()
            } else if (root.kind === "palette") {
                ctx.beginPath()
                ctx.arc(20, 20, 14, 0, Math.PI * 2)
                ctx.stroke()
                for (var dot = 0; dot < 4; dot++) {
                    var dotAngle = dot * Math.PI / 2 + Math.PI / 4
                    ctx.beginPath()
                    ctx.arc(20 + Math.cos(dotAngle) * 8, 20 + Math.sin(dotAngle) * 8, 1.6, 0, Math.PI * 2)
                    ctx.fill()
                }
            } else if (root.kind === "half") {
                ctx.beginPath()
                ctx.arc(20, 20, 13, 0, Math.PI * 2)
                ctx.stroke()
                ctx.beginPath()
                ctx.arc(20, 20, 10, -Math.PI / 2, Math.PI / 2)
                ctx.fill()
            } else if (root.kind === "temperature") {
                ctx.beginPath()
                ctx.moveTo(20, 8)
                ctx.lineTo(20, 27)
                ctx.stroke()
                ctx.beginPath()
                ctx.arc(20, 29, 6, 0, Math.PI * 2)
                ctx.fill()
                ctx.beginPath()
                ctx.moveTo(24, 13)
                ctx.lineTo(28, 13)
                ctx.moveTo(24, 18)
                ctx.lineTo(28, 18)
                ctx.moveTo(24, 23)
                ctx.lineTo(28, 23)
                ctx.stroke()
            } else if (root.kind === "power") {
                ctx.beginPath()
                ctx.arc(20, 22, 12, -Math.PI * 0.78, Math.PI * 0.78)
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(20, 5)
                ctx.lineTo(20, 20)
                ctx.stroke()
            } else if (root.kind === "info") {
                ctx.strokeRect(7, 6, 26, 28)
                ctx.beginPath()
                ctx.arc(20, 13, 1.2, 0, Math.PI * 2)
                ctx.fill()
                ctx.beginPath()
                ctx.moveTo(20, 18)
                ctx.lineTo(20, 28)
                ctx.stroke()
            } else if (root.kind === "gear") {
                ctx.beginPath()
                ctx.arc(20, 20, 7, 0, Math.PI * 2)
                ctx.stroke()
                for (var tooth = 0; tooth < 8; tooth++) {
                    var toothAngle = tooth * Math.PI / 4
                    var inner = 10
                    var outer = 15
                    ctx.beginPath()
                    ctx.moveTo(20 + Math.cos(toothAngle) * inner, 20 + Math.sin(toothAngle) * inner)
                    ctx.lineTo(20 + Math.cos(toothAngle) * outer, 20 + Math.sin(toothAngle) * outer)
                    ctx.stroke()
                }
            } else if (root.kind === "arrange") {
                ctx.strokeRect(6, 7, 11, 11)
                ctx.strokeRect(23, 7, 11, 11)
                ctx.strokeRect(6, 22, 11, 11)
                ctx.strokeRect(23, 22, 11, 11)
                ctx.beginPath()
                ctx.moveTo(19.5, 12.5)
                ctx.lineTo(21, 12.5)
                ctx.moveTo(19.5, 27.5)
                ctx.lineTo(21, 27.5)
                ctx.stroke()
            }

            ctx.restore()
        }
    }

    onKindChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onStrokeWidthChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
