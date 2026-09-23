import QtQuick
import Quickshell
import Quickshell.Io

// Isolated fixture for durable app-icon retention. It drives the production
// Service in testMode with an ephemeral `image://icon//tmp/...` app icon and
// image, waits for the persistence queue to drain, then proves the live models
// and snapshots now carry the durable copied path that the on-disk JSON holds.
// It never owns a live notification bus or desktop surface.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_NOTIFICATION_DURABLE_ICON_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_NOTIFICATION_DURABLE_ICON_SERVICE_SOURCE") || ""
    readonly property string sourceIcon: Quickshell.env("AURELIA_NOTIFICATION_DURABLE_ICON_SOURCE") || ""
    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property string activeAppIcon: ""
    property string activeImage: ""
    property string popupAppIcon: ""
    property string liveAppIcon: ""
    property string diskAppIcon: ""
    property string diskImage: ""
    property int activeActionsCount: -1
    property int popupActionsCount: -1

    QtObject {
        id: ephemeralNotification
        signal closed()
        property bool tracked: false
        property int id: 77
        property string appName: "Chromium"
        property string appIcon: root.sourceIcon !== "" ? "image://icon/" + root.sourceIcon : ""
        property string desktopEntry: "chromium"
        property string summary: "Durable icon"
        property string body: "body"
        property string image: root.sourceIcon !== "" ? "image://icon/" + root.sourceIcon : ""
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
        printErrors: true
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    function start() {
        if (root.sourceIcon === "") {
            console.error("[DURABLE-ICON] source_icon_missing")
            root.writeResult()
            return
        }
        root.service.handleNotification(ephemeralNotification)
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
        var jsonPath = root.service.popupStateDir + stem + ".json"
        readPopupProcess.command = ["/usr/bin/cat", jsonPath]
        readPopupProcess.running = true
    }

    function durablePath(stem, role) {
        var path = root.service.imagesDir + stem + "-" + role
        return "file://" + path
    }

    function writeResult() {
        if (root.finished || !root.service || root.resultPath === "") return
        root.finished = true
        var activeRow = root.service.activeModel.count > 0
            ? root.service.activeModel.get(0) : null
        var stem = activeRow
            ? String(activeRow.timestamp) + "-" + String(activeRow.originalId) : ""
        var expectedAppIcon = stem !== "" ? durablePath(stem, "appIcon") : ""
        var expectedImage = stem !== "" ? durablePath(stem, "image") : ""
        resultFile.setText(JSON.stringify({
            serviceLoaded: root.serviceLoaded,
            activeAppIcon: root.activeAppIcon,
            activeImage: root.activeImage,
            popupAppIcon: root.popupAppIcon,
            liveAppIcon: root.liveAppIcon,
            activeActionsCount: root.activeActionsCount,
            popupActionsCount: root.popupActionsCount,
            diskAppIcon: root.diskAppIcon,
            diskImage: root.diskImage,
            expectedAppIcon: expectedAppIcon,
            expectedImage: expectedImage,
            appIconRetained: root.activeAppIcon === expectedAppIcon &&
                root.activeAppIcon.indexOf("image://") !== 0 &&
                root.activeAppIcon.indexOf(root.sourceIcon) === -1,
            imageRetained: root.activeImage === expectedImage &&
                root.activeImage.indexOf("image://") !== 0 &&
                root.activeImage.indexOf(root.sourceIcon) === -1,
            popupRetained: root.popupAppIcon === expectedAppIcon,
            activeActionsRetained: root.activeActionsCount === 1,
            popupActionsRetained: root.popupActionsCount === 1,
            liveRetained: root.liveAppIcon === expectedAppIcon,
            diskMatchesModel: root.diskAppIcon === expectedAppIcon &&
                root.diskImage === expectedImage
        }) + "\n")
    }
}
