import QtQuick
import Quickshell
import Quickshell.Io

// T47 panel fixture. It loads the real SessionActionsPanel entry point and
// injects an executor before exercising actions; destructive commands never
// reach a production Process.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_SESSION_PANEL_RESULT") || ""
    readonly property string panelSource: Quickshell.env("AURELIA_SESSION_PANEL_SOURCE") || ""
    property bool finished: false
    property bool panelLoaded: false
    property bool panelFailed: false

    QtObject {
        id: fakeBar
        property int barSize: 26
        property int barIconCanvas: 16
        property int barIconFont: 13
        property bool vertical: false
        function anchorItemFor(id) { return null }
        function requestPopout(panel, ownerId) {}
        function releasePopout(panel) {}
    }

    QtObject {
        id: fakeShell
        function updateEntryInline(id, settings, selector) { return "ok" }
    }

    Loader {
        id: panelLoader
        source: root.panelSource
        onLoaded: {
            if (!item) return
            root.panelLoaded = true
            item.bar = fakeBar
            item.shell = fakeShell
            var calls = []
            item.actionExecutor = function(argv, actionId) {
                calls.push({argv: argv.slice(), actionId: String(actionId)})
                return "ok"
            }
            var openResult = item.open("{}")
            var confirmationResult = item.requestAction("shutdown")
            var pendingAction = item.confirmAction
            var cancelResult = item.cancelPendingAction()
            var lockResult = item.requestAction("lock")
            var lockPendingAction = item.confirmAction
            var preConfirmationCalls = calls.length
            item.cancelPendingAction()
            var directRunResult = item.runAction("lock")
            var directRunPendingAction = item.confirmAction
            var directRunCalls = calls.length
            item.cancelPendingAction()

            var actionIds = ["lock", "logout", "suspend", "reboot", "shutdown"]
            var confirmationChecks = []
            var confirmedActions = []
            var actionExecutions = 0
            for (var i = 0; i < actionIds.length; i++) {
                var actionId = actionIds[i]
                item.open("{}")
                var callsBeforeConfirm = calls.length
                var requested = item.requestAction(actionId)
                var pending = item.confirmAction
                var canceled = item.cancelPendingAction()
                var callsAfterCancel = calls.length
                item.open("{}")
                var requestedAgain = item.requestAction(actionId)
                var confirmed = item.activateSelection()
                var callsAfterConfirm = calls.length
                if (confirmed === "ok") {
                    actionExecutions++
                    confirmedActions.push({id: actionId, requested: requestedAgain, result: confirmed})
                }
                confirmationChecks.push({
                    id: actionId,
                    request: requested,
                    pending: pending,
                    callsBeforeConfirm: callsBeforeConfirm,
                    cancel: canceled,
                    callsAfterCancel: callsAfterCancel,
                    requestAgain: requestedAgain,
                    confirm: confirmed,
                    callsAfterConfirm: callsAfterConfirm
                })
            }
            var invalidResult = item.requestAction("not-an-action")
            root.writeResult({
                loaded: true,
                openResult: openResult,
                confirmationResult: confirmationResult,
                pendingAction: pendingAction,
                cancelResult: cancelResult,
                lockResult: lockResult,
                lockPendingAction: lockPendingAction,
                directRunResult: directRunResult,
                directRunPendingAction: directRunPendingAction,
                directRunCalls: directRunCalls,
                invalidResult: invalidResult,
                calls: calls,
                preConfirmationCalls: preConfirmationCalls,
                confirmationChecks: confirmationChecks,
                confirmedActions: confirmedActions,
                actionExecutions: actionExecutions,
                actionRunning: item.actionRunning === true
            })
        }
        onStatusChanged: if (status === Loader.Error) {
            root.panelFailed = true
            root.writeResult({loaded: false})
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

    function writeResult(value) {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        resultFile.setText(JSON.stringify(value) + "\n")
    }

    Timer {
        interval: 1500
        running: true
        repeat: false
        onTriggered: if (!root.finished) root.writeResult({loaded: root.panelLoaded})
    }
}
