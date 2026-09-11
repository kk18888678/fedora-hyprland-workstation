import QtQuick
import "../../theme"
import "../../ui"

Item {
    id: root

    property var bar: null
    property var shell: null
    property string moduleName: "aurelia.power"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var barAnchorItem: null
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
            if ("barSize" in item) item.barSize = root.bar ? root.bar.barSize : 26
            if ("bar" in item) item.bar = root.bar
            if ("anchorItem" in item) item.anchorItem = root.barAnchorItem || root
        }
    }

    onBarChanged: {
        if (panelLoader.item && "bar" in panelLoader.item) panelLoader.item.bar = root.bar
        if (panelLoader.item && "anchorItem" in panelLoader.item) panelLoader.item.anchorItem = root.barAnchorItem || root
    }

    onBarAnchorItemChanged: {
        if (panelLoader.item && "anchorItem" in panelLoader.item) panelLoader.item.anchorItem = root.barAnchorItem || root
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: powerHover.hovered ? Theme.selection : "transparent"

        HoverHandler { id: powerHover }

        AureliaIcon {
            anchors.centerIn: parent
            width: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            height: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            iconSize: root.bar && root.bar.barIconFont ? root.bar.barIconFont : 13
            name: "system-shutdown"
            fallbackName: "system-power-off"
            tint: powerHover.hovered ? Theme.text : Theme.textSecondary
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
