import QtQuick
import Quickshell
import Quickshell.Io
import "../../../services"

// Isolated probe body for the WindowPreview fallback icon. It loads the real
// preview through an absolute file:// source, pins deterministic fake
// toplevels, and never activates capture, so no live compositor or capture
// stream is touched. The fixture asserts the resolved source and the
// symbolic-versus-logo render decision the preview drew from the shared
// AppIconResolver owner, and separately proves each source renders
// (Image.Ready).
Item {
    id: probe

    readonly property string previewSource: Quickshell.env("AURELIA_WINDOW_PREVIEW_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_WINDOW_PREVIEW_RESULT") || ""

    property var cases: []
    property bool finished: false

    QtObject {
        id: fixtureHandle
        property string appId: "fixture-app"
    }

    QtObject {
        id: fixtureToplevel
        property var handle: fixtureHandle
        property var wayland: null
        property string title: "Fixture App"
    }

    QtObject {
        id: symbolicHandle
        property string appId: "fixture-symbolic"
    }

    QtObject {
        id: symbolicToplevel
        property var handle: symbolicHandle
        property var wayland: null
        property string title: "Symbolic App"
    }

    QtObject {
        id: unknownHandle
        property string appId: "definitely-not-real-xyz"
    }

    QtObject {
        id: unknownToplevel
        property var handle: unknownHandle
        property var wayland: null
        property string title: "Unknown"
    }

    Loader {
        id: fixtureLoader
        source: probe.previewSource
        onLoaded: {
            item.hyprlandToplevel = fixtureToplevel
            item.active = false
        }
    }

    Loader {
        id: symbolicLoader
        source: probe.previewSource
        onLoaded: {
            item.hyprlandToplevel = symbolicToplevel
            item.active = false
        }
    }

    Loader {
        id: unknownLoader
        source: probe.previewSource
        onLoaded: {
            item.hyprlandToplevel = unknownToplevel
            item.active = false
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

    function snapshot(item) {
        var resolution = item ? item.iconResolution : null
        var value = resolution || {}
        return {
            kind: String(value.kind || ""),
            name: String(value.name || ""),
            symbolic: value.symbolic === true,
            source: item ? String(item.iconSource || "") : "",
            preservesColors: item ? item.iconPreservesColors === true : false
        }
    }

    function buildCases() {
        return [
            { id: "fixtureApp", source: fixtureLoader.item.iconSource },
            { id: "symbolic", source: symbolicLoader.item.iconSource },
            { id: "unknown", source: unknownLoader.item.iconSource }
        ]
    }

    function writeResult() {
        if (probe.finished || probe.resultPath === "") return
        probe.finished = true
        var out = {
            readyStatus: Image.Ready,
            fixtureApp: probe.snapshot(fixtureLoader.item),
            symbolic: probe.snapshot(symbolicLoader.item),
            unknown: probe.snapshot(unknownLoader.item),
            rendered: {}
        }
        for (var i = 0; i < iconRepeater.count; i++) {
            var item = iconRepeater.itemAt(i)
            out.rendered[probe.cases[i].id] = item ? item.status : -1
        }
        resultFile.setText(JSON.stringify(out) + "\n")
    }

    // Wait for the preview instances, the asynchronous desktop-entry scan and
    // the resolver's direct metadata index before snapshotting, with a bounded
    // fallback so a broken build still reports instead of hanging.
    Timer {
        id: readinessTimer
        interval: 100
        running: true
        repeat: true
        property int attempts: 0
        onTriggered: {
            attempts = attempts + 1
            if (fixtureLoader.item !== null && symbolicLoader.item !== null && unknownLoader.item !== null &&
                    DesktopEntries.heuristicLookup("fixture-app") !== null &&
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
