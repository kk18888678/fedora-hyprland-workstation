import QtQuick
import Quickshell
import Quickshell.Io

// Isolated fixture for the notification Copy action. It drives the production
// Service in testMode (so no live clipboard or bus is touched) and proves the
// transient toast and Inbox copy paths project app/summary/body through the
// shared clipboard mutation owner.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_NOTIFICATION_COPY_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_NOTIFICATION_COPY_SERVICE_SOURCE") || ""
    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property string activeCopy: ""
    property string popupCopy: ""
    property string activeResult: ""
    property string popupResult: ""
    property string missingResult: ""
    property bool activeCopied: false
    property bool popupCopied: false

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
        // The transient toast (popup) surface shares the same clipboard owner
        // and must also copy the complete notification content.
        if (root.service.popupModel.count < 1) return Qt.callLater(root.copyActive)
        var popupRow = root.service.popupModel.get(0)
        root.popupResult = root.service.copyNotificationAt(0, popupRow.originalId, popupRow.timestamp)
        root.popupCopy = root.service.lastCopiedText
        root.popupCopied = root.popupCopy === "Signal\nNew message\nHello there"
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
            popupCopy: root.popupCopy,
            activeResult: root.activeResult,
            popupResult: root.popupResult,
            missingResult: root.missingResult,
            activeCopied: root.activeCopied,
            popupCopied: root.popupCopied,
            lastCopiedPreserved: root.service.lastCopiedText === root.popupCopy
        }) + "\n")
    }
}
