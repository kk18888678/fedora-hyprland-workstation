import QtQuick
import Quickshell
import Quickshell.Io

// T38 disposable entry-point fixture. It loads only the real Microphone bar
// widget and records safe no-source state without a bar layout or PipeWire
// mutation.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_MICROPHONE_FOUNDATION_RESULT") || ""
    readonly property string microphoneSource: Quickshell.env("AURELIA_MICROPHONE_FOUNDATION_SOURCE") || ""
    property bool finished: false
    property bool microphoneLoaded: false

    QtObject {
        id: fakeAudio
        property real volume: 0.4
        property bool muted: false
    }

    QtObject {
        id: fakeSource
        property QtObject audio: fakeAudio
    }

    QtObject {
        id: fakeShell
        property int summonCalls: 0
        property string summonedPlugin: ""
        function summon(pluginId, payloadJson) {
            summonCalls++
            summonedPlugin = String(pluginId || "")
            return "ok"
        }
    }

    readonly property var fakeNodes: [
        {isStream: true, isSink: false, audio: {muted: false}},
        {isStream: true, isSink: false, audio: {muted: true}},
        {isStream: true, isSink: true, audio: {muted: false}}
    ]

    Loader {
        id: microphoneLoader
        active: root.microphoneSource !== ""
        source: root.microphoneSource
        onLoaded: root.microphoneLoaded = item !== null
    }

    Loader {
        id: noSourceLoader
        active: root.microphoneSource !== ""
        source: root.microphoneSource
        onLoaded: {
            if (!item) return
            item.trackSource = false
            item.sourceOverride = null
            item.nodesOverride = []
        }
    }

    Loader {
        id: fakeSourceLoader
        active: root.microphoneSource !== ""
        source: root.microphoneSource
        onLoaded: {
            if (!item) return
            item.trackSource = false
            item.sourceOverride = fakeSource
            item.nodesOverride = root.fakeNodes
            item.shell = fakeShell
        }
    }

    FileView {
        id: resultFile
        path: root.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: true
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    function writeResult() {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        var noSource = noSourceLoader.item
        var fake = fakeSourceLoader.item
        if (!noSource || !fake) {
            resultFile.setText(JSON.stringify({microphoneLoaded: false}) + "\n")
            return
        }

        var initialVisible = fake.visible === true
        var initialInUse = fake.inUse === true
        var initialMuted = fake.muted === true
        var initialStatusText = String(fake.statusText || "")
        fake.handleClick(Qt.LeftButton)
        var afterMuteMuted = fake.muted === true
        var afterMuteInUse = fake.inUse === true
        var afterMuteStatusText = String(fake.statusText || "")
        fake.handleClick(Qt.LeftButton)
        var afterUnmuteMuted = fake.muted === true
        var afterUnmuteInUse = fake.inUse === true
        fake.handleClick(Qt.MiddleButton)
        var afterMiddleMuted = fake.muted === true
        fakeSource.audio.volume = 0.95
        fake.handleWheel(1)
        var upperVolume = Number(fakeSource.audio.volume)
        fakeSource.audio.volume = 0.05
        fake.handleWheel(-1)
        var lowerVolume = Number(fakeSource.audio.volume)
        resultFile.setText(JSON.stringify({
            microphoneLoaded: root.microphoneLoaded && noSource !== null && fake !== null,
            noSource: {
                exposesSource: noSource.source !== undefined,
                exposesInUse: noSource.inUse !== undefined,
                exposesStatusText: noSource.statusText !== undefined,
                visible: noSource.visible === true,
                inUse: noSource.inUse === true,
                muted: noSource.muted === true,
                volume: noSource.volume !== undefined ? Number(noSource.volume) : -1
            },
            fake: {
                initialVisible: initialVisible,
                initialInUse: initialInUse,
                initialMuted: initialMuted,
                initialStatusText: initialStatusText,
                afterMuteMuted: afterMuteMuted,
                afterMuteInUse: afterMuteInUse,
                afterMuteStatusText: afterMuteStatusText,
                afterUnmuteMuted: afterUnmuteMuted,
                afterUnmuteInUse: afterUnmuteInUse,
                afterMiddleMuted: afterMiddleMuted,
                summonCalls: fakeShell.summonCalls,
                summonedPlugin: fakeShell.summonedPlugin,
                upperVolume: upperVolume,
                lowerVolume: lowerVolume
            }
        }) + "\n")
    }

    Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: root.writeResult()
    }
}
