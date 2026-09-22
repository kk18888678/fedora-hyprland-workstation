import QtQuick
import Quickshell
import Quickshell.Io

// Isolated fixture for the shell-reload restore path. It drives the production
// Service in testMode and proves that restoring persisted Inbox rows does not
// replay them as transient popups, while a genuinely new notification still
// toasts. It never owns a live notification bus or desktop surface.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_NOTIFICATION_RESTORE_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_NOTIFICATION_RESTORE_SERVICE_SOURCE") || ""
    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property int restoredActive: -1
    property int restoredPopup: -1
    property int afterNewActive: -1
    property int afterNewPopup: -1
    property bool restoredMarked: false
    property var restoredSummaries: []

    QtObject {
        id: freshNotification
        signal closed()
        property bool tracked: false
        property int id: 900
        property string appName: "Fresh Fixture"
        property string appIcon: ""
        property string desktopEntry: "fresh-fixture"
        property string summary: "Fresh notification"
        property string body: "fresh body"
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
            Qt.callLater(root.performRestore)
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
        onTriggered: root.afterFreshIfIdle()
    }

    function rawPopup() {
        var entries = [
            {
                id: 11, originalId: 11, timestamp: 5001,
                app: "Restored One", appIcon: "", desktopEntry: "restored-one",
                summary: "Restored One", body: "restored one body",
                image: "", glyph: "", execArgv: "", actions: [],
                defaultActionText: "", urgency: 1, expireTimeout: 0,
                deadline: 0, transient: false
            },
            {
                id: 12, originalId: 12, timestamp: 5002,
                app: "Restored Two", appIcon: "", desktopEntry: "restored-two",
                summary: "Restored Two", body: "restored two body",
                image: "", glyph: "", execArgv: "", actions: [],
                defaultActionText: "", urgency: 1, expireTimeout: 0,
                deadline: 0, transient: false
            }
        ]
        var lines = []
        for (var i = 0; i < entries.length; i++) lines.push(JSON.stringify(entries[i]))
        return lines.join("\n")
    }

    function performRestore() {
        // Exercise the production restore parser directly; the file-directory
        // read is covered by the service's own state machinery.
        root.service.restorePopups(root.rawPopup())
        Qt.callLater(root.afterRestore)
    }

    function afterRestore() {
        root.restoredActive = root.service.activeModel.count
        root.restoredPopup = root.service.popupModel.count
        root.restoredMarked = !!root.service.restoredPopups["5001-11.json"] &&
            !!root.service.restoredPopups["5002-12.json"]
        for (var i = 0; i < root.service.activeModel.count; i++)
            root.restoredSummaries.push(String(root.service.activeModel.get(i).summary || ""))
        root.service.handleNotification(freshNotification)
        queueTimer.start()
    }

    function afterFreshIfIdle() {
        if (!root.service) return
        if (root.service.popupFileQueue.length > 0 ||
            root.service.runningPopupFileJob !== null ||
            root.service.popupFileProcess.running ||
            root.service.popupFileRetryTimer.running) return
        queueTimer.stop()
        root.afterNewActive = root.service.activeModel.count
        root.afterNewPopup = root.service.popupModel.count
        root.writeResult()
    }

    function writeResult() {
        if (root.finished || !root.service || root.resultPath === "") return
        root.finished = true
        resultFile.setText(JSON.stringify({
            serviceLoaded: root.serviceLoaded,
            restoredActive: root.restoredActive,
            restoredPopup: root.restoredPopup,
            restoredMarked: root.restoredMarked,
            restoredSummaries: root.restoredSummaries,
            afterNewActive: root.afterNewActive,
            afterNewPopup: root.afterNewPopup
        }) + "\n")
    }
}
