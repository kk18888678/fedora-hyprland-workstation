import QtQuick
import Quickshell
import Quickshell.Io

// T51 fixture. It keeps two restored rows and two successive live rows with
// the same numeric notification ID, then dismisses the restored rows through
// the production popup Toast path. This is the collision that distinct-ID
// fixtures cannot represent.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_NOTIFICATION_COLLISION_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_NOTIFICATION_COLLISION_SERVICE_SOURCE") || ""
    readonly property string toastSource: Quickshell.env("AURELIA_NOTIFICATION_COLLISION_TOAST_SOURCE") || ""
    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property int phase: 0
    property bool popupMalformedCovered: false
    property bool replacementPreservedRestored: false
    property bool secondPopupMalformedCovered: false
    property bool stateCountRequested: false
    property int popupFiles: -1
    property int historyFiles: -1

    QtObject {
        id: liveFirst
        signal closed()
        property bool tracked: false
        property int id: 1
        property string appName: "Collision Live One"
        property string appIcon: ""
        property string desktopEntry: "collision-live"
        property string summary: "live-one"
        property string body: "live one body"
        property int urgency: 1
        property int expireTimeout: 0
        property var hints: ({transient: true})
        property var actions: []
        property int dismissCalls: 0
        function dismiss() { dismissCalls++; closed() }
        function expire() { dismiss() }
    }

    QtObject {
        id: liveSecond
        signal closed()
        property bool tracked: false
        property int id: 1
        property string appName: "Collision Live Two"
        property string appIcon: ""
        property string desktopEntry: "collision-live"
        property string summary: "live-two"
        property string body: "live two body"
        property int urgency: 1
        property int expireTimeout: 0
        property var hints: ({transient: true})
        property var actions: []
        property int dismissCalls: 0
        function dismiss() { dismissCalls++; closed() }
        function expire() { dismiss() }
    }

    Loader {
        id: serviceLoader
        onLoaded: {
            if (!item) return
            root.service = item
            root.serviceLoaded = true

            var restoredA = root.restoredEntry("restored-a", 1001)
            var restoredB = root.restoredEntry("restored-b", 1002)
            root.seedRestored(restoredA)
            root.seedRestored(restoredB)
            root.service.persistPopupFile(restoredA)
            root.service.persistPopupFile(restoredB)
            root.service.handleNotification(liveFirst)
            root.retryAdvance()
        }
        Component.onCompleted: {
            if (root.serviceSource !== "") setSource(root.serviceSource, {testMode: true})
        }
    }

    Item {
        width: 1
        height: 1
        visible: false

        Repeater {
            id: popupRepeater
            model: root.service ? root.service.popupModel : null

            delegate: Item {
                id: popupDelegate
                required property int index
                required property var originalId
                required property double timestamp

                function emitClose(malformed) {
                    if (!toastLoader.item) return false
                    toastLoader.item.identityIndex = popupDelegate.index
                    if (malformed) {
                        toastLoader.item.identityOriginalId = undefined
                        toastLoader.item.identityTimestamp = 0
                    } else {
                        toastLoader.item.identityOriginalId = popupDelegate.originalId
                        toastLoader.item.identityTimestamp = popupDelegate.timestamp
                    }
                    toastLoader.item.dismissFromClose()
                    return true
                }

                function emitCardDismissed(malformed) {
                    if (!toastLoader.item) return false
                    toastLoader.item.identityIndex = popupDelegate.index
                    if (malformed) {
                        toastLoader.item.identityOriginalId = undefined
                        toastLoader.item.identityTimestamp = 0
                    } else {
                        toastLoader.item.identityOriginalId = popupDelegate.originalId
                        toastLoader.item.identityTimestamp = popupDelegate.timestamp
                    }
                    toastLoader.item.dismissFromPointer(Qt.RightButton)
                    return true
                }

                Loader {
                    id: toastLoader
                    anchors.fill: parent
                    source: root.toastSource
                    onLoaded: {
                        item.identityOriginalId = popupDelegate.originalId
                        item.identityTimestamp = popupDelegate.timestamp
                        item.identityIndex = popupDelegate.index
                    }
                }

                Connections {
                    target: toastLoader.item
                    function onDismissed(originalId, timestamp, index) {
                        root.service.dismissPopupAt(index, originalId, timestamp)
                    }
                }
            }
        }
    }

    Timer {
        id: advanceTimer
        interval: 60
        repeat: false
        onTriggered: root.advance()
    }

    Process {
        id: popupCountProcess
        running: false
        stdout: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            if (code !== 0) return root.writeResult()
            var output = String(popupCountProcess.stdout.text || "").trim()
            root.popupFiles = output === "" ? 0 : output.split("\n").length
            historyCountProcess.command = ["/usr/bin/find", root.service.historyDir,
                "-maxdepth", "1", "-type", "f", "-name", "*.json"]
            historyCountProcess.running = true
        }
    }

    Process {
        id: historyCountProcess
        running: false
        stdout: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            if (code === 0) {
                var output = String(historyCountProcess.stdout.text || "").trim()
                root.historyFiles = output === "" ? 0 : output.split("\n").length
            }
            root.writeResult()
        }
    }

    FileView {
        id: resultFile
        path: root.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: false
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    Timer {
        interval: 7000
        running: true
        repeat: false
        onTriggered: if (!root.finished) root.writeResult()
    }

    function restoredEntry(summary, timestamp) {
        return {
            id: 1,
            originalId: 1,
            timestamp: timestamp,
            app: "Restored Collision",
            appIcon: "",
            desktopEntry: "restored-collision",
            summary: summary,
            body: summary + " body",
            image: "",
            glyph: "",
            execArgv: "",
            actions: [],
            defaultActionText: "",
            urgency: 1,
            expireTimeout: 0,
            deadline: 0,
            transient: true
        }
    }

    function seedRestored(entry) {
        var fileName = String(entry.timestamp) + "-" + String(entry.originalId) + ".json"
        var restored = root.service.restoredPopups
        restored[fileName] = true
        root.service.restoredPopups = restored
        root.service.activeModel.append(entry)
        root.service.popupModel.append(entry)
    }

    function queuesBusy() {
        return root.service.popupFileQueue.length > 0 ||
            root.service.runningPopupFileJob !== null ||
            root.service.popupFileProcess.running ||
            root.service.popupFileRetryTimer.running
    }

    function retryAdvance() {
        if (!root.finished) advanceTimer.restart()
    }

    function advance() {
        if (!root.service || root.finished || queuesBusy()) return root.retryAdvance()

        if (root.phase === 0) {
            if (root.service.popupModel.count !== 3) return root.retryAdvance()
            var oldest = popupRepeater.itemAt(2)
            if (!oldest || !oldest.emitClose(true)) return root.retryAdvance()
            root.popupMalformedCovered = true
            root.phase = 1
            return root.retryAdvance()
        }

        if (root.phase === 1) {
            if (root.service.historyModel.count < 1) return root.retryAdvance()
            root.service.handleNotification(liveSecond)
            root.phase = 2
            return root.retryAdvance()
        }

        if (root.phase === 2) {
            if (root.service.popupModel.count !== 2) return root.retryAdvance()
            root.replacementPreservedRestored = root.service.activeModel.count === 2
            var restored = popupRepeater.itemAt(1)
            if (!restored || !restored.emitCardDismissed(true)) return root.retryAdvance()
            root.secondPopupMalformedCovered = true
            root.phase = 3
            return root.retryAdvance()
        }

        if (root.phase === 3) {
            if (root.service.historyModel.count < 2 || root.service.popupModel.count !== 1)
                return root.retryAdvance()
            var current = popupRepeater.itemAt(0)
            if (!current || !current.emitClose(false)) return root.retryAdvance()
            root.phase = 4
            return root.retryAdvance()
        }

        if (root.phase === 4) {
            if (queuesBusy() || root.service.historyModel.count < 3 ||
                root.service.activeModel.count !== 0 || root.service.popupModel.count !== 0)
                return root.retryAdvance()
            if (!root.stateCountRequested) {
                root.stateCountRequested = true
                popupCountProcess.command = ["/usr/bin/find", root.service.popupStateDir,
                    "-maxdepth", "1", "-type", "f", "-name", "*.json"]
                popupCountProcess.running = true
            }
        }
    }

    function writeResult() {
        if (root.finished || !root.service || root.resultPath === "") return
        root.finished = true
        var summaries = []
        for (var i = 0; i < root.service.historyModel.count; i++)
            summaries.push(String(root.service.historyModel.get(i).summary || ""))
        resultFile.setText(JSON.stringify({
            loaded: root.serviceLoaded,
            phase: root.phase,
            activeCount: root.service.activeModel.count,
            popupCount: root.service.popupModel.count,
            historyCount: root.service.historyModel.count,
            historySummaries: summaries,
            popupFiles: root.popupFiles,
            historyFiles: root.historyFiles,
            popupMalformedCovered: root.popupMalformedCovered,
            secondPopupMalformedCovered: root.secondPopupMalformedCovered,
            replacementPreservedRestored: root.replacementPreservedRestored,
            firstDismissCalls: liveFirst.dismissCalls,
            secondDismissCalls: liveSecond.dismissCalls
        }) + "\n")
    }

}
