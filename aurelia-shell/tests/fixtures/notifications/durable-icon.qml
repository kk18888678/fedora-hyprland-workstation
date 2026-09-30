import QtQuick
import Quickshell
import Quickshell.Io

// Isolated fixture for the notification icon pipeline. It drives the real
// Service in testMode with a notification whose only icon is one of the forms
// the shared AppIconResolver must own, waits for the persistence queue to
// drain, then proves the live model, the live snapshot, and the on-disk JSON
// all carry a durable value (our own file:// copy or a theme/default name),
// never the sender's transient path. It finally renders the real
// NotificationToast from the persisted value and records the real
// Image.status, so a suite that passes while foot still shows no icon cannot
// exist. It never owns a live notification bus or desktop surface.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_NOTIFICATION_DURABLE_ICON_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_NOTIFICATION_DURABLE_ICON_SERVICE_SOURCE") || ""
    readonly property string toastSource: Quickshell.env("AURELIA_NOTIFICATION_DURABLE_ICON_TOAST_SOURCE") || ""
    readonly property string sourceIcon: Quickshell.env("AURELIA_NOTIFICATION_DURABLE_ICON_SOURCE") || ""
    readonly property string mode: Quickshell.env("AURELIA_NOTIFICATION_DURABLE_ICON_MODE") || "embedded"
    readonly property string metadataGateSource: Quickshell.env("AURELIA_NOTIFICATION_DURABLE_ICON_METADATA_GATE") || ""
    readonly property int imageReadyStatus: 1

    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property bool started: false
    property string activeAppIcon: ""
    property string activeImage: ""
    property string popupAppIcon: ""
    property string liveAppIcon: ""
    property string diskAppIcon: ""
    property string diskImage: ""
    property int activeActionsCount: -1
    property int popupActionsCount: -1
    property string expectedAppIcon: ""
    // Toast render results.
    property var toast: null
    property bool toastReady: false
    property bool toastSlotVisible: false
    property bool toastSymbolicVisible: false
    property bool toastFallbackVisible: false
    property string toastSourceValue: ""

    QtObject {
        id: testNotification
        signal closed()
        property bool tracked: false
        property int id: 77
        property string appName: "Chromium"
        property string appIcon: ""
        property string desktopEntry: "chromium"
        property string summary: "Durable icon"
        property string body: "body"
        property string image: ""
        property int urgency: 1
        property int expireTimeout: 0
        property var hints: ({})
        // A non-default action is what the destructive ListModel update used to
        // drop: the default button survives, the reply button disappears.
        property var actions: [
            { identifier: "default", text: "Open" },
            { identifier: "reply", text: "Reply" }
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
            if (root.mode === "desktop-race" && root.metadataGateSource !== "") {
                metadataLoader.source = root.metadataGateSource
            } else {
                Qt.callLater(root.start)
            }
        }
        Component.onCompleted: {
            if (root.serviceSource !== "") setSource(root.serviceSource, {testMode: true})
        }
    }

    Loader {
        id: metadataLoader
        onLoaded: {
            if (!item) { Qt.callLater(root.start); return }
            item.metadataReady.connect(root.start)
            // The gate may already be ready before the connection is made.
            Qt.callLater(function() {
                if (item.revision > 0) root.start()
            })
        }
    }

    Timer {
        id: queueTimer
        interval: 60
        repeat: true
        onTriggered: root.captureIfIdle()
    }

    Timer {
        interval: 7000
        running: true
        repeat: false
        onTriggered: if (!root.finished) root.writeResult()
    }

    Process {
        id: readPopupProcess
        running: false
        stdout: StdioCollector {
            id: readPopupStdout
            waitForEnd: true
        }
        onExited: function(code) {
            if (code === 0) {
                try {
                    var entry = JSON.parse(String(readPopupStdout.text || "").trim())
                    root.diskAppIcon = String(entry.appIcon || "")
                    root.diskImage = String(entry.image || "")
                } catch (error) {
                    console.error("[DURABLE-ICON] popup_json_parse_failed")
                }
            }
            root.renderToast()
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

    function start() {
        if (root.started || !root.service) return
        root.started = true
        if (root.mode === "embedded" && root.sourceIcon === "") {
            console.error("[DURABLE-ICON] source_icon_missing")
            root.writeResult()
            return
        }
        if (root.mode === "embedded") {
            testNotification.appName = "Chromium"
            testNotification.desktopEntry = "chromium"
            testNotification.appIcon = "image://icon/" + root.sourceIcon
            testNotification.image = "image://icon/" + root.sourceIcon
        } else if (root.mode === "themed") {
            testNotification.appName = "foot"
            testNotification.desktopEntry = "foot"
            testNotification.appIcon = ""
            testNotification.image = "image://icon/foot"
        } else if (root.mode === "ghostty") {
            testNotification.appName = "Ghostty"
            testNotification.desktopEntry = "com.mitchellh.ghostty"
            testNotification.appIcon = ""
            testNotification.image = ""
        } else if (root.mode === "screenshot") {
            // The screenshot path pairs a generic camera app icon with the real
            // captured image. The content image must win over the app icon.
            testNotification.appName = "aurelia-action"
            testNotification.desktopEntry = ""
            testNotification.appIcon = "camera-photo"
            testNotification.image = "file://" + root.sourceIcon
        } else if (root.mode === "desktop-race") {
            testNotification.appName = "Example Tool"
            testNotification.desktopEntry = "com.example.tool"
            testNotification.appIcon = ""
            testNotification.image = ""
        } else if (root.mode === "iconless") {
            // A genuinely iconless notification: no app icon, no image, no
            // desktop entry, no hints, and no matching desktop file or theme
            // icon in the sandbox. It must persist and render as empty.
            testNotification.appName = "Iconless"
            testNotification.desktopEntry = ""
            testNotification.appIcon = ""
            testNotification.image = ""
        } else {
            testNotification.appName = "Missing"
            testNotification.desktopEntry = "missing-app"
            testNotification.appIcon = "file://" + "/nonexistent/aurelia-missing-logo.png"
            testNotification.image = ""
        }
        root.service.handleNotification(testNotification)
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
        var activeRow = root.service.activeModel.count > 0
            ? root.service.activeModel.get(0) : null
        var popupRow = root.service.popupModel.count > 0
            ? root.service.popupModel.get(0) : null
        if (!activeRow || !popupRow) {
            root.writeResult()
            return
        }
        root.activeAppIcon = String(activeRow.appIcon || "")
        root.activeImage = String(activeRow.image || "")
        root.popupAppIcon = String(popupRow.appIcon || "")
        root.activeActionsCount = activeRow.actions === undefined ? -1
            : (typeof activeRow.actions.count === "number" ? activeRow.actions.count : -1)
        root.popupActionsCount = popupRow.actions === undefined ? -1
            : (typeof popupRow.actions.count === "number" ? popupRow.actions.count : -1)
        var liveKey = root.service.liveKeyForOriginalId(activeRow.originalId)
        var live = liveKey !== "" ? root.service.liveSnapshots[liveKey] : null
        root.liveAppIcon = live ? String(live.appIcon || "") : ""
        var stem = String(activeRow.timestamp) + "-" + String(activeRow.originalId)
        root.expectedAppIcon = root.expectedValue(stem)
        var jsonPath = root.service.popupStateDir + stem + ".json"
        readPopupProcess.command = ["/usr/bin/cat", jsonPath]
        readPopupProcess.running = true
    }

    function expectedValue(stem) {
        if (root.mode === "themed") return "foot"
        if (root.mode === "ghostty") return "com.mitchellh.ghostty"
        if (root.mode === "desktop-race") return "example-tool"
        // An unresolved icon is persisted as the empty string and the card
        // draws nothing; there is no generic fallback glyph any more.
        if (root.mode === "missing" || root.mode === "iconless") return ""
        return "file://" + root.service.imagesDir + stem + "-appIcon"
    }

    // ------------------------------------------------------------------
    // Toast render
    // ------------------------------------------------------------------

    function renderToast() {
        if (root.finished || root.toastSource === "") {
            root.writeResult()
            return
        }
        var component = Qt.createComponent(root.toastSource)
        if (component.status === Component.Loading) {
            component.statusChanged.connect(function() {
                if (component.status === Component.Ready) root.materializeToast(component)
                else root.writeResult()
            })
            return
        }
        root.materializeToast(component)
    }

    function materializeToast(component) {
        if (component.status !== Component.Ready) {
            root.writeResult()
            return
        }
        root.toast = component.createObject(root, {
            app: testNotification.appName,
            appIcon: root.activeAppIcon,
            image: root.activeImage,
            desktopEntry: testNotification.desktopEntry,
            summary: "Icon render",
            body: "",
            glyph: "",
            showDismiss: false,
            showCopy: false,
            actions: []
        })
        toastPollTimer.start()
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

    function captureToast() {
        if (!root.toast) return
        var nodes = nodesUnder(root.toast, [])
        var iconNode = nodeNamed("notificationSourceIcon", nodes)
        var slotNode = nodeNamed("notificationIconSlot", nodes)
        var symbolicNode = nodeNamed("notificationSymbolicIcon", nodes)
        var fallbackNode = nodeNamed("notificationSourceIconFallback", nodes)
        root.toastSourceValue = iconNode ? String(iconNode.source) : ""
        root.toastReady = iconNode ? Number(iconNode.status) === root.imageReadyStatus : false
        root.toastSlotVisible = slotNode ? slotNode.visible === true : false
        root.toastSymbolicVisible = symbolicNode ? symbolicNode.visible === true : false
        root.toastFallbackVisible = fallbackNode ? fallbackNode.visible === true : false
    }

    Timer {
        id: toastPollTimer
        interval: 50
        repeat: true
        running: false
        onTriggered: {
            root.captureToast()
            if (root.toastReady || root.toastSymbolicVisible ||
                root.toastFallbackVisible || root.toastSourceValue === "" ||
                !root.toast) {
                toastPollTimer.stop()
                root.writeResult()
            }
        }
    }

    function writeResult() {
        if (root.finished || !root.service || root.resultPath === "") return
        root.finished = true
        var isFile = root.activeAppIcon.indexOf("file://") === 0
        var isName = !isFile && root.activeAppIcon.indexOf("image://") !== 0 &&
            root.activeAppIcon.charAt(0) !== "/" && root.activeAppIcon !== ""
        resultFile.setText(JSON.stringify({
            serviceLoaded: root.serviceLoaded,
            mode: root.mode,
            activeAppIcon: root.activeAppIcon,
            activeImage: root.activeImage,
            popupAppIcon: root.popupAppIcon,
            liveAppIcon: root.liveAppIcon,
            diskAppIcon: root.diskAppIcon,
            diskImage: root.diskImage,
            expectedAppIcon: root.expectedAppIcon,
            activeActionsCount: root.activeActionsCount,
            popupActionsCount: root.popupActionsCount,
            appIconIsFile: isFile,
            appIconIsName: isName,
            noSenderPath: root.sourceIcon === "" || root.activeAppIcon.indexOf(root.sourceIcon) === -1,
            noProvider: root.activeAppIcon.indexOf("image://") !== 0,
            imageCleared: root.activeImage === "",
            matchesExpected: root.activeAppIcon === root.expectedAppIcon,
            diskMatchesModel: root.diskAppIcon === root.activeAppIcon &&
                root.diskImage === root.activeImage,
            liveMatchesModel: root.liveAppIcon === root.activeAppIcon,
            activeActionsRetained: root.activeActionsCount === 1,
            popupActionsRetained: root.popupActionsCount === 1,
            toastReady: root.toastReady,
            toastSlotVisible: root.toastSlotVisible,
            toastSymbolicVisible: root.toastSymbolicVisible,
            toastFallbackVisible: root.toastFallbackVisible,
            toastSource: root.toastSourceValue
        }) + "\n")
    }
}
