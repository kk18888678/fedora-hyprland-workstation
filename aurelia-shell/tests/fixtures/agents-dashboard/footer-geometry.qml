import QtQuick
import Quickshell
import Quickshell.Io

// Offscreen measurement fixture for the pinned footer pager. It drives the
// real dashboard through every idle hint kind (text, legend, keys) and the
// stale hint, and records the pager's right edge (`x + width`, mapped into the
// dashboard), the hint kind and the hint text. The test asserts the right edge
// never moves.
Window {
    id: root

    readonly property string resultPath: Quickshell.env("AGENTS_DASHBOARD_RESULT") || ""
    readonly property string fixturePath: {
        var override = Quickshell.env("AGENTS_DASHBOARD_FIXTURE") || ""
        if (override !== "") return override
        return String(Qt.resolvedUrl("records.json")).replace(/^file:\/\//, "")
    }
    readonly property var dashboard: dashboardLoader.item
    readonly property string pluginPath: {
        var override = Quickshell.env("AGENTS_DASHBOARD_PLUGIN") || ""
        if (override !== "") return override
        return String(Qt.resolvedUrl("../../../plugins/aurelia.agents/AgentsDashboard.qml"))
            .replace(/^file:\/\//, "")
    }

    property var records: []
    property var samples: []
    property var legendCentres: ({})
    property int step: 0
    property bool written: false

    visible: true
    width: 580
    height: 640
    color: dashboard ? dashboard.surfaceBackdrop : "#191724"

    QtObject {
        id: mockWidget
        property var visibleAgents: root.records
        property bool loaded: true
        property string lastError: ""
        property bool refreshing: false
        property int staleMs: 1800000
        property string percentMode: "remaining"
        property var bar: null
        function refresh(force) {}
        function maybeRefresh(age) {}
    }

    Loader {
        id: dashboardLoader
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: 560
        height: 620
        source: root.pluginPath
        onLoaded: {
            item.agentsWidget = mockWidget
            item.nowMs = 1789819200000
            item.maxHeight = 620
        }
    }

    FileView {
        id: fixtureFile
        path: root.fixturePath
        blockLoading: true
        watchChanges: false
        printErrors: true
        onLoaded: {
            try {
                var parsed = JSON.parse(fixtureFile.text())
                root.records = (parsed && parsed.agents) ? parsed.agents : []
                settleTimer.restart()
            } catch (e) {
                console.error("[AGENTS-FOOTER] fixture_parse_failed " + e)
            }
        }
        onLoadFailed: console.error("[AGENTS-FOOTER] fixture_load_failed " + root.fixturePath)
    }

    function findByObjectName(name) {
        var found = null
        function walk(node) {
            if (found !== null) return
            var kids = node.children || []
            for (var i = 0; i < kids.length; i++) {
                var child = kids[i]
                if (String(child.objectName) === name) { found = child; return }
                walk(child)
                if (found !== null) return
            }
        }
        if (root.dashboard) walk(root.dashboard)
        return found
    }

    function centreY(item) {
        if (!item || !root.dashboard) return null
        var point = item.mapToItem(root.dashboard, 0, 0)
        return Math.round((point.y + item.height / 2) * 100) / 100
    }

    function captureLegendCentres() {
        root.legendCentres = {
            evenMeter: centreY(root.findByObjectName("agentsFooterLegendEvenMeter")),
            evenLabel: centreY(root.findByObjectName("agentsFooterLegendEvenLabel")),
            fastMeter: centreY(root.findByObjectName("agentsFooterLegendFastMeter")),
            fastLabel: centreY(root.findByObjectName("agentsFooterLegendFastLabel"))
        }
    }

    function captureSample(label) {
        var d = root.dashboard
        var pager = root.findByObjectName("agentsFooterPager")
        var hint = root.findByObjectName("agentsFooterHint")
        var point = pager ? pager.mapToItem(d, 0, 0) : null
        root.samples.push({
            label: label,
            rotationIndex: d ? d.rotationIndex : -1,
            kind: d && d.footerHint ? String(d.footerHint.kind) : null,
            priority: d && d.footerHint ? d.footerHint.priority : -1,
            hintText: hint ? String(hint.text) : "",
            pagerVisible: pager ? pager.visible === true : null,
            pagerX: point ? Math.round(point.x * 100) / 100 : null,
            pagerWidth: pager ? pager.width : null,
            pagerRight: point && pager
                ? Math.round((point.x + pager.width) * 100) / 100 : null
        })
    }

    Timer {
        id: settleTimer
        interval: 600
        repeat: false
        onTriggered: {
            captureSample("text")
            stepTimer.restart()
        }
    }

    Timer {
        id: stepTimer
        interval: 250
        repeat: true
        onTriggered: {
            var d = root.dashboard
            if (!d) return
            if (root.step === 0) {
                d.rotationIndex = 1
                root.step = 1
            } else if (root.step === 1) {
                captureSample("legend")
                captureLegendCentres()
                d.rotationIndex = 2
                root.step = 2
            } else if (root.step === 2) {
                captureSample("keys")
                // Force the stale hint (priority 1) by ageing the data.
                d.nowMs = 1789819200000 + 7200000
                root.step = 3
            } else if (root.step === 3) {
                captureSample("stale")
                // Force a selected account so the Close control is present.
                d.selectedAccountId = "codex"
                root.step = 4
            } else if (root.step === 4) {
                captureSample("selected")
                stepTimer.stop()
                writeTimer.restart()
            }
        }
    }

    Timer {
        id: writeTimer
        interval: 150
        repeat: false
        onTriggered: root.writeResult()
    }

    function writeResult() {
        if (root.written || root.resultPath === "") return
        root.written = true
        resultFile.setText(JSON.stringify({ samples: root.samples,
            legendCentres: root.legendCentres }) + "\n")
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
        interval: 12000
        running: true
        repeat: false
        onTriggered: {
            root.writeResult()
            Qt.quit()
        }
    }
}
