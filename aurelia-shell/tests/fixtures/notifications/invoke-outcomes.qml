import QtQuick
import Quickshell
import Quickshell.Io

// Isolated fixture for the honest action-result contract. It drives the real
// Service in testMode and proves:
//   - a live action.invoke() that actually ran                -> "delivered"
//   - an execArgv command that genuinely ran (sentinel file)  -> row removed
//   - a missing execArgv command                              -> "unavailable"
//                                                                and the row is
//                                                                retained with
//                                                                the outcome
//                                                                surfaced
//   - an index/identity miss                                  -> "none"
// The execArgv case asserts a real side effect (a sentinel file), so the old
// `shift` + `exec "$@"` guard bug fails this test instead of silently passing.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_NOTIFICATION_INVOKE_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_NOTIFICATION_INVOKE_SERVICE_SOURCE") || ""
    readonly property string sentinelPath: Quickshell.env("AURELIA_NOTIFICATION_INVOKE_SENTINEL") || ""
    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property int phase: 0
    property bool liveActionInvoked: false
    property string liveDeliveredResult: ""
    property bool liveRowRemoved: false
    property string executedSyncResult: ""
    property bool execRowRemoved: false
    property bool sentinelExists: false
    property string missingSyncResult: ""
    property string missingOutcome: ""
    property bool missingRowRetained: false
    property string noneIndexResult: ""
    property string noneIdentityResult: ""

    QtObject {
        id: liveDelivery
        signal closed()
        property bool tracked: false
        property int id: 71
        property string appName: "Signal"
        property string appIcon: "signal"
        property string desktopEntry: "signal"
        property string summary: "Signal"
        property string body: "New message"
        property string image: ""
        property int urgency: 1
        property int expireTimeout: 0
        property var hints: ({})
        property var actions: [
            { identifier: "default", text: "Open" },
            { identifier: "settings", text: "Settings",
              invoke: function() { root.liveActionInvoked = true } }
        ]
        function dismiss() { closed() }
        function expire() { dismiss() }
    }

    QtObject {
        id: execSentinel
        signal closed()
        property bool tracked: false
        property int id: 72
        property string appName: "Signal"
        property string appIcon: "signal"
        property string desktopEntry: "signal"
        property string summary: "Signal"
        property string body: "Exec sentinel"
        property string image: ""
        property int urgency: 1
        property int expireTimeout: 0
        property var hints: ({
            "aurelia-exec-argv": JSON.stringify(["/usr/bin/touch", root.sentinelPath])
        })
        property var actions: [
            { identifier: "settings", text: "Settings" }
        ]
        function dismiss() { closed() }
        function expire() { dismiss() }
    }

    QtObject {
        id: missingCommand
        signal closed()
        property bool tracked: false
        property int id: 73
        property string appName: "Signal"
        property string appIcon: "signal"
        property string desktopEntry: "signal"
        property string summary: "Signal"
        property string body: "Missing command"
        property string image: ""
        property int urgency: 1
        property int expireTimeout: 0
        property var hints: ({
            "aurelia-exec-argv": JSON.stringify(["/nonexistent/aurelia-missing-command-xyz"])
        })
        property var actions: [
            { identifier: "settings", text: "Settings" }
        ]
        function dismiss() { closed() }
        function expire() { dismiss() }
    }

    Loader {
        id: serviceLoader
        onLoaded: {
            if (!item) return
            root.service = item
            root.serviceLoaded = true
            Qt.callLater(root.start)
        }
        Component.onCompleted: {
            if (root.serviceSource !== "") setSource(root.serviceSource, {testMode: true})
        }
    }

    Process {
        id: sentinelProbeProcess
        running: false
        onExited: function(code) {
            root.sentinelExists = code === 0
        }
    }

    Timer {
        id: queueTimer
        interval: 60
        repeat: true
        onTriggered: root.step()
    }

    Timer {
        interval: 8000
        running: true
        repeat: false
        onTriggered: if (!root.finished) root.writeResult()
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

    function start() {
        root.service.handleNotification(liveDelivery)
        queueTimer.start()
    }

    function busy() {
        return !root.service ||
            root.service.popupFileQueue.length > 0 ||
            root.service.runningPopupFileJob !== null ||
            root.service.popupFileProcess.running ||
            root.service.popupFileRetryTimer.running ||
            root.service.captureQueue.length > 0 ||
            root.service.runningCaptureJob !== null ||
            root.service.captureProcess.running ||
            root.service.actionQueue.length > 0 ||
            root.service.runningActionJob !== null ||
            root.service.actionProcess.running ||
            sentinelProbeProcess.running
    }

    function rowForBody(body) {
        for (var i = 0; i < root.service.activeModel.count; i++) {
            var candidate = root.service.activeModel.get(i)
            if (candidate && String(candidate.body) === body) return candidate
        }
        return null
    }

    function step() {
        if (!root.service || root.finished || root.busy()) return
        if (root.phase === 0) { root.phase = 1; root.runLive(); return }
        if (root.phase === 1) { root.phase = 2; root.runExecSentinel(); return }
        if (root.phase === 2) { root.phase = 3; root.probeSentinel(); return }
        if (root.phase === 3) { root.phase = 4; root.captureExecRemoved(); return }
        if (root.phase === 4) { root.phase = 5; root.runMissing(); return }
        if (root.phase === 5) { root.phase = 6; root.captureMissingOutcome(); return }
        if (root.phase === 6) { root.phase = 7; root.runNones(); return }
        if (root.phase === 7) root.writeResult()
    }

    function runLive() {
        var row = root.service.activeModel.count > 0 ? root.service.activeModel.get(0) : null
        if (!row) { root.writeResult(); return }
        root.liveDeliveredResult = String(
            root.service.invokeAction(0, "settings", row.originalId, row.timestamp))
        root.liveRowRemoved = root.service.activeModel.count === 0
        root.service.handleNotification(execSentinel)
    }

    function runExecSentinel() {
        var row = root.rowForBody("Exec sentinel")
        if (!row) { root.writeResult(); return }
        root.executedSyncResult = String(
            root.service.invokeAction(0, "settings", row.originalId, row.timestamp))
    }

    function probeSentinel() {
        if (root.sentinelPath === "") { root.sentinelExists = false; return }
        sentinelProbeProcess.command = ["/usr/bin/test", "-f", root.sentinelPath]
        sentinelProbeProcess.running = true
    }

    function captureExecRemoved() {
        root.execRowRemoved = root.rowForBody("Exec sentinel") === null
        root.service.handleNotification(missingCommand)
    }

    function runMissing() {
        var row = root.rowForBody("Missing command")
        if (!row) { root.writeResult(); return }
        root.missingSyncResult = String(
            root.service.invokeAction(0, "settings", row.originalId, row.timestamp))
    }

    function captureMissingOutcome() {
        var row = root.rowForBody("Missing command")
        root.missingRowRetained = row !== null
        root.missingOutcome = row ? String(row.actionOutcome || "") : ""
    }

    function runNones() {
        root.noneIndexResult = String(root.service.invokeAction(999, "settings"))
        root.noneIdentityResult = String(root.service.invokeAction(0, "settings", 12345, 67890))
    }

    function writeResult() {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        queueTimer.stop()
        resultFile.setText(JSON.stringify({
            serviceLoaded: root.serviceLoaded,
            liveActionInvoked: root.liveActionInvoked,
            liveDeliveredResult: root.liveDeliveredResult,
            liveRowRemoved: root.liveRowRemoved,
            executedSyncResult: root.executedSyncResult,
            execRowRemoved: root.execRowRemoved,
            sentinelExists: root.sentinelExists,
            missingSyncResult: root.missingSyncResult,
            missingOutcome: root.missingOutcome,
            missingRowRetained: root.missingRowRetained,
            noneIndexResult: root.noneIndexResult,
            noneIdentityResult: root.noneIdentityResult
        }) + "\n")
    }
}
