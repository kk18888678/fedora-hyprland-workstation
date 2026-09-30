import QtQuick
import Quickshell
import Quickshell.Io

// Isolated fixture for the one non-nagging startup notice. The resolved helper
// path points at a file that does not exist, so the health probe reports it
// missing and the degraded-path prerequisite notice is published exactly once.
// An absent origin MONITOR must not trigger it; this fixture never captures.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_NOTICE_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_NOTICE_SERVICE_SOURCE") || ""
    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property int phase: 0
    property int noticeCountFirst: -1
    property int noticeCountSecond: -1
    property string healthJson: ""
    property string helperPath: ""

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
        id: stepTimer
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
        if (!root.service) return
        root.helperPath = String(root.service.originHelperPath || "")
        root.service.probeHelperAvailability()
        stepTimer.start()
    }

    function busy() {
        return !root.service || root.service.helperProbeProcess.running ||
            root.service.popupFileQueue.length > 0 ||
            root.service.runningPopupFileJob !== null ||
            root.service.popupFileProcess.running ||
            root.service.popupFileRetryTimer.running
    }

    function countNotices() {
        var count = 0
        for (var i = 0; i < root.service.activeModel.count; i++) {
            var row = root.service.activeModel.get(i)
            if (row && String(row.app || "") === "aurelia-notifications") count++
        }
        return count
    }

    function step() {
        if (!root.service || root.finished || root.busy()) return
        if (root.phase === 0) {
            if (!root.service.helperProbeComplete) return
            root.phase = 1
            root.noticeCountFirst = root.countNotices()
            root.service.maybePublishPrerequisiteNotice()
            return
        }
        if (root.phase === 1) {
            root.phase = 2
            root.noticeCountSecond = root.countNotices()
            root.healthJson = root.service.health()
            return
        }
        if (root.phase === 2) root.writeResult()
    }

    function writeResult() {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        stepTimer.stop()
        resultFile.setText(JSON.stringify({
            serviceLoaded: root.serviceLoaded,
            helperPath: root.helperPath,
            helperProbeComplete: root.service.helperProbeComplete,
            noticeCountFirst: root.noticeCountFirst,
            noticeCountSecond: root.noticeCountSecond,
            healthJson: root.healthJson
        }) + "\n")
    }
}
