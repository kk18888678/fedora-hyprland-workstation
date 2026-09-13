import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "../../ui"
import "../../theme"
import "Model.js" as Model

// T36 anchored Audio panel foundation. T37 extends this same owner with the
// complete output/input/stream sections without changing the plugin identity.
AureliaKeyboardPanel {
    id: root

    property var audioWidget: null
    property var shell: null

    readonly property var sink: audioWidget && audioWidget.sink
        ? audioWidget.sink : Pipewire.defaultAudioSink
    readonly property var source: audioWidget && audioWidget.source
        ? audioWidget.source : Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
    readonly property real outputVolume: sink && sink.audio ? Number(sink.audio.volume || 0) : 0
    readonly property real inputVolume: source && source.audio ? Number(source.audio.volume || 0) : 0
    readonly property bool outputMuted: !!(sink && sink.audio && sink.audio.muted)
    readonly property bool inputMuted: !!(source && source.audio && source.audio.muted)

    ownerId: "aurelia.audio"
    popupWidth: 380
    popupHeight: 220
    fitHeightToContent: true
    minPopupHeight: 180
    maxPopupHeight: 560
    contentSizingItem: contentColumn
    shown: false

    function open(payloadJson) {
        root.shown = true
        return "ok"
    }

    function close() {
        root.shown = false
        return "ok"
    }

    function toggle(payloadJson) {
        return root.shown ? root.close() : root.open(payloadJson || "{}")
    }

    function isVisible() {
        return root.shown === true
    }

    function outputGlyph() {
        if (root.outputMuted) return "󰝟"
        return Model.sinkGlyph(root.sink)
    }

    function setOutputVolume(value) {
        if (!root.sink || !root.sink.audio) return root.outputVolume
        var bounded = Math.max(0, Math.min(1, Number(value) || 0))
        root.sink.audio.volume = bounded
        return bounded
    }

    function setInputVolume(value) {
        if (!root.source || !root.source.audio) return root.inputVolume
        var bounded = Math.max(0, Math.min(1, Number(value) || 0))
        root.source.audio.volume = bounded
        return bounded
    }

    function toggleOutputMute() {
        if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
    }

    function toggleInputMute() {
        if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: Theme.spacingSm

        Text {
            Layout.fillWidth: true
            text: "Audio"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLg
            font.weight: Theme.fontWeightBold
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: root.outputGlyph()
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
            }
            Text {
                Layout.fillWidth: true
                text: Model.outputVolumeName(root.outputVolume, root.outputMuted)
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
            Text {
                text: Math.round(root.outputVolume * 100) + "%"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
        }

        Slider {
            Layout.fillWidth: true
            from: 0
            to: 1
            stepSize: 0.05
            value: root.outputVolume
            enabled: !!root.sink
            onMoved: root.setOutputVolume(value)
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: root.source && root.source.audio
                    ? "Input " + Math.round(root.inputVolume * 100) + "%"
                    : "No input source"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
            Text {
                text: root.inputMuted ? "Muted" : "Live"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
        }
    }
}
