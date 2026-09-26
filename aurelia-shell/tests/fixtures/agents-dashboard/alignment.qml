import QtQuick
import Quickshell
import Quickshell.Io

// Offscreen alignment probe for the consolidated AI Usage dashboard matrix.
//
// It loads the exact panel body (AgentsDashboard.qml) with the shared fixture
// data, walks the live item tree, and reports the measured geometry of the
// account column, the window header labels, the per-row window cells, the
// percentage labels and the meters, plus every row height. The test asserts
// the four grid properties from those measurements rather than grepping for
// Layout properties.
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
    readonly property string selectId: Quickshell.env("AGENTS_DASHBOARD_SELECT") || ""
    // Percentage presentation to measure; the same dashboard body renders both
    // modes so a test can prove the number and the meter fill agree.
    readonly property string percentMode: Quickshell.env("AGENTS_DASHBOARD_PERCENT_MODE") || "remaining"
    // Default panel width; the test also measures a deliberately narrow width.
    readonly property int windowWidth: {
        var raw = parseInt(Quickshell.env("AGENTS_DASHBOARD_WIDTH") || "480")
        return isFinite(raw) && raw > 240 ? raw : 480
    }

    property var records: []
    property bool measured: false

    visible: true
    width: root.windowWidth
    height: card.height + 24
    color: dashboard ? dashboard.surfaceBackdrop : "#191724"

    QtObject {
        id: mockWidget
        property var visibleAgents: root.records
        property bool loaded: true
        property string lastError: ""
        property bool refreshing: false
        property int staleMs: 1800000
        property string percentMode: root.percentMode
        property var bar: null
        function refresh(force) {}
        function maybeRefresh(age) {}
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 12
        width: root.windowWidth - 20
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
                item.nowMs = 1789819200000
                item.maxHeight = 620
            }
            onStatusChanged: {
                if (status === Loader.Error) console.error("[AGENTS-ALIGN] dashboard_load_failed")
            }
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
                selectTimer.restart()
            } catch (e) {
                console.error("[AGENTS-ALIGN] fixture_parse_failed " + e)
            }
        }
        onLoadFailed: console.error("[AGENTS-ALIGN] fixture_load_failed " + root.fixturePath)
    }

    Timer {
        id: selectTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (root.dashboard && root.selectId !== "")
                root.dashboard.selectedAccountId = root.selectId
            measureTimer.restart()
        }
    }

    Timer {
        id: measureTimer
        interval: 900
        repeat: false
        onTriggered: root.capture()
    }

    function collect(prefix) {
        var out = []
        function walk(node) {
            var kids = node.children || []
            for (var i = 0; i < kids.length; i++) {
                var child = kids[i]
                if (child.objectName && String(child.objectName).indexOf(prefix) === 0)
                    out.push(child)
                walk(child)
            }
        }
        if (root.dashboard) walk(root.dashboard)
        return out
    }

    function geometry(item) {
        var point = item.mapToItem(root.dashboard, 0, 0)
        return {
            x: Math.round(point.x * 100) / 100,
            y: Math.round(point.y * 100) / 100,
            width: Math.round(item.width * 100) / 100,
            height: Math.round(item.height * 100) / 100
        }
    }

    // Depth-first search for the named descendant; used to measure the meter
    // fill rectangle that the Meter component declares as `meterFill`.
    function findDescendant(node, name) {
        var kids = node.children || []
        for (var i = 0; i < kids.length; i++) {
            if (String(kids[i].objectName) === name) return kids[i]
            var found = root.findDescendant(kids[i], name)
            if (found) return found
        }
        return null
    }

    function capture() {
        var d = root.dashboard
        if (!d) return
        var accountHeader = null
        var headers = {}
        var accountCells = []
        var cells = []
        var percentages = []
        var meters = []
        var meterFills = []
        var rows = []

        root.collect("matrixAccountHeader").forEach(function (item) {
            accountHeader = root.geometry(item)
        })
        root.collect("matrixAccountCell-").forEach(function (item) {
            accountCells.push(root.geometry(item))
        })
        root.collect("matrixHeader-").forEach(function (item) {
            headers[String(item.objectName).slice("matrixHeader-".length)] = root.geometry(item)
        })
        root.collect("matrixCell-").forEach(function (item) {
            var rest = String(item.objectName).slice("matrixCell-".length).split("-")
            var geo = root.geometry(item)
            cells.push({ row: parseInt(rest[0]), column: rest.slice(1).join("-"),
                x: geo.x, width: geo.width, height: geo.height })
        })
        root.collect("matrixPercent-").forEach(function (item) {
            var rest = String(item.objectName).slice("matrixPercent-".length).split("-")
            var geo = root.geometry(item)
            percentages.push({ row: parseInt(rest[0]), column: rest.slice(1).join("-"),
                text: String(item.text),
                x: geo.x, width: geo.width, right: Math.round((geo.x + geo.width) * 100) / 100 })
        })
        root.collect("matrixMeter-").forEach(function (item) {
            var rest = String(item.objectName).slice("matrixMeter-".length).split("-")
            var geo = root.geometry(item)
            meters.push({ row: parseInt(rest[0]), column: rest.slice(1).join("-"),
                x: geo.x, width: geo.width, visible: item.visible === true })
            var fill = root.findDescendant(item, "meterFill")
            if (fill) {
                var fillGeo = root.geometry(fill)
                meterFills.push({ row: parseInt(rest[0]), column: rest.slice(1).join("-"),
                    x: fillGeo.x, width: fillGeo.width })
            }
        })
        root.collect("matrixRowRect-").forEach(function (item) {
            var geo = root.geometry(item)
            rows.push({ row: parseInt(String(item.objectName).slice("matrixRowRect-".length)),
                x: geo.x, y: geo.y, width: geo.width, height: geo.height })
        })

        var payload = {
            columns: Quickshell.env("AGENTS_DASHBOARD_COLUMNS") || "five_hour,week,month",
            windowWidth: root.windowWidth,
            percentMode: root.percentMode,
            accountHeader: accountHeader,
            accountCells: accountCells,
            headers: headers,
            cells: cells,
            percentages: percentages,
            meters: meters,
            meterFills: meterFills,
            rows: rows
        }
        resultFile.setText(JSON.stringify(payload) + "\n")
        root.measured = true
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
            if (!root.measured) root.capture()
            Qt.quit()
        }
    }
}
