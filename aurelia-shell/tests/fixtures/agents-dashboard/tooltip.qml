import QtQuick
import Quickshell
import Quickshell.Io

// Offscreen probe for the dashboard's single in-scene tooltip.
//
// It loads the real AgentsDashboard, points the shared AureliaInlineToolTip at
// a matrix cell with a synthetic line set, waits past the 400 ms delay, and
// reports whether the tooltip is visible, inside the dashboard's own bounds,
// using the theme tooltip text colour for every line and clipping nothing.
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
        width: 560
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
                console.error("[AGENTS-TOOLTIP] fixture_parse_failed " + e)
            }
        }
    }

    Timer {
        id: selectTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (root.dashboard) root.dashboard.selectedAccountId = "codex"
            hoverTimer.restart()
        }
    }

    Timer {
        id: hoverTimer
        interval: 300
        repeat: false
        onTriggered: {
            var tooltip = root.findByObjectName("panelToolTip")
            var cell = root.findByObjectName("matrixCell-0-five_hour") ||
                root.findByObjectName("matrixPercent-0-five_hour")
            if (tooltip && cell) {
                tooltip.triggerItem = cell
                tooltip.lines = [
                    { text: "Codex · 5-hour", tone: "default", strong: true },
                    { text: "42% used · resets today 15:30", tone: "default", strong: false },
                    { text: "Runs out in ~2h 50m at this rate", tone: "warning", strong: false }
                ]
                tooltip.hovered = true
            }
            measureTimer.restart()
        }
    }

    Timer {
        id: measureTimer
        interval: 700
        repeat: false
        onTriggered: root.capture()
    }

    function collectByName(prefix) {
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

    function findByObjectName(name) {
        var all = root.collectByName(name)
        for (var i = 0; i < all.length; i++) {
            if (String(all[i].objectName) === name) return all[i]
        }
        return null
    }

    function collectTextColors(node, out) {
        var kids = node.children || []
        for (var i = 0; i < kids.length; i++) {
            var child = kids[i]
            if (typeof child.text === "string" && child.color !== undefined &&
                child.font !== undefined && child.visible !== false &&
                String(child.text) !== "▲" && String(child.text) !== "●") {
                out.push(String(child.color))
            }
            collectTextColors(child, out)
        }
    }

    function collectElided(node) {
        var found = false
        var kids = node.children || []
        for (var i = 0; i < kids.length; i++) {
            var child = kids[i]
            if (child.truncated === true) found = true
            if (collectElided(child)) found = true
        }
        return found
    }

    function capture() {
        if (root.written) return
        root.written = true
        var d = root.dashboard
        var tooltip = root.findByObjectName("panelToolTip")
        var payload = {
            tooltipCount: root.collectByName("panelToolTip").length,
            found: tooltip !== null,
            dashboardWidth: d ? d.width : -1,
            dashboardHeight: d ? d.height : -1
        }
        if (tooltip) {
            payload.visible = tooltip.visible === true
            payload.x = tooltip.x
            payload.y = tooltip.y
            payload.width = tooltip.width
            payload.height = tooltip.height
            payload.textColor = String(tooltip.textColor)
            payload.backgroundColor = String(tooltip.backgroundColor)
            var colors = []
            root.collectTextColors(tooltip, colors)
            payload.textColors = colors
            payload.elided = root.collectElided(tooltip)
        }
        resultFile.setText(JSON.stringify(payload) + "\n")
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
            root.capture()
            Qt.quit()
        }
    }
}
