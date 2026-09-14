import QtQuick
import Quickshell
import Quickshell.Io

// T45 headless watcher fixture. It loads the real non-visual watcher and
// observes actual parent-directory events without constructing a PanelWindow.
ShellRoot {
    id: root

    readonly property string watcherSource: Quickshell.env("AURELIA_BAR_WATCHER_SOURCE") || ""
    readonly property string watchDirectory: Quickshell.env("AURELIA_BAR_WATCHER_DIRECTORY") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_BAR_WATCHER_RESULT") || ""
    property var watcher: null
    property int syncEvents: 0
    property bool finished: false

    Loader {
        id: watcherLoader
        source: root.watcherSource
        onLoaded: {
            if (!item) return
            item.directory = root.watchDirectory
            item.active = true
            root.watcher = item
            writeEventTimer.start()
        }
    }

    Connections {
        target: root.watcher
        function onSyncRequested(path) {
            if (String(path || "") !== "") root.syncEvents++
        }
    }

    Process {
        id: createProcess
        command: root.watchDirectory === "" ? [] : ["/usr/bin/bash", "-c",
            "printf '%s\\n' hidden >\"$1/bar-off\"; rm -f -- \"$1/bar-off\"",
            "aurelia-bar-watcher-fixture", root.watchDirectory]
        running: false
        onExited: resultTimer.start()
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

    function writeEventResult() {
        if (!root.watcher || root.watchDirectory === "") return
        createProcess.running = true
    }

    function writeResult() {
        if (root.finished) return
        root.finished = true
        resultFile.setText(JSON.stringify({
            loaded: root.watcher !== null,
            watcherAvailable: root.watcher !== null && root.watcher.unavailable !== true,
            syncEvents: root.syncEvents
        }) + "\n")
    }

    Timer {
        id: writeEventTimer
        interval: 300
        repeat: false
        onTriggered: root.writeEventResult()
    }

    Timer {
        id: resultTimer
        interval: 500
        repeat: false
        onTriggered: root.writeResult()
    }

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: root.writeResult()
    }
}
