import QtQuick
import Quickshell
import Quickshell.Io

// T48 fixture. The production Service is constructed in testMode so no live
// notification bus or desktop surface is owned, while its identity, models,
// persistence queue, and sender-closed callback remain real.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_NOTIFICATION_DISMISSAL_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_NOTIFICATION_SERVICE_SOURCE") || ""
    readonly property string toastSource: Quickshell.env("AURELIA_NOTIFICATION_TOAST_SOURCE") || ""
    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property var firstNotification: null
    property var secondNotification: null
    property var thirdNotification: null
    property var dismissedIds: []
    property bool malformedFallback: false
    property bool mismatchedIdentityPreserved: false
    property bool pointerPathCovered: false
    property bool popupMalformedIdentityCovered: false
    property bool popupSourceMode: true
    property int dismissPass: 0
    property bool dismissalComplete: false
    property bool stateCountRequested: false
    property int popupFiles: -1
    property int historyFiles: -1

    QtObject {
        id: first
        signal closed()
        property bool tracked: false
        property int id: 41
        property string appName: "Dismissal Fixture One"
        property string appIcon: ""
        property string desktopEntry: "fixture-one"
        property string summary: "First notification"
        property string body: "First body"
        property int urgency: 1
        property int expireTimeout: 0
        property var hints: ({})
        property var actions: []
        property int dismissCalls: 0
        function dismiss() { dismissCalls++; closed() }
        function expire() { dismiss() }
    }

    QtObject {
        id: second
        signal closed()
        property bool tracked: false
        property int id: 42
        property string appName: "Dismissal Fixture Two"
        property string appIcon: ""
        property string desktopEntry: "fixture-two"
        property string summary: "Second notification"
        property string body: "Second body"
        property int urgency: 1
        property int expireTimeout: 0
        property var hints: ({})
        property var actions: []
        property int dismissCalls: 0
        function dismiss() { dismissCalls++; closed() }
        function expire() { dismiss() }
    }

    QtObject {
        id: third
        signal closed()
        property bool tracked: false
        property int id: 43
        property string appName: "Dismissal Fixture Three"
        property string appIcon: ""
        property string desktopEntry: "fixture-three"
        property string summary: "Third notification"
        property string body: "Third body"
        property int urgency: 1
        property int expireTimeout: 0
        property var hints: ({})
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
            root.firstNotification = first
            root.secondNotification = second
            root.thirdNotification = third
            root.service.handleNotification(first)
            root.service.handleNotification(second)
            Qt.callLater(root.dismissThroughToast)
        }
        Component.onCompleted: {
            if (root.serviceSource !== "")
                setSource(root.serviceSource, {testMode: true})
        }
    }

    Item {
        width: 1
        height: 1
        visible: false

        Repeater {
            id: notificationRepeater
            model: root.service
                ? (root.popupSourceMode ? root.service.popupModel : root.service.activeModel)
                : null

            delegate: Item {
                id: notificationDelegate
                required property int index
                required property var originalId
                required property double timestamp
                required property var app
                required property var appIcon
                required property var desktopEntry
                required property var summary
                required property var body
                required property var image
                required property var glyph
                required property var execArgv
                required property var actions
                required property var defaultActionText
                required property int urgency

                function emitDismissed() {
                    if (!toastLoader.item) return false
                    if (root.popupSourceMode && root.dismissPass === 1) {
                        // Model a real delegate identity race: the popup row
                        // remains authoritative while the Toast signal loses
                        // its optional identity fields.
                        toastLoader.item.identityOriginalId = undefined
                        toastLoader.item.identityTimestamp = 0
                        toastLoader.item.identityIndex = notificationDelegate.index
                        root.popupMalformedIdentityCovered = true
                    }
                    toastLoader.item.dismissFromClose()
                    return true
                }

                function emitCardDismissed() {
                    if (!toastLoader.item) return false
                    root.pointerPathCovered = true
                    toastLoader.item.dismissFromPointer(Qt.RightButton)
                    return true
                }

                Loader {
                    id: toastLoader
                    anchors.fill: parent
                    source: root.toastSource
                    onLoaded: {
                        item.app = String(notificationDelegate.app || "")
                        item.appIcon = String(notificationDelegate.appIcon || "")
                        item.desktopEntry = String(notificationDelegate.desktopEntry || "")
                        item.summary = String(notificationDelegate.summary || "")
                        item.body = String(notificationDelegate.body || "")
                        item.image = String(notificationDelegate.image || "")
                        item.glyph = String(notificationDelegate.glyph || "")
                        item.execArgv = String(notificationDelegate.execArgv || "")
                        item.actions = notificationDelegate.actions || []
                    item.defaultActionText = String(notificationDelegate.defaultActionText || "")
                    item.urgency = notificationDelegate.urgency
                    item.identityOriginalId = notificationDelegate.originalId
                    item.identityTimestamp = notificationDelegate.timestamp
                    item.identityIndex = notificationDelegate.index
                    item.showDismiss = true
                    }
                }

                Connections {
                    target: toastLoader.item
                    function onDismissed(originalId, timestamp, index) {
                        if (root.popupSourceMode)
                            root.service.dismissPopupAt(index, originalId, timestamp)
                        else
                            root.service.dismissAt(index, originalId, timestamp)
                    }
                }
            }
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
        id: dismissRetryTimer
        interval: 100
        repeat: false
        onTriggered: root.dismissThroughToast()
    }

    Timer {
        id: finishTimer
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (!root.service || root.finished || !root.dismissalComplete) return
            if (root.service.popupFileQueue.length > 0 ||
                root.service.runningPopupFileJob !== null ||
                root.service.popupFileProcess.running ||
                root.service.popupFileRetryTimer.running) return
            if (root.stateCountRequested) return
            root.stateCountRequested = true
            popupCountProcess.command = ["/usr/bin/find", root.service.popupStateDir,
                "-maxdepth", "1", "-type", "f", "-name", "*.json"]
            popupCountProcess.running = true
        }
    }

    Process {
        id: popupCountProcess
        running: false
        stdout: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            if (code !== 0) {
                root.writeResult()
                return
            }
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
            if (code !== 0) {
                root.writeResult()
                return
            }
            var output = String(historyCountProcess.stdout.text || "").trim()
            root.historyFiles = output === "" ? 0 : output.split("\n").length
            root.writeResult()
        }
    }

    Timer {
        id: timeoutTimer
        interval: 5000
        running: true
        repeat: false
        onTriggered: if (!root.finished) root.writeResult()
    }

    function dismissThroughToast() {
        if (!root.service || root.finished) return
        if (root.dismissPass < 2) {
            var expectedActive = 2 - root.dismissPass
            if (root.service.activeModel.count !== expectedActive) {
                dismissRetryTimer.restart()
                return
            }
            var delegate = notificationRepeater.itemAt(0)
            if (!delegate) {
                dismissRetryTimer.restart()
                return
            }
            var sourceModel = root.popupSourceMode
                ? root.service.popupModel : root.service.activeModel
            var sourceRow = sourceModel.get(0)
            if (!sourceRow || String(delegate.originalId) !== String(sourceRow.originalId) ||
                Number(delegate.timestamp) !== Number(sourceRow.timestamp)) {
                // A Repeater can retain the removed delegate for one event-loop
                // turn. Never simulate a close from that stale identity.
                dismissRetryTimer.restart()
                return
            }
            root.dismissedIds = root.dismissedIds.concat([Number(delegate.originalId)])
            var emitted = root.dismissPass === 0
                ? delegate.emitCardDismissed() : delegate.emitDismissed()
            if (!emitted) {
                dismissRetryTimer.restart()
                return
            }
            root.dismissPass++
            if (root.dismissPass >= 2) root.popupSourceMode = false
            Qt.callLater(root.dismissThroughToast)
            return
        }

        // Exercise an incomplete delegate identity explicitly. The service
        // must recover the authoritative row by index rather than creating a
        // zero identity or leaving the notification stuck.
        if (root.thirdNotification === null) return
        if (root.service.activeModel.count === 0) {
            root.service.handleNotification(third)
            Qt.callLater(root.dismissThroughToast)
            return
        }
        if (root.service.activeModel.count !== 1) {
            dismissRetryTimer.restart()
            return
        }
        var beforeMismatch = root.service.activeModel.count
        root.service.dismissAt(0, 999, 1789300000000)
        root.mismatchedIdentityPreserved = root.service.activeModel.count === beforeMismatch
        var malformedBefore = root.service.activeModel.count
        root.service.dismissAt(0, undefined, undefined)
        root.malformedFallback = root.service.activeModel.count === malformedBefore - 1
        root.dismissedIds = root.dismissedIds.concat([43])
        root.thirdNotification = null
        root.dismissalComplete = true
    }

    function writeResult() {
        if (root.finished || !root.service || root.resultPath === "") return
        root.finished = true
        var rows = []
        for (var i = 0; i < root.service.historyModel.count; i++)
            rows.push(root.service.historyModel.get(i))
        var activeRows = []
        for (var j = 0; j < root.service.activeModel.count; j++)
            activeRows.push(root.service.activeModel.get(j))
        var popupRows = []
        for (var k = 0; k < root.service.popupModel.count; k++)
            popupRows.push(root.service.popupModel.get(k))
        resultFile.setText(JSON.stringify({
            serviceLoaded: root.serviceLoaded,
            activeCount: root.service.activeModel.count,
            popupCount: root.service.popupModel.count,
            historyCount: root.service.historyModel.count,
            popupFiles: root.popupFiles,
            historyFiles: root.historyFiles,
            historyRows: rows,
            activeRows: activeRows,
            popupRows: popupRows,
            dismissedIds: root.dismissedIds,
            malformedFallback: root.malformedFallback,
            mismatchedIdentityPreserved: root.mismatchedIdentityPreserved,
            pointerPathCovered: root.pointerPathCovered,
            popupMalformedIdentityCovered: root.popupMalformedIdentityCovered,
            firstDismissCalls: first.dismissCalls,
            secondDismissCalls: second.dismissCalls,
            thirdDismissCalls: third.dismissCalls,
            firstTracked: first.tracked,
            secondTracked: second.tracked,
            thirdTracked: third.tracked
        }) + "\n")
    }
}
