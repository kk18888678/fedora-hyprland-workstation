import QtQuick
import Quickshell
import Quickshell.Io

// T44 fixture. This loads the real PowerPanel entry point with deterministic
// battery overrides but does not open it or execute a power command.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_POWER_PANEL_RESULT") || ""
    readonly property string panelSource: Quickshell.env("AURELIA_POWER_PANEL_SOURCE") || ""
    readonly property string runtimeSource: Quickshell.env("AURELIA_POWER_RUNTIME_SOURCE") || ""
    property bool finished: false
    property bool runtimeLoaded: false
    property bool panelLoaded: false
    property bool panelFailed: false

    QtObject {
        id: fakeBattery
        property bool isPresent: true
        property real percentage: 0.8
        property int state: 1
        property real changeRate: 2
        property int timeToFull: 1200
    }

    QtObject {
        id: fakeBar
        property int widgetRevision: 1
        property int barSize: 26
        property string position: "top"
        function anchorItemFor(id) { return null }
    }

    QtObject {
        id: fakeShell
        function updateEntryInline(id, settings, selector) { return "ok" }
    }

    QtObject {
        id: runtimeOwner
        property bool batteryPresent: false
        property bool shown: false
        property bool actionRunning: false
        property string actionError: ""
        property string profileError: ""
        property int phraseIndex: 0
        property var activePhrases: []
        property var actionExecutor
        function refresh() {}
        function updateProfiles(raw) {}
        function updateSystemStats(raw) {}
    }

    Loader {
        id: runtimeLoader
        source: root.runtimeSource
        onLoaded: {
            if (!item) return
            item.owner = runtimeOwner
            root.runtimeLoaded = true
            root.maybeWriteResult()
        }
        onStatusChanged: {
            if (status === Loader.Error) root.maybeWriteResult()
        }
    }

    Loader {
        id: panelLoader
        source: root.panelSource
        onLoaded: {
            if (!item) return
            root.panelLoaded = true
            item.bar = fakeBar
            item.shell = fakeShell
            item.displayDeviceOverride = fakeBattery
            item.onBatteryOverride = false
            item.statesOverride = ({Charging: 1, Discharging: 2, FullyCharged: 3, PendingCharge: 4})
            root.maybeWriteResult()
        }
        onStatusChanged: {
            if (status === Loader.Error) {
                root.panelFailed = true
                root.maybeWriteResult()
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

    function writeResult(value) {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        resultFile.setText(JSON.stringify(value) + "\n")
    }

    function maybeWriteResult() {
        if (root.finished || !root.runtimeLoaded ||
            !(root.panelLoaded || root.panelFailed)) return
        root.writeResult({
            loaded: root.panelLoaded,
            runtimeLoaded: root.runtimeLoaded,
            runtimeAvailable: runtimeLoader.item !== null,
            entryPointConstructed: root.panelLoaded
        })
    }

    Timer {
        interval: 1200
        running: true
        repeat: false
        onTriggered: if (!root.finished) root.writeResult({
            loaded: root.panelLoaded,
            runtimeLoaded: root.runtimeLoaded,
            runtimeAvailable: runtimeLoader.item !== null,
            entryPointConstructed: false
        })
    }
}
