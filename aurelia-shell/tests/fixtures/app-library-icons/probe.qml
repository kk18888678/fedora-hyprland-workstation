import QtQuick
import Quickshell
import Quickshell.Io

// Isolated probe body for the AureliaAppLibrary icon bridge. It loads the real
// library through a file:// source and drives its public iconSource() with
// deterministic values. A matching Image per case asserts the resolved source
// actually renders (Image.Ready), so a migration that stops resolving a real
// icon is caught instead of only a string-shape change. No live shell,
// compositor, or user configuration is touched.
Item {
    id: probe

    readonly property string librarySource: Quickshell.env("AURELIA_APP_LIBRARY_ICON_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_APP_LIBRARY_ICON_RESULT") || ""
    readonly property string samplePng: Quickshell.env("AURELIA_APP_LIBRARY_ICON_PNG") || ""

    // Touching the applications model starts the asynchronous desktop-entry
    // scan so the bridge is exercised against a populated environment.
    readonly property int desktopEntryCount: DesktopEntries.applications.values.length

    property var library: null
    property var cases: []
    property bool finished: false

    Loader {
        id: libraryLoader
        source: probe.librarySource
        onLoaded: probe.library = item
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

    function buildCases() {
        var lib = probe.library
        return [
            { id: "empty", source: lib.iconSource("") },
            { id: "knownName", source: lib.iconSource("fixture-app") },
            { id: "knownSymbolic", source: lib.iconSource("fixture-app-symbolic") },
            { id: "themedImage", source: lib.iconSource("image://icon/fixture-app") },
            { id: "fileUrl", source: lib.iconSource("file:" + "//" + probe.samplePng) },
            { id: "absolute", source: lib.iconSource(probe.samplePng) },
            { id: "unknown", source: lib.iconSource("definitely-not-real-xyz") }
        ]
    }

    function writeResult() {
        if (probe.finished || probe.resultPath === "") return
        probe.finished = true
        var out = { readyStatus: Image.Ready, caseCount: iconRepeater.count, cases: {} }
        for (var i = 0; i < iconRepeater.count; i++) {
            var item = iconRepeater.itemAt(i)
            out.cases[probe.cases[i].id] = {
                status: item ? item.status : -1,
                source: probe.cases[i].source
            }
        }
        resultFile.setText(JSON.stringify(out) + "\n")
    }

    // Wait for the library and the asynchronous desktop-entry model before
    // resolving, with a bounded fallback so a broken scan still reports.
    Timer {
        id: readinessTimer
        interval: 100
        running: true
        repeat: true
        property int attempts: 0
        onTriggered: {
            attempts = attempts + 1
            if (probe.library !== null && (probe.desktopEntryCount > 0 || attempts >= 60)) {
                running = false
                probe.cases = probe.buildCases()
                settleTimer.running = true
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
