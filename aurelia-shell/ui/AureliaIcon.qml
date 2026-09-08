import QtQuick
import QtQuick.Effects
import Quickshell
import "../theme"

// Monochrome theme-aware icon primitive. System theme icons are rendered into
// a hidden source layer and colorized with Aurelia's semantic foreground, so
// icons remain legible on both primary and selected surfaces.
Item {
    id: root

    property string name: "application-x-executable"
    property color tint: Theme.text
    property real iconSize: 18

    implicitWidth: iconSize
    implicitHeight: iconSize

    Image {
        id: iconSource
        anchors.fill: parent
        visible: false
        layer.enabled: true
        source: root.name !== ""
            ? Quickshell.iconPath(root.name, "application-x-executable")
            : ""
        sourceSize: Qt.size(Math.max(1, Math.round(root.width)), Math.max(1, Math.round(root.height)))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }

    MultiEffect {
        anchors.fill: iconSource
        source: iconSource
        visible: root.name !== ""
        colorization: 1.0
        colorizationColor: root.tint
    }
}
