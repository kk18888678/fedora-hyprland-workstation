import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../ui"
import "../../theme"

// The Display widget is deliberately thin. It owns the bar affordance and
// delegates state, actions, and keyboard navigation to DisplayPanel.qml.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string aureliaPath: ""
    property string moduleName: "aurelia.monitor"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var barAnchorItem: null
    property real wheelAccumulator: 0

    readonly property var displayPanel: panelLoader.item
    readonly property string sourceBinRoot: decodeURIComponent(
        String(Qt.resolvedUrl("../../bin")).replace(/^file:\/\//, "")
    )
    // This is a first-party source plugin. Resolve its sibling backend tree
    // directly so a stale/absent host injection cannot silently select the
    // production-only /usr/local/bin path during checkout development.
    readonly property string backendRoot: sourceBinRoot

    function configurePanel(target) {
        if (!target) return
        if ("bar" in target) target.bar = root.bar
        if ("anchorItem" in target) target.anchorItem = root.barAnchorItem || root
        if ("backendRoot" in target) target.backendRoot = root.backendRoot
    }

    implicitWidth: bar ? bar.barSize : 32
    implicitHeight: bar ? bar.barSize : 32

    function open(payloadJson) {
        if (!displayPanel) return "not-ready"
        displayPanel.open(payloadJson || "{}")
        return "ok"
    }

    function close() {
        if (!displayPanel) return "not-ready"
        displayPanel.close()
        return "ok"
    }

    function closeForPopoutSwitch() { close() }

    function toggle(payloadJson) {
        if (displayPanel && displayPanel.shown) return close()
        return open(payloadJson || "{}")
    }

    function isVisible() {
        return !!displayPanel && displayPanel.shown === true
    }

    function wheelBrightness(delta) {
        if (!displayPanel || !displayPanel.brightnessAvailable) return
        var steps = Math.trunc((root.wheelAccumulator + Number(delta || 0)) / 120)
        root.wheelAccumulator = root.wheelAccumulator + Number(delta || 0) - steps * 120
        if (steps === 0) return
        displayPanel.adjustBrightness(steps * 5)
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("DisplayPanel.qml")
        onLoaded: root.configurePanel(item)
        onStatusChanged: {
            if (status === Loader.Error) console.error("[DISPLAY] panel_load_failed")
        }
    }

    onBarChanged: {
        root.configurePanel(panelLoader.item)
    }

    onAureliaPathChanged: root.configurePanel(panelLoader.item)
    onBarAnchorItemChanged: root.configurePanel(panelLoader.item)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: displayHover.hovered || root.isVisible() ? Theme.selection : "transparent"

        HoverHandler { id: displayHover }

        AureliaIcon {
            anchors.centerIn: parent
            width: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            height: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            iconSize: root.bar && root.bar.barIconFont ? root.bar.barIconFont : 13
            glyph: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
            tint: root.isVisible() ? Theme.accent : Theme.textSecondary
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                mouse.accepted = true
                root.toggle("{}")
            }
            onWheel: function(wheel) {
                wheel.accepted = true
                root.wheelBrightness(wheel.angleDelta.y)
            }
        }
    }
}
