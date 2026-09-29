import QtQuick
import Quickshell
import Quickshell.Io
import "../../../services"

// Isolated probe body for the Tasklist bar widget's icon resolution. It loads
// the real widget through an absolute file:// source and pins a deterministic
// toplevel list through the documented toplevelsOverride seam, so no live
// Hyprland socket or bar layout is touched. The fixture asserts the resolved
// source and the symbolic-versus-logo render decision the widget drew from the
// shared AppIconResolver owner, and separately proves each resolved source
// renders (Image.Ready).
Item {
    id: probe

    readonly property string widgetSource: Quickshell.env("AURELIA_TASKLIST_ICON_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_TASKLIST_ICON_RESULT") || ""

    property var widget: null
    property var cases: []
    property bool finished: false

    QtObject {
        id: fixtureAppHandle
        property string appId: "fixture-app"
    }

    QtObject {
        id: symbolicHandle
        property string appId: "fixture-symbolic"
    }

    QtObject {
        id: footHandle
        property string appId: "foot"
    }

    QtObject {
        id: unknownHandle
        property string appId: "definitely-not-real-xyz"
    }

    QtObject {
        id: fixtureAppToplevel
        property var handle: fixtureAppHandle
        property bool activated: true
        property string title: "Fixture App"
    }

    QtObject {
        id: symbolicToplevel
        property var handle: symbolicHandle
        property bool activated: false
        property string title: "Symbolic App"
    }

    QtObject {
        id: footToplevel
        property var handle: footHandle
        property bool activated: false
        property string title: "Foot"
    }

    QtObject {
        id: unknownToplevel
        property var handle: unknownHandle
        property bool activated: false
        property string title: "Unknown"
    }

    QtObject {
        id: fakeBar
        property bool vertical: false
        property int barSize: 26
        property int barIconCanvas: 16
        property int barIconSlot: 27
        property color barForeground: "#ffffff"
    }

    Loader {
        id: widgetLoader
        source: probe.widgetSource
        onLoaded: {
            item.bar = fakeBar
            item.toplevelsOverride = [fixtureAppToplevel, symbolicToplevel, footToplevel, unknownToplevel]
            probe.widget = item
        }
    }

    Repeater {
        id: iconRepeater
        model: probe.cases
        Image {
            width: 16
            height: 16
            asynchronous: false
            source: modelData.source
        }
    }

    FileView {
        id: resultFile
        path: probe.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: true
    }

    function snapshotResolution(index) {
        var resolution = probe.widget.iconResolutionAt(index)
        var value = resolution || {}
        return {
            kind: String(value.kind || ""),
            name: String(value.name || ""),
            symbolic: value.symbolic === true,
            source: String(value.source || ""),
            preservesColors: probe.widget.iconPreservesColorsAt(index) === true,
            iconReady: probe.widget.iconReadyAt(index) === true
        }
    }

    function buildCases() {
        return [
            { id: "fixtureApp", source: probe.widget.iconSourceAt(0) },
            { id: "symbolic", source: probe.widget.iconSourceAt(1) },
            { id: "foot", source: probe.widget.iconSourceAt(2) },
            { id: "unknown", source: probe.widget.iconSourceAt(3) }
        ]
    }

    function writeResult() {
        if (probe.finished || probe.resultPath === "") return
        probe.finished = true
        var out = {
            readyStatus: Image.Ready,
            fixtureApp: probe.snapshotResolution(0),
            symbolic: probe.snapshotResolution(1),
            foot: probe.snapshotResolution(2),
            unknown: probe.snapshotResolution(3),
            rendered: {}
        }
        for (var i = 0; i < iconRepeater.count; i++) {
            var item = iconRepeater.itemAt(i)
            out.rendered[probe.cases[i].id] = item ? item.status : -1
        }
        resultFile.setText(JSON.stringify(out) + "\n")
    }

    // Wait for the widget, the asynchronous desktop-entry scan and the
    // resolver's direct metadata index before snapshotting, with a bounded
    // fallback so a broken build still reports instead of hanging.
    Timer {
        id: readinessTimer
        interval: 100
        running: true
        repeat: true
        property int attempts: 0
        onTriggered: {
            attempts = attempts + 1
            if (probe.widget !== null &&
                    DesktopEntries.heuristicLookup("fixture-app") !== null &&
                    DesktopEntries.heuristicLookup("fixture-symbolic") !== null &&
                    (AppIconResolver.metadataIndexRevision > 0 || attempts >= 60)) {
                running = false
                probe.cases = probe.buildCases()
                settleTimer.running = true
            }
        }
    }

    Timer {
        id: settleTimer
        interval: 900
        running: false
        repeat: false
        onTriggered: probe.writeResult()
    }

    Connections {
        target: resultFile
        function onSaved() { Qt.quit() }
        function onSaveFailed() { Qt.quit() }
    }

    Timer {
        interval: 7000
        running: true
        repeat: false
        onTriggered: { if (!probe.finished) probe.writeResult() }
    }
}
