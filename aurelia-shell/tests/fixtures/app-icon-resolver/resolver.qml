import QtQuick
import Quickshell
import Quickshell.Io
import "../../../services"

// Isolated probe body for the shared AppIconResolver. It is loaded through a
// Loader by shell.qml because Quickshell only resolves relative directory
// imports (services/theme) for loaded children, not for the root config file.
// It exercises every form of the ordered chain against the real QML owner and
// asserts the resolved slot through real Image.status values, not string
// shape. The disposable XDG data dir supplied by the test runner provides
// deterministic desktop entries and theme icons; no live shell, compositor, or
// user configuration is touched.
Item {
    id: probe

    readonly property string resultPath: Quickshell.env("AURELIA_APP_ICON_RESULT") || ""
    readonly property string samplePng: Quickshell.env("AURELIA_APP_ICON_PNG") || ""
    readonly property string missingPng: Quickshell.env("AURELIA_APP_ICON_MISSING") || ""
    property var cases: []
    property bool finished: false

    FileView {
        id: resultFile
        path: probe.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: true
    }

    function buildCases() {
        var png = probe.samplePng
        var fileUrl = "file://" + png
        return [
            { id: "absolute", result: AppIconResolver.resolve({ appIcon: png }) },
            { id: "fileUrl", result: AppIconResolver.resolve({ appIcon: fileUrl }) },
            { id: "appIconName", result: AppIconResolver.resolve({ appIcon: "foot" }) },
            { id: "themedImage", result: AppIconResolver.resolve({ image: "image://icon/foot" }) },
            { id: "desktopFoot", result: AppIconResolver.resolve({ desktopEntry: "foot" }) },
            { id: "desktopGhostty", result: AppIconResolver.resolve({ desktopEntry: "com.mitchellh.ghostty" }) },
            { id: "desktopChromium", result: AppIconResolver.resolve({ desktopEntry: "chromium-browser" }) },
            { id: "desktopChatgpt", result: AppIconResolver.resolve({ desktopEntry: "chatgpt" }) },
            { id: "windowFoot", result: AppIconResolver.resolve({ origin: { className: "foot" } }) },
            { id: "windowGhostty", result: AppIconResolver.resolve({ origin: { className: "com.mitchellh.ghostty" } }) },
            { id: "inline", result: AppIconResolver.resolve({ imageData: png }) },
            { id: "unresolvable", result: AppIconResolver.resolve({ appIcon: "definitely-not-a-real-icon-xyz" }) },
            {
                id: "durable",
                result: AppIconResolver.resolve({ localPath: fileUrl, imageData: png, appIcon: "foot" })
            },
            { id: "dangling", result: AppIconResolver.resolve({ localPath: "file://" + probe.missingPng }) },
            { id: "symbolic", result: AppIconResolver.resolve({ appIcon: "probefixture-symbolic" }) }
        ]
    }

    Repeater {
        id: probeRepeater
        model: probe.cases
        Image {
            width: 16
            height: 16
            asynchronous: false
            source: modelData.result.source
        }
    }

    function writeResult() {
        if (probe.finished || probe.resultPath === "") return
        probe.finished = true
        var out = { readyStatus: Image.Ready, errorStatus: Image.Error, cases: {} }
        for (var i = 0; i < probeRepeater.count; i++) {
            var item = probeRepeater.itemAt(i)
            var entry = probe.cases[i]
            out.cases[entry.id] = {
                status: item ? item.status : -1,
                kind: entry.result.kind,
                name: entry.result.name,
                symbolic: entry.result.symbolic,
                origin: entry.result.origin,
                source: entry.result.source
            }
        }
        resultFile.setText(JSON.stringify(out) + "\n")
    }

    // The direct .desktop/AppStream index is asynchronous. Build the cases as
    // soon as it is ready (with a bounded fallback) so the desktop-entry-only
    // cases exercise the direct metadata lookup rather than racing an empty
    // index.
    property bool casesBuilt: false
    property int indexWaits: 0

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            probe.indexWaits = probe.indexWaits + 1
            if (probe.casesBuilt) return
            if (AppIconResolver.metadataIndexRevision > 0 || probe.indexWaits >= 60) {
                probe.casesBuilt = true
                probe.cases = buildCases()
                settleTimer.running = true
                running = false
            }
        }
    }

    Timer {
        id: settleTimer
        interval: 1200
        running: false
        repeat: false
        onTriggered: probe.writeResult()
    }

    Connections {
        target: resultFile
        function onSaved() { Qt.quit() }
        function onSaveFailed() { Qt.quit() }
    }
}
