import QtQuick
import Quickshell
import Quickshell.Io

// Isolated fixture for the notification-origin lifecycle. It drives the real
// Service in testMode against a deterministic helper stub and proves:
//   - capture at arrival folds the returned origin into the live row;
//   - the origin is written into the per-notification popup JSON;
//   - restorePopups rehydrates the origin without gating on its version;
//   - a click navigates with the same origin and a `focused` outcome removes
//     the row, while a `routed` outcome retains it and surfaces the outcome;
//   - a null capture, a timed-out capture, and a corrupt or unknown-version
//     origin all leave the notification displayed with no origin and an
//     honest `unavailable` click result.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_ORIGIN_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_ORIGIN_SERVICE_SOURCE") || ""
    readonly property string navigateSentinel: Quickshell.env("AURELIA_STUB_NAVIGATE_SENTINEL") || ""
    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property int phase: 0
    property string originStem: ""
    property string capturedOrigin: ""
    property string liveOrigin: ""
    property string diskOrigin: ""
    property string restoredOrigin: ""
    property string clickSentinel: ""
    property bool clickRowRemoved: false
    property string routedOrigin: ""
    property string routedOutcome: ""
    property bool routedRowRetained: false
    property bool nullRowRetained: false
    property string nullOrigin: "missing"
    property bool slowRowRetained: false
    property string slowOrigin: "missing"
    property bool corruptRowRetained: false
    property string corruptOutcome: ""
    property bool unknownRowRetained: false
    property string unknownOutcome: ""

    QtObject {
        id: originNotification
        signal closed()
        property bool tracked: false
        property int id: 501
        property string appName: "Chromium"
        property string appIcon: "chromium"
        property string desktopEntry: "chromium"
        property string summary: "Origin round trip"
        property string body: "roundtrip"
        property string image: ""
        property int urgency: 1
        property int expireTimeout: 0
        property var hints: ({})
        property var actions: [{ identifier: "default", text: "Activate" }]
        function dismiss() { closed() }
        function expire() { dismiss() }
    }

    QtObject {
        id: routedNotification
        signal closed()
        property bool tracked: false
        property int id: 503
        property string appName: "Chromium"
        property string appIcon: "chromium"
        property string desktopEntry: "chromium"
        property string summary: "Routed"
        property string body: "routed-capture"
        property string image: ""
        property int urgency: 1
        property int expireTimeout: 0
        property var hints: ({})
        property var actions: [{ identifier: "default", text: "Activate" }]
        function dismiss() { closed() }
        function expire() { dismiss() }
    }

    QtObject {
        id: nullNotification
        signal closed()
        property bool tracked: false
        property int id: 505
        property string appName: "Chromium"
        property string appIcon: "chromium"
        property string desktopEntry: "chromium"
        property string summary: "Null capture"
        property string body: "capture-null"
        property string image: ""
        property int urgency: 1
        property int expireTimeout: 0
        property var hints: ({})
        property var actions: []
        function dismiss() { closed() }
        function expire() { dismiss() }
    }

    QtObject {
        id: slowNotification
        signal closed()
        property bool tracked: false
        property int id: 507
        property string appName: "Chromium"
        property string appIcon: "chromium"
        property string desktopEntry: "chromium"
        property string summary: "Slow capture"
        property string body: "capture-slow"
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
        id: diskReadProcess
        running: false
        stdout: StdioCollector {
            id: diskReadStdout
            waitForEnd: true
        }
        onExited: function(code) {
            if (code === 0) {
                try {
                    var entry = JSON.parse(String(diskReadStdout.text || "").trim())
                    root.diskOrigin = String(entry.origin || "")
                } catch (error) {
                    root.diskOrigin = "parse-error"
                    console.info("[ORIGIN] disk_origin_parse_failed")
                }
            } else {
                root.diskOrigin = "read-error"
            }
        }
    }

    Process {
        id: sentinelReadProcess
        running: false
        stdout: StdioCollector {
            id: sentinelReadStdout
            waitForEnd: true
        }
        onExited: function() {
            root.clickSentinel = String(sentinelReadStdout.text || "")
        }
    }

    Timer {
        id: stepTimer
        interval: 60
        repeat: true
        onTriggered: root.step()
    }

    Timer {
        interval: 12000
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
        root.service.handleNotification(originNotification)
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
            diskReadProcess.running ||
            sentinelReadProcess.running
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
        if (root.phase === 0) { root.phase = 1; root.captureOriginRow(); return }
        if (root.phase === 1) { root.phase = 2; root.readDiskOrigin(); return }
        if (root.phase === 2) { root.phase = 3; root.restoreRoundTrip(); return }
        if (root.phase === 3) { root.phase = 4; root.clickOriginRow(); return }
        if (root.phase === 4) { root.phase = 5; root.readNavigateSentinel(); return }
        if (root.phase === 5) { root.phase = 6; root.handleRouted(); return }
        if (root.phase === 6) { root.phase = 7; root.clickRoutedRow(); return }
        if (root.phase === 7) { root.phase = 8; root.captureRoutedOutcome(); return }
        if (root.phase === 8) { root.phase = 9; root.handleNullCapture(); return }
        if (root.phase === 9) { root.phase = 10; root.captureNullOutcome(); return }
        if (root.phase === 10) { root.phase = 11; root.handleSlowCapture(); return }
        if (root.phase === 11) { root.phase = 12; root.captureSlowOutcome(); return }
        if (root.phase === 12) { root.phase = 13; root.restoreCorruptRows(); return }
        if (root.phase === 13) { root.phase = 14; root.clickCorruptRow(); return }
        if (root.phase === 14) { root.phase = 15; root.clickUnknownRow(); return }
        if (root.phase === 15) root.writeResult()
    }

    function captureOriginRow() {
        var row = root.rowForBody("roundtrip")
        if (!row) { root.writeResult(); return }
        root.capturedOrigin = String(row.origin || "")
        root.originStem = String(row.timestamp) + "-" + String(row.originalId)
        var key = root.service.identityKey(row.originalId, row.timestamp)
        var live = key !== "" ? root.service.liveSnapshots[key] : null
        root.liveOrigin = live ? String(live.origin || "") : ""
    }

    function readDiskOrigin() {
        if (root.originStem === "") return
        diskReadProcess.command = ["/usr/bin/cat", root.service.popupStateDir + root.originStem + ".json"]
        diskReadProcess.running = true
    }

    function restoreRoundTrip() {
        var line = JSON.stringify({
            id: 601, originalId: 601, timestamp: 7600,
            app: "Fixture", appIcon: "", desktopEntry: "fixture",
            summary: "Restored origin", body: "restored-origin",
            image: "", glyph: "", execArgv: "", actions: [],
            defaultActionText: "", urgency: 1, expireTimeout: 0,
            deadline: 0, transient: false,
            origin: root.capturedOrigin
        })
        root.service.restorePopups(line)
    }

    function restoredRow() {
        return root.rowForBody("restored-origin")
    }

    function clickOriginRow() {
        var restored = root.restoredRow()
        if (restored) root.restoredOrigin = String(restored.origin || "")
        var row = root.rowForBody("roundtrip")
        if (!row) { root.writeResult(); return }
        root.service.invokeDefault(root.service.activeIndexForIdentity(row.originalId, row.timestamp),
            row.originalId, row.timestamp)
    }

    function readNavigateSentinel() {
        // The action process has settled, so a `focused` outcome has already
        // removed the row.
        root.clickRowRemoved = root.rowForBody("roundtrip") === null
        if (root.navigateSentinel === "") { root.clickSentinel = ""; return }
        sentinelReadProcess.command = ["/usr/bin/cat", root.navigateSentinel]
        sentinelReadProcess.running = true
    }

    function handleRouted() {
        root.service.handleNotification(routedNotification)
    }

    function clickRoutedRow() {
        var row = root.rowForBody("routed-capture")
        if (!row) { root.writeResult(); return }
        root.routedOrigin = String(row.origin || "")
        root.service.invokeDefault(root.service.activeIndexForIdentity(row.originalId, row.timestamp),
            row.originalId, row.timestamp)
    }

    function captureRoutedOutcome() {
        var row = root.rowForBody("routed-capture")
        root.routedRowRetained = row !== null
        root.routedOutcome = row ? String(row.actionOutcome || "") : ""
    }

    function handleNullCapture() {
        root.service.handleNotification(nullNotification)
    }

    function captureNullOutcome() {
        var row = root.rowForBody("capture-null")
        root.nullRowRetained = row !== null
        root.nullOrigin = row ? String(row.origin || "") : "missing"
    }

    function handleSlowCapture() {
        root.service.handleNotification(slowNotification)
    }

    function captureSlowOutcome() {
        var row = root.rowForBody("capture-slow")
        root.slowRowRetained = row !== null
        root.slowOrigin = row ? String(row.origin || "") : "missing"
    }

    function restoreCorruptRows() {
        var corrupt = JSON.stringify({
            id: 701, originalId: 701, timestamp: 7700,
            app: "Fixture", appIcon: "", desktopEntry: "fixture",
            summary: "Corrupt origin", body: "corrupt-origin",
            image: "", glyph: "", execArgv: "", actions: [],
            defaultActionText: "", urgency: 1, expireTimeout: 0,
            deadline: 0, transient: false,
            origin: "not-valid-json"
        })
        var unknown = JSON.stringify({
            id: 702, originalId: 702, timestamp: 7701,
            app: "Fixture", appIcon: "", desktopEntry: "fixture",
            summary: "Unknown origin", body: "unknown-origin",
            image: "", glyph: "", execArgv: "", actions: [],
            defaultActionText: "", urgency: 1, expireTimeout: 0,
            deadline: 0, transient: false,
            origin: JSON.stringify({ originVersion: 99, captureQuality: "exact" })
        })
        root.service.restorePopups(corrupt + "\n" + unknown)
    }

    function clickCorruptRow() {
        var row = root.rowForBody("corrupt-origin")
        root.corruptRowRetained = row !== null
        if (!row) return
        root.service.invokeDefault(root.service.activeIndexForIdentity(row.originalId, row.timestamp),
            row.originalId, row.timestamp)
        var after = root.rowForBody("corrupt-origin")
        root.corruptOutcome = after ? String(after.actionOutcome || "") : ""
    }

    function clickUnknownRow() {
        var row = root.rowForBody("unknown-origin")
        root.unknownRowRetained = row !== null
        if (!row) return
        root.service.invokeDefault(root.service.activeIndexForIdentity(row.originalId, row.timestamp),
            row.originalId, row.timestamp)
        var after = root.rowForBody("unknown-origin")
        root.unknownOutcome = after ? String(after.actionOutcome || "") : ""
    }

    function writeResult() {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        stepTimer.stop()
        resultFile.setText(JSON.stringify({
            serviceLoaded: root.serviceLoaded,
            capturedOrigin: root.capturedOrigin,
            liveOrigin: root.liveOrigin,
            diskOrigin: root.diskOrigin,
            restoredOrigin: root.restoredOrigin,
            clickSentinel: root.clickSentinel,
            clickRowRemoved: root.clickRowRemoved,
            routedOrigin: root.routedOrigin,
            routedOutcome: root.routedOutcome,
            routedRowRetained: root.routedRowRetained,
            nullRowRetained: root.nullRowRetained,
            nullOrigin: root.nullOrigin,
            slowRowRetained: root.slowRowRetained,
            slowOrigin: root.slowOrigin,
            corruptRowRetained: root.corruptRowRetained,
            corruptOutcome: root.corruptOutcome,
            unknownRowRetained: root.unknownRowRetained,
            unknownOutcome: root.unknownOutcome
        }) + "\n")
    }
}
