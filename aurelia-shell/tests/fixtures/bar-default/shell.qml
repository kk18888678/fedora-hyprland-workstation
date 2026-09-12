import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    readonly property string sourcePath: Quickshell.env("AURELIA_BAR_DEFAULT_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_BAR_DEFAULT_RESULT") || ""
    property var defaults: null
    property bool evaluated: false

    Loader {
        id: defaultsLoader
        source: root.sourcePath
        onLoaded: {
            root.defaults = item
            evaluateTimer.start()
        }
    }

    FileView {
        id: resultFile
        path: root.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: false
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    Timer {
        id: evaluateTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (root.evaluated || !root.defaults || root.resultPath === "") return
            root.evaluated = true
            var value = root.defaults.copy()
            resultFile.setText(JSON.stringify({
                loaded: root.defaults.loaded,
                id: value.id,
                position: value.position,
                centerAnchor: value.centerAnchor,
                left: value.layout.left.map(function(entry) { return entry.id }),
                center: value.layout.center.map(function(entry) { return entry.id }),
                right: value.layout.right.map(function(entry) { return entry.id })
            }) + "\n")
        }
    }

    Timer {
        interval: 9000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
