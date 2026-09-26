import QtQuick
import Quickshell
import Quickshell.Io

// Offscreen interaction probe for the consolidated AI Usage dashboard.
//
// Verifies the runtime behaviour the static greps cannot: the close control
// clears the selection and hides the detail pane, and the icon-only refresh
// control disables and shows its busy state while a probe is running. The
// dashboard's normal selection reconciliation is left intact.
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
    // The dashboard percentage presentation; default matches production.
    readonly property string percentMode: Quickshell.env("AGENTS_DASHBOARD_PERCENT_MODE") || "remaining"
    // Focus-ring policy: captured independently of the close/refresh flow so a
    // pointer selection can be shown to leave no keyboard cursor and a real
    // key press can be shown to establish one. The object is referenced by
    // root.result, so later mutations are still serialised.
    property var focusPolicy: ({})
    property bool written: false

    visible: true
    width: 480
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
                if (status === Loader.Error) console.error("[AGENTS-INTERACT] dashboard_load_failed")
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
                focusRestTimer.restart()
            } catch (e) {
                console.error("[AGENTS-INTERACT] fixture_parse_failed " + e)
            }
        }
        onLoadFailed: console.error("[AGENTS-INTERACT] fixture_load_failed " + root.fixturePath)
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

    function topY(item) {
        if (!item || !root.dashboard) return null
        var point = item.mapToItem(root.dashboard, 0, 0)
        return Math.round(point.y * 100) / 100
    }

    // At-rest policy: the panel opens with no keyboard cursor, so neither the
    // dashboard ring nor the shared primitive's ring may be active.
    Timer {
        id: focusRestTimer
        interval: 250
        repeat: false
        onTriggered: {
            var d = root.dashboard
            var refresh = root.findByObjectName("agentsRefreshButton")
            var close = root.findByObjectName("agentsCloseButton")
            root.focusPolicy.atRestCursorActive = d ? d.cursorActive === true : null
            root.focusPolicy.atRestRefreshRing = d ? d.actionFocus("refresh") === true : null
            root.focusPolicy.atRestCloseRing = d ? d.actionFocus("close") === true : null
            root.focusPolicy.atRestRefreshKeyboardFocus = refresh ? refresh.keyboardFocus === true : null
            root.focusPolicy.atRestCloseKeyboardFocus = close ? close.keyboardFocus === true : null
            selectTimer.restart()
        }
    }

    Timer {
        id: selectTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (root.dashboard) root.dashboard.selectedAccountId = "codex"
            beforeTimer.restart()
        }
    }

    Timer {
        id: beforeTimer
        interval: 500
        repeat: false
        onTriggered: {
            var d = root.dashboard
            var detail = root.findByObjectName("agentsDetailPane")
            var close = root.findByObjectName("agentsCloseButton")
            var refresh = root.findByObjectName("agentsRefreshButton")
            var matrixHeader = root.findByObjectName("matrixAccountHeader")
            root.result = {
                hasSelectionBefore: d ? d.hasSelection === true : false,
                detailVisibleBefore: detail ? detail.visible === true : false,
                closePresent: close !== null,
                refreshPresent: refresh !== null,
                refreshEnabledBefore: refresh ? refresh.enabled === true : false,
                // Placement: Refresh is in the always-present header ABOVE the
                // matrix; Close is in the action row BELOW it.
                refreshY: root.topY(refresh),
                matrixY: root.topY(matrixHeader),
                closeY: root.topY(close),
                focusPolicy: root.focusPolicy
            }
            if (close) close.triggered()
            afterCloseTimer.restart()
        }
    }

    Timer {
        id: afterCloseTimer
        interval: 300
        repeat: false
        onTriggered: {
            var d = root.dashboard
            var detail = root.findByObjectName("agentsDetailPane")
            var close = root.findByObjectName("agentsCloseButton")
            root.result.hasSelectionAfterClose = d ? d.hasSelection === true : false
            root.result.detailVisibleAfterClose = detail ? detail.visible === true : false
            root.result.closeVisibleAfterClose = close ? close.visible === true : false
            mockWidget.refreshing = true
            busyTimer.restart()
        }
    }

    Timer {
        id: busyTimer
        interval: 300
        repeat: false
        onTriggered: {
            var refresh = root.findByObjectName("agentsRefreshButton")
            root.result.refreshEnabledWhileBusy = refresh ? refresh.enabled === true : false
            root.result.refreshActiveWhileBusy = refresh ? refresh.active === true : false
            mockWidget.refreshing = false
            idleTimer.restart()
        }
    }

    Timer {
        id: idleTimer
        interval: 300
        repeat: false
        onTriggered: {
            var refresh = root.findByObjectName("agentsRefreshButton")
            root.result.refreshEnabledAfter = refresh ? refresh.enabled === true : false
            root.result.refreshActiveAfter = refresh ? refresh.active === true : false
            focusPointerTimer.restart()
        }
    }

    // Pointer policy: selecting a row through the pointer entry point must not
    // create a keyboard cursor or a ring on either action control.
    Timer {
        id: focusPointerTimer
        interval: 250
        repeat: false
        onTriggered: {
            var d = root.dashboard
            var refresh = root.findByObjectName("agentsRefreshButton")
            var close = root.findByObjectName("agentsCloseButton")
            if (d) d.selectAccountByPointer(1)
            root.focusPolicy.afterPointerCursorActive = d ? d.cursorActive === true : null
            root.focusPolicy.afterPointerRefreshRing = d ? d.actionFocus("refresh") === true : null
            root.focusPolicy.afterPointerCloseRing = d ? d.actionFocus("close") === true : null
            root.focusPolicy.afterPointerRefreshKeyboardFocus = refresh ? refresh.keyboardFocus === true : null
            root.focusPolicy.afterPointerCloseKeyboardFocus = close ? close.keyboardFocus === true : null
            focusKeyboardTimer.restart()
        }
    }

    // Keyboard policy: a real key handler establishes the cursor and therefore
    // a visible ring. Tab exercises the real region cycling (at least one
    // press, then until the action region is reached) and j would move within
    // the region; the ring must be on the focused action.
    Timer {
        id: focusKeyboardTimer
        interval: 250
        repeat: false
        onTriggered: {
            var d = root.dashboard
            var refresh = root.findByObjectName("agentsRefreshButton")
            if (d) {
                d.handleKey({ key: Qt.Key_Tab, modifiers: 0, text: "", accepted: false })
                var guard = 0
                while (d.focusRegion !== "actions" && guard < 4) {
                    d.handleKey({ key: Qt.Key_Tab, modifiers: 0, text: "", accepted: false })
                    guard++
                }
            }
            root.focusPolicy.afterKeyboardCursorActive = d ? d.cursorActive === true : null
            root.focusPolicy.afterKeyboardFocusRegion = d ? d.focusRegion : null
            root.focusPolicy.afterKeyboardRefreshRing = d ? d.actionFocus("refresh") === true : null
            root.focusPolicy.afterKeyboardRefreshKeyboardFocus = refresh ? refresh.keyboardFocus === true : null
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
        interval: 9000
        running: true
        repeat: false
        onTriggered: {
            root.writeResult()
            Qt.quit()
        }
    }
}
