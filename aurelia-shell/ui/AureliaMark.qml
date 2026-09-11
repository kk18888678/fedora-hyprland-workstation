import QtQuick
import QtQuick.Shapes
import "../theme"

// Small vector-only Aurelia mark for layer-shell UI. Keeping the orbital paths
// in Shape avoids rasterizing a large gradient SVG and then recoloring it in a
// texture at bar size. The mark remains theme-aware without sacrificing the
// high-frequency edges that make a 20px icon readable.
Item {
    id: root

    property color color: Theme.accent
    property color coreColor: Theme.gold
    readonly property real markScale: Math.min(width, height) / 256

    Shape {
        id: markShape
        anchors.centerIn: parent
        width: 256
        height: 256
        scale: root.markScale
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.color
            strokeWidth: 18
            fillColor: "transparent"
            capStyle: ShapePath.SquareCap
            pathHints: ShapePath.PathSolid
            PathSvg { path: "M48 101a88 88 0 1 1 107 107" }
        }

        ShapePath {
            strokeColor: root.color
            strokeWidth: 14
            fillColor: "transparent"
            capStyle: ShapePath.SquareCap
            pathHints: ShapePath.PathSolid
            PathSvg { path: "M76 119a58 58 0 1 1 61 61" }
        }

        ShapePath {
            strokeColor: root.color
            strokeWidth: 10
            fillColor: "transparent"
            capStyle: ShapePath.SquareCap
            pathHints: ShapePath.PathSolid
            PathSvg { path: "M103 128a25 25 0 1 1 25 25" }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 24 * root.markScale
        height: width
        radius: width / 2
        color: root.coreColor
    }
}
