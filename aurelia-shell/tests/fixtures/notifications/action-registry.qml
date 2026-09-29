import QtQuick
import Quickshell
import Quickshell.Io

// Isolated fixture for the per-application cooperation registry. It drives the
// real Service in testMode with durable rows that have no live sender object
// (exactly the retained-Inbox case) and proves:
//   - a Herdr default Open resolves through the registry from the CAPTURED
//     origin, which is more precise than the body workspace number;
//   - a Herdr default Open without a captured origin falls back to the body
//     number and still navigates through the single origin owner;
//   - a registry argv entry genuinely runs (a sentinel file is the side
//     effect), so a broken invocation cannot silently pass;
//   - an unregistered (app, action) pair fails closed to `unavailable` and the
//     row is retained instead of inventing a command.
//
// The fixture never reaches the live compositor, helper, or notification bus:
// the navigation helper is a deterministic stub and the extra registry entry
// only touches a temp sentinel.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_REGISTRY_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_REGISTRY_SERVICE_SOURCE") || ""
    readonly property string navigateSentinel: Quickshell.env("AURELIA_STUB_NAVIGATE_SENTINEL") || ""
    readonly property string argvSentinel: Quickshell.env("AURELIA_REGISTRY_ARGV_SENTINEL") || ""
    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property int phase: 0
    property bool restoredRowsReady: false
    property string capturedInvokeResult: ""
    property bool capturedRowRemoved: false
    property string fallbackInvokeResult: ""
    property bool fallbackRowRemoved: false
    property string argvInvokeResult: ""
    property bool argvRowRemoved: false
    property bool argvSentinelExists: false
    property string unknownInvokeResult: ""
    property bool unknownRowRetained: false
    property string unknownOutcome: ""
    property string navigateOutput: ""

    function capturedOriginJson() {
        return JSON.stringify({
            originVersion: 1,
            captureQuality: "exact",
            captureSource: "bus-monitor",
            notify: { appName: "Herdr", desktopEntry: "Herdr" },
            sender: {
                pid: 4242, ancestry: [],
                focusEnv: { HERDR_WORKSPACE_ID: "w1P", HERDR_TAB_ID: "w1T", HERDR_PANE_ID: "w1P:p2" }
            },
            compositor: { matched: true, matchConfidence: "pid", workspaceId: 2 },
            tab: { kind: "herdr", workspaceId: "w1P", tabId: "w1T", paneId: "w1P:p2" }
        })
    }

    function restoredLine(id, timestamp, app, desktopEntry, body, actions, defaultActionText, origin) {
        return JSON.stringify({
            id: id, originalId: id, timestamp: timestamp,
            app: app, appIcon: "application-x-executable", desktopEntry: desktopEntry,
            summary: body, body: body,
            image: "", glyph: "", execArgv: "", actions: actions || [],
            defaultActionText: defaultActionText || "", urgency: 1, expireTimeout: 0,
            deadline: 0, transient: false, origin: origin || ""
        })
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
        onExited: function(code) { root.argvSentinelExists = code === 0 }
    }

    Process {
        id: navigateReadProcess
        running: false
        stdout: StdioCollector {
            id: navigateReadStdout
            waitForEnd: true
        }
        onExited: function() { root.navigateOutput = String(navigateReadStdout.text || "") }
    }

    Timer {
        id: stepTimer
        interval: 60
        repeat: true
        onTriggered: root.step()
    }

    Timer {
        interval: 10000
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
            sentinelProbeProcess.running ||
            navigateReadProcess.running
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
        if (root.phase === 0) { root.phase = 1; root.restoreRows(); return }
        if (root.phase === 1) {
            if (!root.rowForBody("sutradhar \u00b7 2 \u00b7 3")) return
            root.phase = 2
            root.invokeCaptured()
            return
        }
        if (root.phase === 2) { root.phase = 3; root.invokeFallback(); return }
        if (root.phase === 3) { root.phase = 4; root.invokeRegistryArgv(); return }
        if (root.phase === 4) { root.phase = 5; root.invokeUnknown(); return }
        if (root.phase === 5) { root.captureOutcomes(); root.phase = 6; return }
        if (root.phase === 6) { root.probeArgvSentinel(); root.phase = 7; return }
        if (root.phase === 7) { root.phase = 8; root.readNavigateSentinel(); return }
        if (root.phase === 8) root.writeResult()
    }

    function restoreRows() {
        var lines = [
            root.restoredLine(911, 8100, "Herdr", "", "sutradhar \u00b7 2 \u00b7 3", [], "Open", root.capturedOriginJson()),
            root.restoredLine(912, 8101, "Herdr", "", "sutradhar \u00b7 7 \u00b7 1", [], "Open", ""),
            root.restoredLine(913, 8102, "Fixture Registry", "fixture-registry", "registry-argv",
                [{ identifier: "settings", text: "Settings" }], "", ""),
            root.restoredLine(914, 8103, "Unregistered", "com.example.Unregistered", "registry-unknown",
                [{ identifier: "settings", text: "Settings" }], "", "")
        ]
        root.service.restorePopups(lines.join("\n"))
    }

    function invokeAt(body, identifier, isDefault) {
        var row = root.rowForBody(body)
        if (!row) return ""
        var index = root.service.activeIndexForIdentity(row.originalId, row.timestamp)
        if (isDefault) return String(root.service.invokeDefault(index, row.originalId, row.timestamp))
        return String(root.service.invokeAction(index, identifier, row.originalId, row.timestamp))
    }

    function invokeCaptured() {
        // A durable default Open with a captured origin. The registry resolves
        // the origin; the row is removed only when the helper reports it
        // focused the target.
        root.capturedInvokeResult = root.invokeAt("sutradhar \u00b7 2 \u00b7 3", "default", true)
    }

    function invokeFallback() {
        root.fallbackInvokeResult = root.invokeAt("sutradhar \u00b7 7 \u00b7 1", "default", true)
        root.fallbackRowRemoved = root.rowForBody("sutradhar \u00b7 7 \u00b7 1") === null
    }

    function invokeRegistryArgv() {
        root.argvInvokeResult = root.invokeAt("registry-argv", "settings", false)
    }

    function invokeUnknown() {
        root.unknownInvokeResult = root.invokeAt("registry-unknown", "settings", false)
    }

    function captureOutcomes() {
        root.capturedRowRemoved = root.rowForBody("sutradhar \u00b7 2 \u00b7 3") === null
        root.fallbackRowRemoved = root.rowForBody("sutradhar \u00b7 7 \u00b7 1") === null
        root.argvRowRemoved = root.rowForBody("registry-argv") === null
        var unknownRow = root.rowForBody("registry-unknown")
        root.unknownRowRetained = unknownRow !== null
        root.unknownOutcome = unknownRow ? String(unknownRow.actionOutcome || "") : ""
    }

    function probeArgvSentinel() {
        if (root.argvSentinel === "") { root.argvSentinelExists = false; return }
        sentinelProbeProcess.command = ["/usr/bin/test", "-f", root.argvSentinel]
        sentinelProbeProcess.running = true
    }

    function readNavigateSentinel() {
        if (root.navigateSentinel === "") { root.navigateOutput = ""; return }
        navigateReadProcess.command = ["/usr/bin/cat", root.navigateSentinel]
        navigateReadProcess.running = true
    }

    function writeResult() {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        stepTimer.stop()
        resultFile.setText(JSON.stringify({
            serviceLoaded: root.serviceLoaded,
            capturedInvokeResult: root.capturedInvokeResult,
            capturedRowRemoved: root.capturedRowRemoved,
            fallbackInvokeResult: root.fallbackInvokeResult,
            fallbackRowRemoved: root.fallbackRowRemoved,
            argvInvokeResult: root.argvInvokeResult,
            argvRowRemoved: root.argvRowRemoved,
            argvSentinelExists: root.argvSentinelExists,
            unknownInvokeResult: root.unknownInvokeResult,
            unknownRowRetained: root.unknownRowRetained,
            unknownOutcome: root.unknownOutcome,
            navigateSentinel: root.navigateOutput
        }) + "\n")
    }
}
