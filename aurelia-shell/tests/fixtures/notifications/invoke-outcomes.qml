import QtQuick
import Quickshell
import Quickshell.Io

// Isolated fixture for the honest action-result contract. It drives the real
// Service in testMode and proves the distinction between:
//   - a live action.invoke() that actually ran             -> "delivered"
//   - a notification-level execArgv fallback that spawned -> "executed"
//   - an index/identity miss                               -> "none"
// The Chromium retained-row "routed" case lives in invoke-action.qml.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_NOTIFICATION_INVOKE_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_NOTIFICATION_INVOKE_SERVICE_SOURCE") || ""
    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property int phase: 0
    property bool liveActionInvoked: false
    property string liveDeliveredResult: ""
    property bool liveRowRemoved: false
    property string executedResult: ""
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
        id: execFallback
        signal closed()
        property bool tracked: false
        property int id: 72
        property string appName: "Signal"
        property string appIcon: "signal"
        property string desktopEntry: "signal"
        property string summary: "Signal"
        property string body: "Exec fallback"
        property string image: ""
        property int urgency: 1
        property int expireTimeout: 0
        property var hints: ({ "aurelia-exec-argv": "[\"/bin/true\"]" })
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

    Timer {
        id: queueTimer
        interval: 60
        repeat: true
        onTriggered: root.step()
    }

    Timer {
        interval: 6000
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

    function queueIdle() {
        return root.service &&
            root.service.popupFileQueue.length === 0 &&
            root.service.runningPopupFileJob === null &&
            !root.service.popupFileProcess.running &&
            !root.service.popupFileRetryTimer.running
    }

    function step() {
        if (!root.service || root.finished || !queueIdle()) return
        if (root.phase === 0) {
            root.phase = 1
            root.runLive()
            return
        }
        if (root.phase === 1) {
            root.phase = 2
            root.runExecuted()
        }
    }

    function runLive() {
        var row = root.service.activeModel.count > 0 ? root.service.activeModel.get(0) : null
        if (!row) { root.writeResult(); return }
        root.liveDeliveredResult = String(
            root.service.invokeAction(0, "settings", row.originalId, row.timestamp))
        root.liveRowRemoved = root.service.activeModel.count === 0
        root.service.handleNotification(execFallback)
    }

    function runExecuted() {
        var row = null
        for (var i = 0; i < root.service.activeModel.count; i++) {
            var candidate = root.service.activeModel.get(i)
            if (candidate && String(candidate.body) === "Exec fallback") {
                row = candidate
                break
            }
        }
        if (!row) { root.writeResult(); return }
        root.executedResult = String(
            root.service.invokeAction(0, "settings", row.originalId, row.timestamp))
        root.noneIndexResult = String(root.service.invokeAction(999, "settings"))
        root.noneIdentityResult = String(root.service.invokeAction(0, "settings", 12345, 67890))
        root.writeResult()
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
            executedResult: root.executedResult,
            noneIndexResult: root.noneIndexResult,
            noneIdentityResult: root.noneIdentityResult
        }) + "\n")
    }
}
