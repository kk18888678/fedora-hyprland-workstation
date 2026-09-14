import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../../theme"
import "../../ui"
import "../aurelia.audio/Model.js" as Model

// Optional Microphone bar affordance. PipeWire owns the live source and
// capture nodes; the widget only presents bounded state and delegates the
// Audio panel transition to the resident shell API.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string moduleName: "aurelia.microphone"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var barAnchorItem: null
    // The override seam is unused in production. It lets the isolated QML
    // fixture drive this exact widget with deterministic source/node objects
    // without connecting to or mutating the live PipeWire graph.
    property var sourceOverride
    property var nodesOverride
    property bool trackSource: true

    readonly property var source: root.sourceOverride !== undefined
        ? root.sourceOverride : Pipewire.defaultAudioSource
    readonly property var nodes: root.nodesOverride !== undefined
        ? root.nodesOverride : (Pipewire.nodes && Pipewire.nodes.values
            ? Pipewire.nodes.values : [])
    readonly property bool hasSource: !!root.source
    readonly property bool muted: Model.microphoneMuted(root.source)
    readonly property real volume: Model.microphoneVolume(root.source)
    readonly property bool inUse: Model.microphoneInUse(root.source, root.nodes)
    readonly property string statusText: root.muted
        ? "Microphone muted"
        : (root.inUse ? "Microphone in use" : "Microphone live")
    readonly property color barForeground: root.bar && root.bar.barForeground !== undefined
        ? root.bar.barForeground : Theme.text

    implicitWidth: root.hasSource ? (root.bar ? root.bar.barSize : 32) : 0
    implicitHeight: root.bar ? root.bar.barSize : 32
    visible: root.hasSource

    function toggleMute() {
        if (root.source && root.source.audio)
            root.source.audio.muted = !root.source.audio.muted
    }

    function summonAudio() {
        if (!root.shell || typeof root.shell.summon !== "function") return "not-ready"
        return String(root.shell.summon("aurelia.audio", "{}") || "ok")
    }

    function adjustInput(delta) {
        if (!root.source || !root.source.audio) return root.volume
        var bounded = Model.stepInputVolume(root.volume, delta)
        root.source.audio.volume = bounded
        return bounded
    }

    function handleClick(button) {
        if (button === Qt.MiddleButton) return root.summonAudio()
        root.toggleMute()
        return "ok"
    }

    function handleWheel(delta) {
        return root.adjustInput(Number(delta) > 0 ? 0.05 : -0.05)
    }

    PwObjectTracker {
        objects: root.trackSource && root.source ? [root.source] : []
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: microphoneHover.hovered || root.inUse ? Theme.selection : "transparent"

        HoverHandler { id: microphoneHover }

        AureliaIcon {
            anchors.centerIn: parent
            width: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            height: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            iconSize: root.bar && root.bar.barIconFont ? root.bar.barIconFont : 13
            glyph: Model.microphoneGlyph(root.muted)
            tint: root.inUse ? Theme.accent : root.barForeground
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                mouse.accepted = true
                root.handleClick(mouse.button)
            }
            onWheel: function(wheel) {
                wheel.accepted = true
                root.handleWheel(wheel.angleDelta.y)
            }
        }
    }

    AureliaToolTip {
        triggerItem: root
        bar: root.bar
        hovered: microphoneHover.hovered
        text: root.statusText
    }
}
