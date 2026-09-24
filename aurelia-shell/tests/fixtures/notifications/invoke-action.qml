import QtQuick
import Quickshell
import Quickshell.Io

// Isolated fixture for the retained-Inbox action path. It drives the real
// Service in testMode with a Chromium-shaped notification that offers a
// `settings` non-default action, drains the durable file queue, then closes
// the sender notification. Chromium destroys its D-Bus notification object on
// close, so the live reference is gone while the Inbox row (and its Settings
// button) is retained. The fixture proves the durable row survives with a
// materialized `actions` role, that the real NotificationToast still renders
// the `settings` identifier, and that invokeAction resolves the durable row
// instead of returning "unavailable". It also proves a notification with only
// non-default actions still shows its action row.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_NOTIFICATION_INVOKE_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_NOTIFICATION_INVOKE_SERVICE_SOURCE") || ""
    readonly property string toastSource: Quickshell.env("AURELIA_NOTIFICATION_INVOKE_TOAST_SOURCE") || ""
    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property int phase: 0
    property bool senderClosed: false
    property int activeCountAfterClose: -1
    property int actionsCountAfterClose: -1
    property bool actionsRoleUndefinedAfterClose: false
    property string firstActionIdentifier: ""
    property string invokeResult: ""
    property bool routeStarted: false
    property int retainedSettingsButtonCount: -1
    property bool nonDefaultOnlyContainerVisible: false
    property int nonDefaultOnlySettingsButtonCount: -1
    property var toastComponent: null
    property var retainedToast: null
    property var nonDefaultOnlyToast: null

    QtObject {
        id: chromiumNotification
        signal closed()
        property bool tracked: false
        property int id: 88
        property string appName: "Chromium"
        property string appIcon: "chromium"
        property string desktopEntry: "chromium"
        property string summary: "Chromium"
        property string body: "A page wants to show notifications"
        property string image: ""
        property int urgency: 1
        property int expireTimeout: 0
        property var hints: ({})
        property var actions: [
            { identifier: "default", text: "Activate" },
            { identifier: "settings", text: "Settings" }
        ]
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

    Timer {
        id: queueTimer
        interval: 60
        repeat: true
        onTriggered: root.captureIfIdle()
    }

    Timer {
        interval: 6000
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
        root.service.handleNotification(chromiumNotification)
        queueTimer.start()
    }

    function queueIdle() {
        return root.service &&
            root.service.popupFileQueue.length === 0 &&
            root.service.runningPopupFileJob === null &&
            !root.service.popupFileProcess.running &&
            !root.service.popupFileRetryTimer.running
    }

    function captureIfIdle() {
        if (!root.service || root.finished || !queueIdle()) return
        queueTimer.stop()
        if (root.phase !== 0) return
        // The durable file is written; now the sender destroys its live
        // notification while Chromium's Inbox row is retained.
        chromiumNotification.closed()
        root.senderClosed = true
        root.phase = 1
        Qt.callLater(root.captureAfterClose)
    }

    function captureAfterClose() {
        if (root.finished || root.phase !== 1) return
        root.activeCountAfterClose = root.service.activeModel.count
        var activeRow = root.activeCountAfterClose > 0 ? root.service.activeModel.get(0) : null
        var actions = activeRow ? activeRow.actions : undefined
        root.actionsRoleUndefinedAfterClose = actions === undefined
        root.actionsCountAfterClose = actions === undefined ? -1
            : (typeof actions.count === "number" ? actions.count : -1)
        if (actions !== undefined && typeof actions.get === "function" && actions.count > 0) {
            var first = actions.get(0)
            root.firstActionIdentifier = first ? String(first.identifier || "") : ""
        }
        root.phase = 2
        root.buildRetainedToast(activeRow)
    }

    function ensureToastComponent() {
        if (root.toastComponent) return root.toastComponent.status
        root.toastComponent = Qt.createComponent(root.toastSource)
        return root.toastComponent.status
    }

    function buildRetainedToast(activeRow) {
        if (!root.service || !activeRow || root.toastSource === "") {
            root.phase = 3
            Qt.callLater(root.buildNonDefaultOnlyToast)
            return
        }
        var status = root.ensureToastComponent()
        if (status === Component.Loading) {
            root.toastComponent.statusChanged.connect(root.materializeRetainedToast)
            return
        }
        root.materializeRetainedToast()
    }

    function materializeRetainedToast() {
        if (root.retainedToast || !root.toastComponent ||
            root.toastComponent.status !== Component.Ready) return
        var activeRow = root.service.activeModel.count > 0
            ? root.service.activeModel.get(0) : null
        if (!activeRow) {
            root.phase = 3
            Qt.callLater(root.buildNonDefaultOnlyToast)
            return
        }
        root.retainedToast = root.toastComponent.createObject(root, {
            app: String(activeRow.app || ""),
            appIcon: String(activeRow.appIcon || ""),
            summary: String(activeRow.summary || ""),
            body: String(activeRow.body || ""),
            showDismiss: false,
            defaultActionText: String(activeRow.defaultActionText || ""),
            actions: activeRow.actions
        })
        root.phase = 2
        pollTimer.start()
    }

    function buildNonDefaultOnlyToast() {
        if (root.finished || root.phase !== 3) return
        if (root.toastSource === "") {
            root.phase = 4
            Qt.callLater(root.invokeDurableAction)
            return
        }
        var status = root.ensureToastComponent()
        if (status === Component.Loading) {
            root.toastComponent.statusChanged.connect(root.materializeNonDefaultOnlyToast)
            return
        }
        root.materializeNonDefaultOnlyToast()
    }

    function materializeNonDefaultOnlyToast() {
        if (root.nonDefaultOnlyToast || !root.toastComponent ||
            root.toastComponent.status !== Component.Ready) return
        root.nonDefaultOnlyToast = root.toastComponent.createObject(root, {
            app: "Chromium",
            appIcon: "chromium",
            summary: "Chromium",
            body: "A page wants to show notifications",
            showDismiss: false,
            defaultActionText: "",
            actions: [{ identifier: "settings", text: "Settings" }]
        })
        root.phase = 4
        pollTimer.start()
    }

    function nodesUnder(node, output) {
        if (!node) return output
        if (typeof node.objectName === "string" && node.objectName !== "") output.push(node)
        var children = node.children
        if (children) {
            for (var i = 0; i < children.length; i++) nodesUnder(children[i], output)
        }
        return output
    }

    function nodeNamed(name, nodes) {
        for (var i = 0; i < nodes.length; i++) {
            if (String(nodes[i].objectName) === name) return nodes[i]
        }
        return null
    }

    function countActionButtons(nodes, identifier) {
        var count = 0
        for (var i = 0; i < nodes.length; i++) {
            if (String(nodes[i].objectName) !== "notificationActionButton") continue
            var modelData = nodes[i].modelData
            if (modelData && String(modelData.identifier || "") === identifier) count++
        }
        return count
    }

    function step() {
        if (root.finished) return
        if (root.phase === 2 && root.retainedToast) {
            var retainedNodes = nodesUnder(root.retainedToast, [])
            root.retainedSettingsButtonCount = root.countActionButtons(retainedNodes, "settings")
            root.phase = 3
            pollTimer.stop()
            Qt.callLater(root.buildNonDefaultOnlyToast)
            return
        }
        if (root.phase === 4 && root.nonDefaultOnlyToast) {
            var nodes = nodesUnder(root.nonDefaultOnlyToast, [])
            var container = nodeNamed("notificationActionContainer", nodes)
            root.nonDefaultOnlyContainerVisible = container ? container.visible === true : false
            root.nonDefaultOnlySettingsButtonCount = root.countActionButtons(nodes, "settings")
            root.phase = 5
            pollTimer.stop()
            Qt.callLater(root.invokeDurableAction)
            return
        }
    }

    Timer {
        id: pollTimer
        interval: 50
        repeat: true
        running: false
        onTriggered: root.step()
    }

    function invokeDurableAction() {
        if (root.finished) return
        var activeRow = root.service.activeModel.count > 0
            ? root.service.activeModel.get(0) : null
        if (!activeRow) {
            root.writeResult()
            return
        }
        var originalId = activeRow.originalId
        var timestamp = Number(activeRow.timestamp)
        root.invokeResult = String(root.service.invokeAction(0, "settings", originalId, timestamp))
        root.routeStarted = root.service.pendingWorkspaceRoute !== null &&
            root.service.pendingWorkspaceRoute !== undefined
        root.writeResult()
    }

    function writeResult() {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        pollTimer.stop()
        resultFile.setText(JSON.stringify({
            serviceLoaded: root.serviceLoaded,
            senderClosed: root.senderClosed,
            activeCountAfterClose: root.activeCountAfterClose,
            actionsCountAfterClose: root.actionsCountAfterClose,
            actionsRoleUndefinedAfterClose: root.actionsRoleUndefinedAfterClose,
            firstActionIdentifier: root.firstActionIdentifier,
            invokeResult: root.invokeResult,
            routeStarted: root.routeStarted,
            retainedSettingsButtonCount: root.retainedSettingsButtonCount,
            nonDefaultOnlyContainerVisible: root.nonDefaultOnlyContainerVisible,
            nonDefaultOnlySettingsButtonCount: root.nonDefaultOnlySettingsButtonCount
        }) + "\n")
    }
}
