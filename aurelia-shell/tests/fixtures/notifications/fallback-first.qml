import QtQuick
import Quickshell
import Quickshell.Io

// Isolated fixture for the FALLBACK-FIRST origin resolution and the honest,
// durable action outcome. It drives the real Service in testMode with a
// deterministic helper stub and proves:
//   - a captured origin that is NOT actionable (monitor absent) falls through
//     to the Herdr body workspace number and yields the workspace identity;
//   - a body-only Herdr notification with no monitor still resolves to that
//     identity and the row is removed only on a delivered outcome;
//   - an app-identity-only retained row resolves through the stable desktop
//     entry to an app/class identity origin;
//   - the helper's bounded reason reaches the model AND the persisted popup
//     JSON, and survives a restore;
//   - the health payload is computed in one place and reports the marker.
//
// The stub helper never reaches the live compositor, helper, or notification
// bus. The stub navigate always reports `unavailable`, so the row policy can
// be asserted without any focus mutation.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_FALLBACK_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_FALLBACK_SERVICE_SOURCE") || ""
    readonly property string navigateSentinel: Quickshell.env("AURELIA_STUB_NAVIGATE_SENTINEL") || ""
    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property int phase: 0
    property string capturedOrigin: ""
    property bool capturedActionable: true
    property bool herdrRowRetained: false
    property string herdrOutcome: ""
    property string herdrReason: ""
    property string diskOutcome: ""
    property string diskReason: ""
    property string restoredOutcome: ""
    property string restoredReason: ""
    property bool appRowRetained: false
    property string appOriginSentinel: ""
    property string healthJson: ""
    property bool noticePublishedOnce: false

    QtObject {
        id: herdrNotification
        signal closed()
        property bool tracked: false
        property int id: 901
        property string appName: "Herdr"
        property string appIcon: "herdr"
        property string desktopEntry: "Herdr"
        property string summary: "pi finished"
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
        id: diskReadProcess
        running: false
        stdout: StdioCollector {
            id: diskReadStdout
            waitForEnd: true
        }
        onExited: function(code) {
            if (code !== 0) { root.diskOutcome = "read-error"; return }
            try {
                var entry = JSON.parse(String(diskReadStdout.text || "").trim())
                root.diskOutcome = String(entry.actionOutcome || "")
                root.diskReason = String(entry.actionOutcomeReason || "")
            } catch (error) {
                root.diskOutcome = "parse-error"
                console.info("[FALLBACK] disk_outcome_parse_failed")
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
            root.appOriginSentinel = String(sentinelReadStdout.text || "")
        }
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
        if (root.phase === 0) {
            if (!root.service.helperProbeComplete) return
            root.phase = 1
            root.captureHerdrRow()
            return
        }
        if (root.phase === 1) { root.phase = 2; root.clickHerdrRow(); return }
        if (root.phase === 2) { root.phase = 3; root.readDiskOutcome(); return }
        if (root.phase === 3) { root.phase = 4; root.restoreOutcome(); return }
        if (root.phase === 4) { root.phase = 5; root.restoreAppIdentityRow(); return }
        if (root.phase === 5) { root.phase = 6; root.clickAppIdentityRow(); return }
        if (root.phase === 6) { root.phase = 7; root.readSentinel(); return }
        if (root.phase === 7) { root.phase = 8; root.captureHealth(); return }
        if (root.phase === 8) { root.phase = 9; root.probeNoticeIdempotence(); return }
        if (root.phase === 9) root.writeResult()
    }

    function captureHerdrRow() {
        var row = root.rowForBody("sutradhar · 7 · capture-identity")
        if (!row) { root.writeResult(); return }
        root.capturedOrigin = String(row.origin || "")
        var parsed = null
        try { parsed = JSON.parse(root.capturedOrigin) } catch (error) {
            console.info("[FALLBACK] captured_origin_unparseable")
            parsed = null
        }
        root.capturedActionable = false
        if (parsed) {
            root.capturedActionable = String(parsed.captureQuality || "") === "exact" ||
                (parsed.compositor && parsed.compositor.matched === true)
        }
    }

    function clickHerdrRow() {
        var row = root.rowForBody("sutradhar · 7 · capture-identity")
        if (!row) { root.writeResult(); return }
        root.service.invokeDefault(root.service.activeIndexForIdentity(row.originalId, row.timestamp),
            row.originalId, row.timestamp)
    }

    function readDiskOutcome() {
        var row = root.rowForBody("sutradhar · 7 · capture-identity")
        root.herdrRowRetained = row !== null
        root.herdrOutcome = row ? String(row.actionOutcome || "") : ""
        root.herdrReason = row ? String(row.actionOutcomeReason || "") : ""
        if (!row) { root.writeResult(); return }
        var stem = String(row.timestamp) + "-" + String(row.originalId)
        diskReadProcess.command = ["/usr/bin/cat", root.service.popupStateDir + stem + ".json"]
        diskReadProcess.running = true
    }

    function restoreOutcome() {
        var line = JSON.stringify({
            id: 902, originalId: 902, timestamp: 9100,
            app: "Herdr", appIcon: "", desktopEntry: "Herdr",
            summary: "Restored outcome", body: "restored-outcome",
            image: "", glyph: "", execArgv: "", actions: [],
            defaultActionText: "Open", urgency: 1, expireTimeout: 0,
            deadline: 0, transient: false, origin: "",
            actionOutcome: "unavailable", actionOutcomeReason: "no origin monitor"
        })
        root.service.restorePopups(line)
    }

    function restoreAppIdentityRow() {
        var row = root.rowForBody("restored-outcome")
        if (row) {
            root.restoredOutcome = String(row.actionOutcome || "")
            root.restoredReason = String(row.actionOutcomeReason || "")
        }
        var line = JSON.stringify({
            id: 903, originalId: 903, timestamp: 9200,
            app: "Fixture App", appIcon: "", desktopEntry: "fixture-app",
            summary: "App identity", body: "app-identity-only",
            image: "", glyph: "", execArgv: "", actions: [],
            defaultActionText: "Open", urgency: 1, expireTimeout: 0,
            deadline: 0, transient: false, origin: ""
        })
        root.service.restorePopups(line)
    }

    function clickAppIdentityRow() {
        var row = root.rowForBody("app-identity-only")
        if (!row) { root.writeResult(); return }
        root.service.invokeDefault(root.service.activeIndexForIdentity(row.originalId, row.timestamp),
            row.originalId, row.timestamp)
    }

    function readSentinel() {
        var row = root.rowForBody("app-identity-only")
        root.appRowRetained = row !== null
        if (root.navigateSentinel === "") { root.appOriginSentinel = ""; return }
        sentinelReadProcess.command = ["/usr/bin/cat", root.navigateSentinel]
        sentinelReadProcess.running = true
    }

    function captureHealth() {
        root.healthJson = root.service.health()
    }

    function probeNoticeIdempotence() {
        // The notice is published at most once even if the probe is retried.
        root.service.prerequisiteNoticePublished = false
        root.service.helperAvailable = false
        root.service.helperProbeComplete = true
        var first = root.service.maybePublishPrerequisiteNotice()
        var second = root.service.maybePublishPrerequisiteNotice()
        var count = 0
        for (var i = 0; i < root.service.activeModel.count; i++) {
            var row = root.service.activeModel.get(i)
            if (row && String(row.app || "") === "aurelia-notifications") count++
        }
        root.noticePublishedOnce = first === "ok" && second === "none" && count === 1
    }

    function writeResult() {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        stepTimer.stop()
        resultFile.setText(JSON.stringify({
            serviceLoaded: root.serviceLoaded,
            capturedOrigin: root.capturedOrigin,
            capturedActionable: root.capturedActionable,
            herdrRowRetained: root.herdrRowRetained,
            herdrOutcome: root.herdrOutcome,
            herdrReason: root.herdrReason,
            diskOutcome: root.diskOutcome,
            diskReason: root.diskReason,
            restoredOutcome: root.restoredOutcome,
            restoredReason: root.restoredReason,
            appRowRetained: root.appRowRetained,
            appOriginSentinel: root.appOriginSentinel,
            healthJson: root.healthJson,
            noticePublishedOnce: root.noticePublishedOnce
        }) + "\n")
    }
}
