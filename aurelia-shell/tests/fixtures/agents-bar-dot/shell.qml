import QtQuick
import Quickshell
import Quickshell.Io

// Offscreen probe for the agents bar badge dot placement.
//
// It loads the real AgentsBarWidget with a mock bar and a fixed critical
// record so the dot is present, then reports the glyph's ink box, the dot's
// centre in the glyph's coordinate system and the dot's size. The test asserts
// the documented ink-box fractions and the ink-box aspect guard; the visual
// "looks tangent" check remains a human one.
Window {
    id: root

    readonly property string widgetSource: Quickshell.env("AGENTS_WIDGET_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AGENTS_BAR_DOT_RESULT") || ""
    readonly property var dashboardItem: widgetLoader.item

    property bool written: false

    visible: true
    width: 80
    height: 40
    color: "#000000"

    QtObject {
        id: mockBar
        property bool barVisible: true
        property bool vertical: false
        property bool transparent: false
        property int barSize: 26
        property int barIconCanvas: 16
        property int barIconFont: 13
        property int barTextSize: 13
        property color barForeground: "#ffffff"
    }

    // A binding window that is critical right now, so root.stateDot is true.
    property var criticalRecord: ({
        id: "probe",
        name: "Probe",
        ready: true,
        detected: true,
        updatedAt: new Date(1789819200000).toISOString(),
        limits: [{
            label: "Weekly",
            percent: 0.95,
            windowMinutes: 10080,
            resetsAt: new Date(1789819200000 + 3 * 86400000).toISOString()
        }]
    })

    Loader {
        id: widgetLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = mockBar
            item.nowMs = 1789819200000
            item.agents = [ root.criticalRecord ]
            item.loaded = true
            captureTimer.restart()
        }
    }

    function findByObjectName(node, name) {
        if (!node) return null
        var kids = node.children || []
        for (var i = 0; i < kids.length; i++) {
            if (String(kids[i].objectName) === name) return kids[i]
            var found = root.findByObjectName(kids[i], name)
            if (found) return found
        }
        return null
    }

    function writeResult() {
        if (root.written || root.resultPath === "") return
        root.written = true
        var widget = widgetLoader.item
        var glyph = root.findByObjectName(widget, "agentGlyph")
        var dot = root.findByObjectName(widget, "stateDot")
        var payload = { "glyphFound": glyph !== null, "dotFound": dot !== null }
        if (glyph && dot) {
            var ink = glyph.glyphInkRect
            var centre = dot.mapToItem(glyph, dot.width / 2, dot.height / 2)
            payload.ink = { x: ink.x, y: ink.y, width: ink.width, height: ink.height }
            payload.dotCentreInGlyph = { x: centre.x, y: centre.y }
            payload.dotSize = { width: dot.width, height: dot.height }
            payload.dotVisible = dot.visible === true
        }
        resultFile.setText(JSON.stringify(payload) + "\n")
    }

    Timer {
        id: captureTimer
        interval: 700
        repeat: false
        onTriggered: root.writeResult()
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

    Timer {
        interval: 9000
        running: true
        repeat: false
        onTriggered: {
            root.writeResult()
            Qt.quit()
        }
    }
}
