import QtQuick
import Quickshell
import Quickshell.Io

// T59 real CommandCenterModel fixture. It injects only a failing backend;
// production model activation and failure presentation remain under test.
ShellRoot {
    id: root

    readonly property string modelSource: Quickshell.env("AURELIA_COMMAND_CENTER_MODEL_SOURCE") || ""
    readonly property string backendSource: Quickshell.env("AURELIA_COMMAND_CENTER_MODEL_BACKEND") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_COMMAND_CENTER_MODEL_RESULT") || ""
    property var model: null
    property bool finished: false

    Loader {
        id: modelLoader
        source: root.modelSource
        onLoaded: {
            root.model = item
            item.backendBin = root.backendSource
            item.results = [{
                id: "app:foot.desktop",
                kind: "app",
                appId: "foot.desktop",
                label: "Foot",
                subtitle: "Terminal",
                detail: "Applications"
            }]
            item.selectedIndex = 0
            item.activateSelected()
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

    Connections {
        target: root.model
        function onLaunchFinished(success, message) {
            if (root.finished || !root.model) return
            root.finished = true
            resultFile.setText(JSON.stringify({
                success: success,
                message: String(message || ""),
                errorMessage: String(root.model.errorMessage || ""),
                statusMessage: String(root.model.statusMessage || "")
            }) + "\n")
        }
    }

    Timer {
        interval: 7000
        repeat: false
        running: true
        onTriggered: Qt.quit()
    }
}
