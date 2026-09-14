import QtQuick
import Quickshell
import Quickshell.Io

// T55 first-run ShellConfig fixture. The configured XDG tree intentionally
// has no shell.json; the real owner must bootstrap it without a missing-file
// FileView warning and expose a ready canonical in-memory state.
ShellRoot {
    id: root

    readonly property string configSource: Quickshell.env("AURELIA_OPTIONAL_SHELL_CONFIG_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_OPTIONAL_SHELL_CONFIG_RESULT") || ""
    property var state: null
    property bool finished: false

    Loader {
        id: stateLoader
        source: root.configSource
        onLoaded: root.state = item
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

    function finish() {
        if (root.finished || !root.state) return
        if (!root.state.configFileReady) return
        root.finished = true
        var raw = ""
        try { raw = root.state.configFile.text() }
        catch (error) { console.error("[TEST] optional shell config read failed") }
        resultFile.setText(JSON.stringify({
            ready: root.state.configFileReady,
            rawNonEmpty: raw.trim() !== "",
            configHasBar: !!(root.state.config && root.state.config.bar),
            configPath: root.state.configPath,
            bootstrapAttempted: root.state.configBootstrapAttempted,
            lastError: root.state.lastError
        }) + "\n")
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: root.finish()
    }

    Timer {
        interval: 8000
        repeat: false
        running: true
        onTriggered: Qt.quit()
    }
}
