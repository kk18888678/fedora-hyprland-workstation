import QtQuick
import Quickshell
import Quickshell.Io

// Measured states + design-owner renders for the in-scene panel tooltip.
//
// For every cell-tooltip state in spec 6.3 (blocking, meaningfully fast, on
// track, non-binding, not offered, not reported, column header) this fixture
// points the one shared in-scene tooltip at a real matrix cell and measures:
//   * the rendered tooltip width against the widest line + the host padding
//     (proving the width is content-driven, never trigger- or space-derived);
//   * every visible line's `lineCount` (must be 1) and `truncated` (must be
//     false, because NoWrap turns an over-cap line into `...` only past 360);
//   * the trigger width (the tooltip must be wider than the ~98 px cell).
// The cases cover five_hour, week AND the rightmost month column, so the
// near-edge clamp is exercised.
//
// When AGENTS_DASHBOARD_IMAGE is set, the fixture also writes one PNG per case
// beside it (`<stem>-<case>.png`) so the design owner can review the real
// pixels. Inline tooltips cannot render live, so this is the only way to show
// them over a real panel row.
Window {
    id: root

    readonly property string resultPath: Quickshell.env("AGENTS_DASHBOARD_RESULT") || ""
    readonly property string imagePath: Quickshell.env("AGENTS_DASHBOARD_IMAGE") || ""
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
    property var cases: []
    property var measurements: []
    property int caseIndex: 0
    property bool finished: false

    readonly property var now: 1789819200000

    visible: true
    width: 580
    height: card.height + 24
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

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 12
        width: 580
        height: (dashboard ? dashboard.implicitHeight : 0) +
            (dashboard ? dashboard.surfacePadding * 2 : 0)
        radius: dashboard ? dashboard.surfaceRadius : 12
        color: dashboard ? dashboard.surfaceBackground : "#1f1d2e"
        border.color: dashboard ? dashboard.surfaceBorder : "#524f67"
        border.width: 1

        Loader {
            id: dashboardLoader
            anchors.fill: parent
            anchors.margins: dashboard ? dashboard.surfacePadding : 10
            source: root.pluginPath
            onLoaded: {
                item.agentsWidget = mockWidget
                item.nowMs = root.now
                item.maxHeight = 620
            }
            onStatusChanged: {
                if (status === Loader.Error) console.error("[AGENTS-TOOLTIP-STATES] load_failed")
            }
        }
    }

    // The seven spec 6.3 states (the same strings AgentUsage.cellTooltipLines
    // produces for each cell shape) plus explicit coverage of every column.
    // The strings are mirrored here rather than imported because Quickshell
    // rejects a relative JS import that climbs out of the fixture directory.
    function buildCases() {
        return [
            { name: "blocking", column: "week", lines: [
                { text: "Cline · Weekly", tone: "default", strong: true },
                { text: "95% used · resets today 15:30", tone: "default", strong: false },
                { text: "Blocking Cline until then", tone: "error", strong: false } ] },
            { name: "meaningfully-fast", column: "five_hour", lines: [
                { text: "Cline · 5-hour", tone: "default", strong: true },
                { text: "11% used · resets today 15:30", tone: "default", strong: false },
                { text: "Runs out in ~2h 50m at this rate", tone: "warning", strong: false } ] },
            { name: "on-track", column: "week", lines: [
                { text: "Cline · Weekly", tone: "default", strong: true },
                { text: "10% used · resets today 15:30", tone: "default", strong: false } ] },
            { name: "on-track-five-hour", column: "five_hour", lines: [
                { text: "Cline · 5-hour", tone: "default", strong: true },
                { text: "10% used · resets today 15:30", tone: "default", strong: false } ] },
            { name: "on-track-month-rightmost", column: "month", lines: [
                { text: "Cline · Monthly", tone: "default", strong: true },
                { text: "10% used · resets in 20 days", tone: "default", strong: false } ] },
            { name: "non-binding", column: "five_hour", lines: [
                { text: "Cline · 5-hour", tone: "default", strong: true },
                { text: "10% used · resets today 15:30", tone: "default", strong: false },
                { text: "Not the limit blocking Cline", tone: "default", strong: false } ] },
            { name: "not-offered", column: "month", lines: [
                { text: "Codex has no monthly limit", tone: "default", strong: true } ] },
            { name: "not-reported", column: "week", lines: [
                { text: "Codex didn't report its weekly limit", tone: "default", strong: true } ] },
            { name: "column-header-month-rightmost", column: "month", lines: [
                { text: "Usage limit over a rolling 30-day window", tone: "default", strong: false } ] }
        ]
    }

    function findByObjectName(name) {
        var found = null
        function walk(node) {
            if (found !== null) return
            if (node && String(node.objectName) === name) { found = node; return }
            var kids = node ? (node.children || []) : []
            for (var i = 0; i < kids.length; i++) {
                walk(kids[i])
                if (found !== null) return
            }
        }
        walk(root.dashboard)
        return found
    }

    function collectByName(prefix, node, out) {
        var kids = node ? (node.children || []) : []
        for (var i = 0; i < kids.length; i++) {
            var child = kids[i]
            if (child.objectName && String(child.objectName).indexOf(prefix) === 0) out.push(child)
            root.collectByName(prefix, child, out)
        }
        return out
    }

    function lineNaturalWidth(body) {
        var row = body.parent
        var sum = 0
        var kids = row ? (row.children || []) : []
        for (var i = 0; i < kids.length; i++) {
            var k = kids[i]
            if (k && typeof k.text === "string" && k.font !== undefined && k.visible !== false) {
                sum += (k === body) ? k.contentWidth : k.width
            }
        }
        return sum
    }

    function captureCase(tooltip) {
        var bodies = root.collectByName("tooltipLineBody", tooltip, [])
        var measureLines = root.collectByName("tooltipMeasureLine", tooltip, [])
        var record = {
            name: root.cases[root.caseIndex].name,
            column: root.cases[root.caseIndex].column,
            tooltipWidth: tooltip.width,
            tooltipHeight: tooltip.height,
            horizontalPadding: tooltip.horizontalPadding,
            triggerWidth: tooltip.triggerItem ? tooltip.triggerItem.width : -1,
            lines: []
        }
        var widest = 0
        for (var m = 0; m < measureLines.length; m++) {
            if (measureLines[m].implicitWidth > widest) widest = measureLines[m].implicitWidth
        }
        for (var i = 0; i < bodies.length; i++) {
            var body = bodies[i]
            var natural = root.lineNaturalWidth(body)
            record.lines.push({
                text: String(body.text),
                contentWidth: body.contentWidth,
                implicitWidth: body.implicitWidth,
                paintedWidth: body.paintedWidth,
                laidOutWidth: body.width,
                lineCount: body.lineCount,
                truncated: body.truncated === true,
                alignment: body.horizontalAlignment,
                weight: body.font.weight,
                naturalWidth: natural
            })
        }
        record.contentWidth = tooltip.width - tooltip.horizontalPadding * 2
        record.expectedContentWidth = widest
        record.expectedWidth = widest + tooltip.horizontalPadding * 2
        record.measureLineCount = measureLines.length
        record.triggerIsCell = tooltip.triggerItem
            ? String(tooltip.triggerItem.objectName).indexOf("matrixCell-") === 0 : false
        return record
    }

    FileView {
        id: recordsFile
        path: root.fixturePath
        blockLoading: true
        watchChanges: false
        printErrors: true
        onLoaded: {
            try {
                var parsed = JSON.parse(recordsFile.text())
                root.records = (parsed && parsed.agents) ? parsed.agents : []
                root.cases = root.buildCases()
                applyTimer.restart()
            } catch (e) {
                console.error("[AGENTS-TOOLTIP-STATES] parse_failed " + e)
            }
        }
        onLoadFailed: console.error("[AGENTS-TOOLTIP-STATES] load_failed " + root.fixturePath)
    }

    function applyCase() {
        var tooltip = root.findByObjectName("panelToolTip")
        if (!tooltip) return false
        var c = root.cases[root.caseIndex]
        var cell = root.findByObjectName("matrixCell-0-" + c.column)
        if (!cell) return false
        tooltip.hovered = false
        tooltip.revealed = false
        tooltip.triggerItem = cell
        tooltip.lines = c.lines
        tooltip.hovered = true
        return true
    }

    Timer {
        id: applyTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (root.caseIndex >= root.cases.length) {
                root.finish()
                return
            }
            if (!root.applyCase()) {
                root.finish()
                return
            }
            revealTimer.restart()
        }
    }

    Timer {
        id: revealTimer
        interval: 650
        repeat: false
        onTriggered: {
            var tooltip = root.findByObjectName("panelToolTip")
            if (!tooltip) { root.finish(); return }
            var record = root.captureCase(tooltip)
            root.measurements.push(record)
            if (root.imagePath !== "") {
                var target = root.imageStem() + "-" + record.name + ".png"
                card.grabToImage(function (result) {
                    if (result) result.saveToFile(target)
                    root.advance()
                })
            } else {
                root.advance()
            }
        }
    }

    function imageStem() {
        return root.imagePath.replace(/\.png$/, "")
    }

    function advance() {
        root.caseIndex += 1
        applyTimer.restart()
    }

    function finish() {
        if (root.finished) return
        root.finished = true
        writeTimer.restart()
    }

    Timer {
        id: writeTimer
        interval: 150
        repeat: false
        onTriggered: root.writeResult()
    }

    function writeResult() {
        if (root.resultPath === "") { Qt.quit(); return }
        resultFile.setText(JSON.stringify({
            measurements: root.measurements,
            count: root.measurements.length
        }) + "\n")
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
        interval: 30000
        running: true
        repeat: false
        onTriggered: {
            root.finish()
        }
    }
}
