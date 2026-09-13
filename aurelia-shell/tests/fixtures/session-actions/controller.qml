import QtQuick
import Quickshell
import Quickshell.Io

// T49 controller fixture. It loads the production non-visual controller and
// injects a fake runtime, so all confirmation transitions are exercised
// without creating a PanelWindow or executing a session command.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_SESSION_CONTROLLER_RESULT") || ""
    readonly property string controllerSource: Quickshell.env("AURELIA_SESSION_CONTROLLER_SOURCE") || ""
    property bool finished: false

    QtObject {
        id: fakeRuntime
        property var calls: []

        function runCommand(argv, actionId) {
            calls = calls.concat([{argv: argv.slice(), actionId: String(actionId)}])
            return "ok"
        }
    }

    QtObject {
        id: fakeOwner
        property bool shown: false
        property string confirmAction: ""
        property string actionError: ""
        property int actionIndex: 0
        property bool cursorActive: false
        property bool actionRunning: false
        property var visibleActionRows: []
        property var runtime: fakeRuntime
    }

    Loader {
        id: controllerLoader
        source: root.controllerSource
        onLoaded: {
            if (!item) return
            item.owner = fakeOwner

            var actionIds = ["lock", "logout", "suspend", "reboot", "shutdown"]
            var checks = []
            for (var i = 0; i < actionIds.length; i++) {
                var actionId = actionIds[i]
                item.open("{}")
                var requested = item.requestAction(actionId)
                var pending = fakeOwner.confirmAction
                var beforeCancel = fakeRuntime.calls.length
                var canceled = item.cancelPendingAction()
                var afterCancel = fakeRuntime.calls.length
                item.open("{}")
                var requestedAgain = item.requestAction(actionId)
                var confirmed = item.confirmPendingAction()
                var afterConfirm = fakeRuntime.calls.length
                checks.push({
                    id: actionId,
                    request: requested,
                    pending: pending,
                    cancel: canceled,
                    callsBeforeCancel: beforeCancel,
                    callsAfterCancel: afterCancel,
                    requestAgain: requestedAgain,
                    confirm: confirmed,
                    callsAfterConfirm: afterConfirm
                })
            }

            item.open("{}")
            var directRunCallsBefore = fakeRuntime.calls.length
            var directRun = item.runAction("lock")
            var directRunPending = fakeOwner.confirmAction
            var directRunCallsAfter = fakeRuntime.calls.length
            item.cancelPendingAction()

            root.writeResult({
                loaded: true,
                checks: checks,
                calls: fakeRuntime.calls,
                directRun: directRun,
                directRunPending: directRunPending,
                directRunCallsBefore: directRunCallsBefore,
                directRunCallsAfter: directRunCallsAfter
            })
        }
        onStatusChanged: if (status === Loader.Error) root.writeResult({loaded: false})
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
        interval: 5000
        running: true
        repeat: false
        onTriggered: if (!root.finished) root.writeResult({loaded: false})
    }
}
