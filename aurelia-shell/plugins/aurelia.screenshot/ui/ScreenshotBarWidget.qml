import QtQuick
import "../../../theme"
import "../../../ui"

// Screenshot is a first-class bar affordance only.
//
// The capture state machine, the bounded capture Process over
// bin/aurelia-screenshot, the region-selection overlay, the menu popup, and
// the notification publish all live in the resident core ScreenshotService.
// This view deliberately owns no Process, no overlay/menu loading, no
// controller state, and no notification call, so disabling this widget,
// removing it from the bar layout, or uninstalling the plugin can never
// unregister the SUPER+SHIFT+R/S shortcut capability.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string aureliaPath: ""
    property string moduleName: "aurelia.screenshot"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var barAnchorItem: null

    // Uniform bar-icon contract: one 16 px ink canvas scaled by the bar, no
    // literal sizes. Screenshot has no alert state, so the glyph rests at the
    // bar foreground colour.
    readonly property color barForeground: root.bar && root.bar.barForeground !== undefined
        ? root.bar.barForeground : Theme.text
    readonly property int iconCanvas: root.bar && root.bar.barIconCanvas
        ? root.bar.barIconCanvas : Theme.bar.iconCanvas
    // Active state mirrors the bar's single-popout owner. The core menu popup
    // requests ownership with this plugin id, so the affordance reflects the
    // live capture surface without polling the IPC and without owning state.
    readonly property bool active: !!root.bar && root.bar.activePopoutId === "aurelia.screenshot"

    implicitWidth: bar ? bar.barSize : 38
    implicitHeight: bar ? bar.barSize : 38

    function invokeCore(method, payloadJson) {
        if (!root.shell || typeof root.shell.call !== "function") {
            console.error("[SCREENSHOT] widget_core_call_unavailable method=" + String(method || ""))
            return "not-loaded"
        }
        return String(root.shell.call("aurelia.screenshot", String(method || ""),
            String(payloadJson || "{}")) || "")
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: (hover.hovered || root.active) ? Theme.selection : "transparent"

        HoverHandler { id: hover }

        AureliaIcon {
            anchors.centerIn: parent
            width: root.iconCanvas
            height: root.iconCanvas
            iconSize: root.iconCanvas
            glyph: "󰄀"
            tint: root.barForeground
        }

        AureliaToolTip {
            id: screenshotToolTip
            triggerItem: root
            bar: root.bar
            hovered: hover.hovered
            text: "Screenshots · Full Screen or Selection"
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                mouse.accepted = true
                root.invokeCore(root.active ? "close" : "open", "{\"mode\":\"menu\"}")
            }
        }
    }
}
