import QtQuick
import Quickshell
import Quickshell.Io

// T52 runtime fixture. It exercises the real Process lifecycle with harmless
// true/false commands; no session command is launched by this test.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_SESSION_RUNTIME_RESULT") || ""
    readonly property string runtimeSource: Quickshell.env("AURELIA_SESSION_RUNTIME_SOURCE") || ""
    property bool finished: false
    property int phase: 0
    property string success: ""
    property string failure: ""
    property string invalid: ""
    property int successExit: -1
    property int failureExit: -1

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
            item.testMode = true
            item.testCommand = ["/usr/bin/true"]
            root.success = item.runCommand(["/usr/bin/loginctl", "lock-session"], "lock")
            root.invalid = item.runCommand([], "invalid")
            root.phase = 1
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
        printErrors: true
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

    Connections {
        target: runtimeLoader.item ? runtimeLoader.item.actionProcess : null
        function onExited(code) {
            if (!runtimeLoader.item) return
            if (root.phase === 1) {
                root.successExit = code
                runtimeLoader.item.testCommand = ["/usr/bin/false"]
                root.failure = runtimeLoader.item.runCommand(
                    ["/usr/bin/systemctl", "poweroff"], "shutdown")
                root.phase = 2
            } else if (root.phase === 2) {
                root.failureExit = code
                root.writeResult({
                    loaded: true,
                    success: root.success,
                    failure: root.failure,
                    invalid: root.invalid,
                    successExit: root.successExit,
                    failureExit: root.failureExit,
                    actionError: fakeOwner.actionError,
                    calls: fakeOwner.calls,
                    processRunning: runtimeLoader.item.actionProcess.running === true
                })
            }
        }
    }
}
