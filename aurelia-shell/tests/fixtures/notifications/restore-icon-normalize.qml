import QtQuick
import Quickshell
import Quickshell.Io

// Isolated fixture for the restore-time legacy icon normalisation. It seeds two
// on-disk Inbox rows that both predate the empty-default fix: one stores the
// generic `application-x-executable` glyph with no icon evidence at all, and
// one stores a genuinely resolved durable icon. The production Service must
// clear only the evidence-free row (and rewrite only that row's own file) and
// leave the resolved row exactly as it was. It never owns a live notification
// bus or desktop surface.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_NOTIFICATION_ICON_NORMALIZE_RESULT") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_NOTIFICATION_ICON_NORMALIZE_SERVICE_SOURCE") || ""
    readonly property string legacyIcon: "application-x-executable"
    property bool finished: false
    property bool serviceLoaded: false
    property var service: null
    property bool seeded: false
    property bool restoreStarted: false
    property int restoredActive: -1
    property string staleModelAppIcon: "<unset>"
    property string staleDiskAppIcon: "<unset>"
    property string provenModelAppIcon: "<unset>"
    property string provenDiskAppIcon: "<unset>"
    property string readPhase: ""
    property string staleFile: ""
    property string provenFile: ""

    Loader {
        id: serviceLoader
        onLoaded: {
            if (!item) return
            root.service = item
            root.serviceLoaded = true
            Qt.callLater(root.seed)
        }
        Component.onCompleted: {
            if (root.serviceSource !== "") setSource(root.serviceSource, {testMode: true})
        }
    }

    Process {
        id: seedProcess
        running: false
        onExited: function(code) {
            if (code !== 0) { root.writeResult(); return }
            root.seeded = true
            // Exercise the same production file-directory restore path the
            // shell uses after a reload.
            root.service.readPopupDirectory()
            root.restoreStarted = true
            pollTimer.start()
        }
    }

    Process {
        id: catProcess
        running: false
        stdout: StdioCollector {
            id: catStdout
            waitForEnd: true
        }
        onExited: function(code) {
            var text = code === 0 ? String(catStdout.text || "").trim() : ""
            if (root.readPhase === "stale") {
                root.staleDiskAppIcon = root.appIconOf(text)
                root.readPhase = "proven"
                catProcess.command = ["/usr/bin/cat", root.provenFile]
                catProcess.running = true
            } else if (root.readPhase === "proven") {
                root.provenDiskAppIcon = root.appIconOf(text)
                root.readPhase = "done"
                root.writeResult()
            }
        }
    }

    Timer {
        id: pollTimer
        interval: 60
        repeat: true
        onTriggered: root.poll()
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

    function staleRow(timestamp) {
        return {
            id: 21, originalId: 21, timestamp: timestamp,
            app: "Herdr", appIcon: root.legacyIcon, desktopEntry: "",
            summary: "stale legacy icon", body: "stale legacy icon", image: "",
            glyph: "", execArgv: "", actions: [], defaultActionText: "",
            urgency: 1, expireTimeout: 0, deadline: 0, transient: false,
            hints: {}, origin: ""
        }
    }

    function provenRow(timestamp, iconUrl) {
        return {
            id: 22, originalId: 22, timestamp: timestamp,
            app: "Foot", appIcon: iconUrl, desktopEntry: "foot",
            summary: "proven legacy icon", body: "proven legacy icon", image: "",
            glyph: "", execArgv: "", actions: [], defaultActionText: "",
            urgency: 1, expireTimeout: 0, deadline: 0, transient: false,
            hints: {}, origin: ""
        }
    }

    function seed() {
        if (!root.service || root.seeded) return
        var dir = root.service.popupStateDir
        var images = root.service.imagesDir
        if (dir === "" || images === "") { root.writeResult(); return }
        var now = Date.now()
        var stale = root.staleRow(now - 1000)
        var proven = root.provenRow(now - 900, "file://" + images + String(now - 900) + "-22-appIcon")
        root.staleFile = dir + String(stale.timestamp) + "-21.json"
        root.provenFile = dir + String(proven.timestamp) + "-22.json"
        seedProcess.command = ["/usr/bin/bash", "-c",
            "set -Eeuo pipefail\n" +
            "dir=\"$1\"; images=\"$2\"; stale=\"$3\"; proven=\"$4\"; staleFile=\"$5\"; provenFile=\"$6\"; provenIcon=\"$7\"\n" +
            "mkdir -p -- \"$dir\" \"$images\"\n" +
            "printf 'icon' > \"$provenIcon\"\n" +
            "printf '%s\\n' \"$stale\" > \"$staleFile\"\n" +
            "printf '%s\\n' \"$proven\" > \"$provenFile\"\n",
            "--", dir, images, JSON.stringify(stale), JSON.stringify(proven),
            root.staleFile, root.provenFile,
            images + String(proven.timestamp) + "-22-appIcon"]
        seedProcess.running = true
    }

    function queueIdle() {
        return root.service &&
            root.service.popupFileQueue.length === 0 &&
            root.service.runningPopupFileJob === null &&
            !root.service.popupFileProcess.running &&
            !root.service.popupFileRetryTimer.running
    }

    function poll() {
        if (root.finished || root.readPhase !== "") return
        if (!root.restoreStarted || !root.service) return
        if (root.service.activeModel.count < 2 || !root.queueIdle()) return
        pollTimer.stop()
        root.restoredActive = root.service.activeModel.count
        for (var i = 0; i < root.service.activeModel.count; i++) {
            var candidate = root.service.activeModel.get(i)
            if (String(candidate.body) === "stale legacy icon")
                root.staleModelAppIcon = String(candidate.appIcon || "")
            if (String(candidate.body) === "proven legacy icon")
                root.provenModelAppIcon = String(candidate.appIcon || "")
        }
        root.readPhase = "stale"
        catProcess.command = ["/usr/bin/cat", root.staleFile]
        catProcess.running = true
    }

    function appIconOf(text) {
        if (text === "") return "<missing>"
        try {
            return String(JSON.parse(text).appIcon || "")
        } catch (error) {
            console.warn("[ICON-NORMALIZE] popup_json_parse_failed")
            return "<unparseable>"
        }
    }

    function writeResult() {
        if (root.finished || !root.service || root.resultPath === "") return
        root.finished = true
        resultFile.setText(JSON.stringify({
            serviceLoaded: root.serviceLoaded,
            seeded: root.seeded,
            restoredActive: root.restoredActive,
            staleModelAppIcon: root.staleModelAppIcon,
            staleDiskAppIcon: root.staleDiskAppIcon,
            provenModelAppIcon: root.provenModelAppIcon,
            provenDiskAppIcon: root.provenDiskAppIcon
        }) + "\n")
    }
}
