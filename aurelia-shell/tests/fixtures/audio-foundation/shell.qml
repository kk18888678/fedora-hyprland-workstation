import QtQuick
import Quickshell
import Quickshell.Io

// T36 disposable entry-point fixture. The real Audio bar widget is loaded with
// no bar configuration, no default-layout mutation, and no audio control call.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_AUDIO_FOUNDATION_RESULT") || ""
    readonly property string audioSource: Quickshell.env("AURELIA_AUDIO_FOUNDATION_SOURCE") || ""
    property bool finished: false
    property bool audioLoaded: false

    Loader {
        id: audioLoader
        active: root.audioSource !== ""
        source: root.audioSource
        onLoaded: root.audioLoaded = item !== null
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
        var audio = audioLoader.item
        resultFile.setText(JSON.stringify({
            audioLoaded: root.audioLoaded,
            audioAvailable: !!(audio && audio.audioAvailable !== undefined && audio.audioAvailable),
            exposesAudioAvailability: !!(audio && audio.audioAvailable !== undefined),
            exposesPanelVisibility: !!(audio && audio.panelVisible !== undefined),
            panelVisible: !!(audio && audio.panelVisible === true)
        }) + "\n")
    }

    Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: root.writeResult()
    }
}
