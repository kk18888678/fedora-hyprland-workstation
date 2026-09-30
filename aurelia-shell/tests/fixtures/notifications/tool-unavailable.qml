import QtQuick
import Quickshell
import Quickshell.Io

// Isolated fixture for the deterministic external-tool resolver's observable
// consequences. It drives the real Service in testMode with a deterministic
// helper stub and proves:
//   - the helper invocation receives the deterministic PATH, which contains
//     ~/.local/bin, rather than the compositor-inherited PATH;
//   - a NAMED tool-unavailable reason from the helper reaches the Inbox row;
//   - the health payload carries the per-tool `tools` map, resolved through
//     the same single resolver (including a fail-closed missing override).
//
// The stub helper never reaches the live compositor, helper, or notification
// bus, and the stub navigate reports `unavailable`, so the row policy is
// asserted without any focus mutation.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_TOOL_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_TOOL_SERVICE_SOURCE") || ""
    readonly property string pathSentinel: Quickshell.env("AURELIA_STUB_PATH_SENTINEL") || ""
    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property int phase: 0
    property bool rowRetained: false
    property string reason: ""
    property string helperPathEnv: ""
    property string healthJson: ""

    QtObject {
        id: herdrNotification
        signal closed()
        property bool tracked: false
        property int id: 1001
        property string appName: "Herdr"
        property string appIcon: "herdr"
        property string desktopEntry: "Herdr"
        property string summary: "tool unavailable"
        property string body: "sutradhar · 7 · capture-identity"
        property string image: ""
        property int urgency: 1
        property int expireTimeout: 0
        property var hints: ({})
        property var actions: []
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
        id: pathReadProcess
        running: false
        stdout: StdioCollector { id: pathReadStdout; waitForEnd: true }
        onExited: function() { root.helperPathEnv = String(pathReadStdout.text || "") }
    }

    Timer {
        id: stepTimer
        interval: 60
        repeat: true
        onTriggered: root.step()
    }

    Timer {
        interval: 14000
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
        if (!root.service) return
        root.service.probeHelperAvailability()
        root.service.handleNotification(herdrNotification)
        stepTimer.start()
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
            root.service.helperProbeProcess.running ||
            !root.service.toolsProbeComplete ||
            pathReadProcess.running
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
        if (root.phase === 0) {
            if (!root.service.helperProbeComplete) return
            root.phase = 1
            root.clickRow()
            return
        }
        if (root.phase === 1) {
            root.phase = 2
            var row = root.rowForBody("sutradhar · 7 · capture-identity")
            root.rowRetained = row !== null
            root.reason = row ? String(row.actionOutcomeReason || "") : ""
            root.healthJson = root.service.health()
            if (root.pathSentinel !== "") {
                pathReadProcess.command = ["/usr/bin/cat", root.pathSentinel]
                pathReadProcess.running = true
            }
            return
        }
        if (root.phase === 2) root.writeResult()
    }

    function clickRow() {
        var row = root.rowForBody("sutradhar · 7 · capture-identity")
        if (!row) { root.writeResult(); return }
        root.service.invokeDefault(root.service.activeIndexForIdentity(row.originalId, row.timestamp),
            row.originalId, row.timestamp)
    }

    function writeResult() {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        stepTimer.stop()
        resultFile.setText(JSON.stringify({
            serviceLoaded: root.serviceLoaded,
            rowRetained: root.rowRetained,
            reason: root.reason,
            helperPathEnv: root.helperPathEnv,
            healthJson: root.healthJson
        }) + "\n")
    }
}
