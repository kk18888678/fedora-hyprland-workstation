import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../../theme"

// The screenshot action is a bar-widget entry point of the screenshot plugin.
// It loads the capture surface internally instead of creating a second
// Quickshell process or exposing the capture panel as a standalone plugin.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string aureliaPath: ""
    property string moduleName: "aurelia.screenshot"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    readonly property var capturePlugin: captureLoader.item

    implicitWidth: bar ? bar.barSize : 38
    implicitHeight: bar ? bar.barSize : 38

    function configureCapturePlugin(target) {
        if (!target) return
        if ("aureliaPath" in target) target.aureliaPath = root.aureliaPath
        if ("shell" in target) target.shell = root.shell
        if ("bar" in target) target.bar = root.bar
        if ("barSize" in target) target.barSize = root.bar ? root.bar.barSize : 26
        if ("manifest" in target) target.manifest = root.manifest
        if ("pluginRegistry" in target) target.pluginRegistry = root.pluginRegistry
    }

    function open(payloadJson) {
        if (!capturePlugin || typeof capturePlugin.open !== "function") return "pending"
        return capturePlugin.open(payloadJson || "{}")
    }

    function close() {
        if (capturePlugin && typeof capturePlugin.close === "function") capturePlugin.close()
        return "ok"
    }

    function toggle(payloadJson) {
        if (isVisible()) return close()
        return open(payloadJson || "{}")
    }

    function isVisible() {
        return capturePlugin && typeof capturePlugin.isVisible === "function" && capturePlugin.isVisible()
    }

    function quickRegion() {
        if (!capturePlugin || typeof capturePlugin.quickRegion !== "function") return "not-ready"
        return capturePlugin.quickRegion()
    }

    Loader {
        id: captureLoader
        active: true
        source: Qt.resolvedUrl("../ScreenshotPlugin.qml")
        onLoaded: root.configureCapturePlugin(item)
        onStatusChanged: {
            if (status === Loader.Error) console.warn("[SCREENSHOT] bar_capture_plugin_load_failed")
        }
    }

    onAureliaPathChanged: root.configureCapturePlugin(captureLoader.item)
    onShellChanged: root.configureCapturePlugin(captureLoader.item)
    onManifestChanged: root.configureCapturePlugin(captureLoader.item)
    onPluginRegistryChanged: root.configureCapturePlugin(captureLoader.item)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: hover.hovered ? Theme.selection : "transparent"

        HoverHandler { id: hover }

        IconImage {
            anchors.centerIn: parent
            width: 18
            height: 18
            source: Quickshell.iconPath("camera-photo", "camera")
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                mouse.accepted = true
                root.open("{\"mode\":\"menu\"}")
            }
        }
    }
}
