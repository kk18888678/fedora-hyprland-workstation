import QtQuick
import Quickshell
import Quickshell.Io

// Offscreen preview harness for the consolidated Usage dashboard.
//
// A PanelWindow does not render offscreen, so this fixture loads
// AgentsDashboard (the exact panel body) inside a plain QtQuick.Window and
// grabs the real pixels with Item.grabToImage. It is used both by the test
// suite (smoke render) and by the committed render script that produces the
// user-facing preview PNG. The card colors come from the dashboard's exposed
// surface tokens so this file never imports the Theme singleton directly
// (directory imports outside the Quickshell config folder are rejected).
Window {
    id: root

    readonly property string imagePath: Quickshell.env("AGENTS_DASHBOARD_IMAGE") || ""
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
    property bool grabbed: false
    readonly property string backendError: Quickshell.env("AGENTS_DASHBOARD_BACKEND_ERROR") || ""
    // Empty means the resting consolidated matrix (no account expanded).
    readonly property string selectId: Quickshell.env("AGENTS_DASHBOARD_SELECT") || ""

    visible: true
    width: 480
    height: card.height + 24
    color: dashboard ? dashboard.surfaceBackdrop : "#191724"

    QtObject {
        id: mockWidget
        property var visibleAgents: root.records
        property bool loaded: true
        property string lastError: root.backendError
        property bool refreshing: false
        property int staleMs: 1800000
        property var bar: null
        function refresh(force) {}
        function maybeRefresh(age) {}
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 12
        width: 460
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
                if (status === Loader.Error) console.error("[AGENTS-PREVIEW] dashboard_load_failed")
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
                console.error("[AGENTS-PREVIEW] fixture_parse_failed " + e)
            }
        }
        onLoadFailed: console.error("[AGENTS-PREVIEW] fixture_load_failed " + root.fixturePath)
    }

    Timer {
        id: selectTimer
        interval: 250
        repeat: false
        onTriggered: if (root.dashboard && root.selectId !== "")
            root.dashboard.selectedAccountId = root.selectId
    }

    function writeResult() {
        if (root.resultPath === "") return
        resultFile.setText(JSON.stringify({
            records: root.records.length,
            rows: root.dashboard ? root.dashboard.rows.length : -1,
            selected: root.dashboard ? root.dashboard.selectedAccountId : "",
            showBalance: root.dashboard ? root.dashboard.showBalance : false,
            detailHeight: root.dashboard ? root.dashboard.maxDetailHeight : -1,
            cardHeight: card.height,
            imageSaved: root.grabbed
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
        interval: 1400
        running: true
        repeat: false
        onTriggered: {
            card.grabToImage(function (result) {
                if (result && root.imagePath !== "") {
                    root.grabbed = result.saveToFile(root.imagePath) === true
                }
                root.writeResult()
            })
        }
    }

    Timer {
        interval: 7000
        running: true
        repeat: false
        onTriggered: {
            root.writeResult()
            Qt.quit()
        }
    }
}
