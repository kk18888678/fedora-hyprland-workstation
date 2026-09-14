import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../../theme"
import "../../ui"
import "Model.js" as Model

// Omarchy-aligned Audio bar affordance. PipeWire owns live objects and the
// panel remains behind the normal host Loader boundary.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string moduleName: "aurelia.audio"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var barAnchorItem: null

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
    readonly property bool audioAvailable: !!(root.sink || root.source)
    readonly property bool outputMuted: !!(root.sink && root.sink.audio && root.sink.audio.muted)
    readonly property real outputVolume: root.sink && root.sink.audio ? Number(root.sink.audio.volume || 0) : 0
    readonly property bool panelVisible: !!(panelLoader.item && panelLoader.item.shown === true)
    readonly property color barForeground: root.bar && root.bar.barForeground !== undefined
        ? root.bar.barForeground : Theme.text

    implicitWidth: root.audioAvailable ? (root.bar ? root.bar.barSize : 32) : 0
    implicitHeight: root.bar ? root.bar.barSize : 32
    visible: root.audioAvailable

    function outputGlyph() {
        return Model.outputBarGlyph(root.sink, root.outputVolume, root.outputMuted)
    }

    function configurePanel(target) {
        if (!target) return
        if ("audioWidget" in target) target.audioWidget = root
        if ("bar" in target) target.bar = root.bar
        if ("shell" in target) target.shell = root.shell
        if ("anchorItem" in target) target.anchorItem = root.barAnchorItem || root
    }

    function open(payloadJson) {
        if (!panelLoader.item || typeof panelLoader.item.open !== "function") return "not-ready"
        root.configurePanel(panelLoader.item)
        return panelLoader.item.open(payloadJson || "{}")
    }

    function close() {
        if (!panelLoader.item || typeof panelLoader.item.close !== "function") return "not-ready"
        return panelLoader.item.close()
    }

    function toggle(payloadJson) {
        return root.panelVisible ? root.close() : root.open(payloadJson || "{}")
    }

    function isVisible() {
        return root.panelVisible
    }

    function toggleMute() {
        if (panelLoader.item && typeof panelLoader.item.toggleAllMuted === "function") {
            panelLoader.item.toggleAllMuted()
            return
        }
        if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
    }

    function adjustOutput(delta) {
        if (!root.sink || !root.sink.audio) return
        root.sink.audio.volume = Model.steppedVolume(root.outputVolume, delta, 1)
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("AudioPanel.qml")
        onLoaded: root.configurePanel(item)
        onStatusChanged: {
            if (status === Loader.Error) console.error("[AUDIO] panel_load_failed")
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: audioHover.hovered || root.panelVisible ? Theme.selection : "transparent"

        HoverHandler { id: audioHover }

        AureliaIcon {
            anchors.centerIn: parent
            width: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            height: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            iconSize: root.bar && root.bar.barIconFont ? root.bar.barIconFont : 13
            glyph: root.outputGlyph()
            tint: root.panelVisible ? Theme.accent : root.barForeground
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                mouse.accepted = true
                if (mouse.button === Qt.RightButton) root.toggleMute()
                else if (mouse.button === Qt.MiddleButton) root.open("{}")
                else if (mouse.button === Qt.LeftButton) root.open("{}")
            }
            onWheel: function(wheel) {
                wheel.accepted = true
                root.adjustOutput(wheel.angleDelta.y > 0 ? 0.05 : -0.05)
            }
        }
    }
}
