import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

// Real-event fixture for the bounded footer key-caps hint.
//
// The dashboard used to key hint priority 2 off `cursorActive`, which is
// cleared only by the next pointer interaction. After any arrow key the
// key-caps hint therefore pinned itself and the idle rotation never resumed.
// This fixture presses a REAL key with QtTest, then advances the (shortened)
// key-hint and rotation intervals and proves the hint decays back to the idle
// rotation and the rotation advances.
//
// It also audits the other hint priorities for the same latch: the hover-driven
// hint (3/4) must release on hover exit and the stale hint (1) must clear when
// the data is fresh again. The full rotation/footer contract is in
// test_agents_dashboard_footer.sh.
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
                if (status === Loader.Error) console.error("[AGENTS] dashboard_load_failed")
            }
        }
    }

    // A real QtTest case that exposes the event-injection helpers. `when`
    // stays false so it never auto-runs and never Qt.quit()s the fixture.
    TestCase { id: tc; name: "AgentsDashboardFooterLatch"; when: false }

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
                console.error("[AGENTS] fixture_parse_failed " + e)
            }
        }
        onLoadFailed: console.error("[AGENTS] fixture_load_failed " + root.fixturePath)
    }

    function snap(label) {
        var d = root.dashboard
        return {
            label: label,
            priority: d && d.footerHint ? d.footerHint.priority : -1,
            kind: d && d.footerHint ? String(d.footerHint.kind) : null,
            rotationIndex: d ? d.rotationIndex : -1,
            keyHintVisible: d ? d.keyHintVisible === true : null,
            cursorActive: d ? d.cursorActive === true : null
        }
    }

    Timer {
        id: settleTimer
        interval: 500
        repeat: false
        onTriggered: {
            var d = root.dashboard
            if (d && d.keyTarget) d.keyTarget.forceActiveFocus()
            // Shortened intervals so the decay is proven without a real wait.
            d.keyHintIntervalMs = 250
            // Keep the idle rotation parked while the hover/stale audit runs.
            d.rotationIntervalMs = 100000
            root.result.beforeKey = root.snap("beforeKey")

            // Audit 1/3/4: none may latch.
            d.hoverColumn = "five_hour"
            root.result.priorityLegend = d.footerHint.priority
            d.hoverColumn = ""
            root.result.priorityAfterLegendExit = d.footerHint.priority

            d.hoverRow = 0
            root.result.priorityRow = d.footerHint.priority
            d.hoverRow = -1
            root.result.priorityAfterRowExit = d.footerHint.priority

            d.nowMs = 1789819200000 + 7200000
            root.result.priorityStale = d.footerHint.priority
            d.nowMs = 1789819200000
            root.result.priorityAfterFresh = d.footerHint.priority

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
            root.result.keyTargetActiveFocus = d && d.keyTarget
                ? d.keyTarget.activeFocus === true : null
            tc.keyClick(Qt.Key_Down)
            // The hint is shown immediately, but the rotation is unparked here
            // so the post-decay rotation is short.
            d.rotationIntervalMs = 250
            root.result.afterKey = root.snap("afterKey")
            expireTimer.restart()
        }
    }

    Timer {
        id: expireTimer
        interval: 320
        repeat: false
        onTriggered: {
            root.result.afterKeyExpiry = root.snap("afterKeyExpiry")
            rotateTimer.restart()
        }
    }

    Timer {
        id: rotateTimer
        interval: 400
        repeat: false
        onTriggered: {
            root.result.afterRotation = root.snap("afterRotation")
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
