import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../theme"

Item {
    id: root

    property var bar: null
    property var shell: null
    property string moduleName: "aurelia.power"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    readonly property var powerPanel: panelLoader.item

    implicitWidth: bar ? bar.barSize : 32
    implicitHeight: bar ? bar.barSize : 32

    function open() {
        if (powerPanel && typeof powerPanel.open === "function") powerPanel.open()
        return "ok"
    }

    function close() {
        if (powerPanel && typeof powerPanel.close === "function") powerPanel.close()
        return "ok"
    }

    function toggle() {
        if (powerPanel && powerPanel.visible) return close()
        return open()
    }

    function isVisible() {
        return powerPanel && powerPanel.visible === true
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("PowerPanel.qml")
        onLoaded: {
            if ("barSize" in item) item.barSize = root.bar ? root.bar.barSize : 32
            if ("anchorWindow" in item) item.anchorWindow = root.bar
        }
    }

    onBarChanged: {
        if (panelLoader.item && "anchorWindow" in panelLoader.item) panelLoader.item.anchorWindow = root.bar
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: powerHover.hovered ? Theme.selection : "transparent"

        HoverHandler { id: powerHover }

        IconImage {
            anchors.centerIn: parent
            width: 18
            height: 18
            source: Quickshell.iconPath("system-shutdown", "system-power-off")
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                mouse.accepted = true
                root.toggle()
            }
        }
    }
}
