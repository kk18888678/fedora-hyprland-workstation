import QtQuick
import Quickshell
import Quickshell.Io

// Isolated fixture for the notification Copy action. It drives the production
// Service in testMode (so no live clipboard or bus is touched) and proves the
// Inbox and History copy paths project app/summary/body through the shared
// clipboard mutation owner.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_NOTIFICATION_COPY_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_NOTIFICATION_COPY_SERVICE_SOURCE") || ""
    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property string activeCopy: ""
    property string historyCopy: ""
    property string activeResult: ""
    property string historyResult: ""
    property string missingResult: ""
    property bool activeCopied: false
    property bool historyCopied: false

    QtObject {
        id: notification
        signal closed()
        property bool tracked: false
        property int id: 700
        property string appName: "Signal"
        property string appIcon: ""
        property string desktopEntry: "signal"
        property string summary: "New message"
        property string body: "Hello there"
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
            Qt.callLater(root.performCopy)
        }
        Component.onCompleted: {
            if (root.serviceSource !== "") setSource(root.serviceSource, {testMode: true})
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

    Timer {
        interval: 6000
        running: true
        repeat: false
        onTriggered: if (!root.finished) root.writeResult()
    }

    Timer {
        id: queueTimer
        interval: 60
        repeat: true
        onTriggered: root.copyHistoryIfIdle()
    }

    function performCopy() {
        root.service.handleNotification(notification)
        Qt.callLater(root.copyActive)
    }

    function copyActive() {
        if (root.service.activeModel.count < 1) return Qt.callLater(root.copyActive)
        var row = root.service.activeModel.get(0)
        root.activeResult = root.service.copyNotificationAt(0, row.originalId, row.timestamp)
        root.activeCopy = root.service.lastCopiedText
        root.activeCopied = root.activeCopy === "Signal\nNew message\nHello there"
        // Use the service's history owner so the row survives the asynchronous
        // startup history load instead of being cleared by it.
        root.service.recordHistory({
            id: 701, originalId: 701, timestamp: 5003,
            app: "History App", appIcon: "", desktopEntry: "history-app",
            summary: "Archived", body: "Old body", image: "", glyph: "",
            execArgv: "", actions: [], defaultActionText: "", urgency: 1,
            expireTimeout: 0, transient: false
        }, false)
        queueTimer.start()
    }

    function copyHistoryIfIdle() {
        if (!root.service) return
        if (root.service.popupFileQueue.length > 0 ||
            root.service.runningPopupFileJob !== null ||
            root.service.popupFileProcess.running ||
            root.service.popupFileRetryTimer.running) return
        queueTimer.stop()
        root.copyHistory()
    }

    function copyHistory() {
        root.historyResult = root.service.copyHistoryAt(0)
        root.historyCopy = root.service.lastCopiedText
        root.historyCopied = root.historyCopy === "History App\nArchived\nOld body"
        // A missing identity must fail closed without replacing the clipboard.
        root.missingResult = root.service.copyNotificationAt(0, 123456, 0)
        root.writeResult()
    }

    function writeResult() {
        if (root.finished || !root.service || root.resultPath === "") return
        root.finished = true
        resultFile.setText(JSON.stringify({
            serviceLoaded: root.serviceLoaded,
            activeCopy: root.activeCopy,
            historyCopy: root.historyCopy,
            activeResult: root.activeResult,
            historyResult: root.historyResult,
            missingResult: root.missingResult,
            activeCopied: root.activeCopied,
            historyCopied: root.historyCopied,
            lastCopiedPreserved: root.service.lastCopiedText === root.historyCopy
        }) + "\n")
    }
}
