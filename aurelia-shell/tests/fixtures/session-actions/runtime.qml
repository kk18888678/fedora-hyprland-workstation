import QtQuick
import Quickshell
import Quickshell.Io

// T47 runtime fixture. The injected executor records argv and returns a
// deterministic result; no session command is launched by this test.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_SESSION_RUNTIME_RESULT") || ""
    readonly property string runtimeSource: Quickshell.env("AURELIA_SESSION_RUNTIME_SOURCE") || ""
    property bool finished: false

    QtObject {
        id: fakeOwner
        property bool actionRunning: false
        property string actionError: ""
        property var calls: []
        property var actionExecutor
    }

    Loader {
        id: runtimeLoader
        onLoaded: {
            if (!item) return
            item.owner = fakeOwner
            fakeOwner.actionExecutor = function(argv, actionId) {
                fakeOwner.calls.push({argv: argv.slice(), actionId: String(actionId)})
                return "ok"
            }
            var success = item.runCommand(["/usr/bin/loginctl", "lock-session"], "lock")
            fakeOwner.actionExecutor = function(argv, actionId) {
                fakeOwner.calls.push({argv: argv.slice(), actionId: String(actionId)})
                return "error"
            }
            var failure = item.runCommand(["/usr/bin/systemctl", "poweroff"], "shutdown")
            var invalid = item.runCommand([], "invalid")
            root.writeResult({
                loaded: true,
                success: success,
                failure: failure,
                invalid: invalid,
                actionError: fakeOwner.actionError,
                calls: fakeOwner.calls,
                processRunning: item.actionProcess.running === true
            })
        }

        Component.onCompleted: if (root.runtimeSource !== "") runtimeLoader.source = root.runtimeSource
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

    function writeResult(value) {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        resultFile.setText(JSON.stringify(value) + "\n")
    }

    Timer {
        interval: 1200
        running: true
        repeat: false
        onTriggered: if (!root.finished) root.writeResult({loaded: false})
    }
}
