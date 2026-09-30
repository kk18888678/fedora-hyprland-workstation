import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

// Real-event fixture for the consolidated AI Usage dashboard. Unlike the
// earlier interaction probe (which set `hoverColumn` / `triggerItem` and called
// `handleKey()` directly), this fixture sends REAL pointer and key events with
// QtTest so it proves the events actually reach the dashboard's items.
//
// It records, in order:
//   * hovering a real matrix cell opens the shared inline tooltip with that
//     cell's lines and switches the footer hint to the pace legend;
//   * moving the pointer away hides the inline tooltip;
//   * a real Qt.Key_Down moves the keyboard cursor, and Qt.Key_Return expands
//     the focused row.
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
    property var result: ({})
    property bool written: false

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
                item.nowMs = 1789819200000
                item.maxHeight = 620
                item.panelShown = true
            }
            onStatusChanged: {
                if (status === Loader.Error) console.error("[AGENTS-EVENTS] dashboard_load_failed")
            }
        }
    }

    // A real QtTest case that exposes its event-injection helpers; the fixture
    // drives the sequence itself. `when` stays false so TestCase never
    // registers with TestSchedule and never auto-runs (which would Qt.quit()
    // the whole fixture); the helper methods do not depend on `when`.
    TestCase { id: tc; name: "AgentsDashboardEvents"; when: false }

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
                console.error("[AGENTS-EVENTS] fixture_parse_failed " + e)
            }
        }
        onLoadFailed: console.error("[AGENTS-EVENTS] fixture_load_failed " + root.fixturePath)
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

    Timer {
        id: settleTimer
        interval: 500
        repeat: false
        onTriggered: {
            var d = root.dashboard
            if (d && d.keyTarget) d.keyTarget.forceActiveFocus()
            root.result.focusRegionAtRest = d ? String(d.focusRegion) : null
            hoverTimer.restart()
        }
    }

    Timer {
        id: hoverTimer
        interval: 200
        repeat: false
        onTriggered: {
            var cell = root.findByObjectName("matrixCell-0-five_hour")
            root.result.cellFound = cell !== null
            root.result.cellObjectName = cell ? String(cell.objectName) : null
            if (cell) tc.mouseMove(cell, cell.width / 2, cell.height / 2)
            afterHoverTimer.restart()
        }
    }

    Timer {
        id: afterHoverTimer
        interval: 700
        repeat: false
        onTriggered: {
            var d = root.dashboard
            var tooltip = root.findByObjectName("panelToolTip")
            root.result.tooltipVisibleOnHover = tooltip ? tooltip.visible === true : null
            root.result.tooltipLinesOnHover = tooltip && tooltip.lines
                ? tooltip.lines.length : -1
            root.result.tooltipTriggerIsCell = tooltip && tooltip.triggerItem
                ? String(tooltip.triggerItem.objectName) : null
            root.result.hoverColumnOnHover = d ? String(d.hoverColumn) : null
            root.result.footerKindOnHover = d && d.footerHint
                ? String(d.footerHint.kind) : null
            root.result.footerPriorityOnHover = d && d.footerHint
                ? d.footerHint.priority : -1
            // Move the pointer onto the empty card corner, away from every cell.
            tc.mouseMove(root, 4, root.height - 4)
            afterLeaveTimer.restart()
        }
    }

    Timer {
        id: afterLeaveTimer
        interval: 200
        repeat: false
        onTriggered: {
            var d = root.dashboard
            var tooltip = root.findByObjectName("panelToolTip")
            root.result.tooltipVisibleAfterLeave = tooltip ? tooltip.visible === true : null
            root.result.hoverColumnAfterLeave = d ? String(d.hoverColumn) : null
            keyTimer.restart()
        }
    }

    Timer {
        id: keyTimer
        interval: 200
        repeat: false
        onTriggered: {
            var d = root.dashboard
            if (d && d.keyTarget) d.keyTarget.forceActiveFocus()
            root.result.focusRegionBeforeKey = d ? String(d.focusRegion) : null
            root.result.keyTargetActiveFocus = d && d.keyTarget
                ? d.keyTarget.activeFocus === true : null
            var beforeRow = d ? d.focusRow : -1
            tc.keyClick(Qt.Key_Down)
            root.result.focusRowBeforeKey = beforeRow
            root.result.focusRowAfterKey = d ? d.focusRow : -1
            root.result.cursorActiveAfterKey = d ? d.cursorActive === true : null
            tc.keyClick(Qt.Key_Return)
            root.result.hasSelectionAfterReturn = d ? d.hasSelection === true : null
            writeTimer.restart()
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
        resultFile.setText(JSON.stringify(root.result) + "\n")
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
