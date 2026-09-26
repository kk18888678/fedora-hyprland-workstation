import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../ui"
import "AgentUsage.js" as AgentUsage

// Local AI subscription usage in the bar. The affordance is deliberately
// ICON-ONLY: one shared-primitive glyph in a square slot that never widens,
// with no percentage, provider label or countdown beside it. State is encoded
// as tint + a 4 px warn/critical/error dot + opacity so the severity colour is
// never traded away for a hover accent. The widget reads records produced by
// `workstation-ai usage` (collectors under bin/ai-usage-*) and stays hidden
// until at least one record is detected.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string aureliaPath: ""
    property string moduleName: "aurelia.agents"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var barAnchorItem: null
    property bool ipcReady: false

    property var agents: []
    property bool loaded: false
    property string lastError: ""
    property int retryCount: 0
    property double lastLoadedMs: 0
    property real nowMs: Date.now()
    property bool pendingForce: false
    property var limitState: ({})
    property var renewalState: ({})
    // Non-visual refresh state exposed to the panel so its icon-only Refresh
    // control can disable itself and show a busy state while a probe runs.
    // The bar affordance itself is unchanged.
    readonly property bool refreshing: usageUpdateProcess.running || usageProcess.running

    readonly property string backendBin: {
        var override = Quickshell.env("WORKSTATION_AI_BIN") || ""
        if (override.indexOf("/") === 0) return override
        if (root.aureliaPath !== "") return root.aureliaPath + "/../bin/workstation-ai"
        return "/usr/local/bin/workstation-ai"
    }
    // The host assigns aureliaPath after the widget is constructed, so the
    // first refresh must not race it into a non-existent installed path.
    readonly property bool backendReady: (Quickshell.env("WORKSTATION_AI_BIN") || "") !== "" || root.aureliaPath !== ""
    readonly property var processEnvironment: ({
        "PATH": "/usr/local/bin:/usr/bin:/bin" + (Quickshell.env("PATH") ? ":" + Quickshell.env("PATH") : ""),
        "HOME": Quickshell.env("HOME") || "",
        "XDG_RUNTIME_DIR": Quickshell.env("XDG_RUNTIME_DIR") || "",
        "XDG_STATE_HOME": Quickshell.env("XDG_STATE_HOME") || "",
        "XDG_CONFIG_HOME": Quickshell.env("XDG_CONFIG_HOME") || ""
    })
    // The refresh interval is clamped to [30, 3600] seconds. Anything outside
    // that band is a configuration error, not a reason to hammer the backend.
    readonly property int refreshSeconds: {
        var raw = root.settings && root.settings.refreshIntervalSec !== undefined
            ? parseInt(root.settings.refreshIntervalSec) : 900
        if (isNaN(raw)) return 900
        return Math.max(30, Math.min(3600, raw))
    }
    // A record older than this is stale: its numbers are dimmed and never
    // presented as live.
    readonly property int staleMs: {
        var raw = root.settings && root.settings.staleAfterSec !== undefined
            ? parseInt(root.settings.staleAfterSec) : 1800
        if (isNaN(raw)) return 1800 * 1000
        return Math.max(60, Math.min(86400, raw)) * 1000
    }
    readonly property var readyAgents: AgentUsage.readyAgents(root.agents)
    readonly property var visibleAgents: AgentUsage.detectedAgents(root.agents)
    readonly property bool hasAgents: root.loaded && root.visibleAgents.length > 0
    readonly property var barState: AgentUsage.barState(root.agents, root.nowMs, {
        loading: !root.loaded,
        backendError: root.lastError,
        staleMs: root.staleMs
    })
    readonly property string stateTint: root.barState.tint
    readonly property bool stateDot: root.barState.dot
    readonly property real stateOpacity: root.barState.opacity
    readonly property color statusColor: {
        var tint = root.barState.tint
        if (tint === "warning") return Theme.warning
        if (tint === "error") return Theme.error
        if (tint === "textMuted") return Theme.textMuted
        return root.barForeground
    }
    readonly property color barForeground: root.bar && root.bar.barForeground !== undefined
        ? root.bar.barForeground : Theme.text
    readonly property bool vertical: root.bar ? root.bar.vertical === true : false
    // Uniform bar-icon contract: the usage glyph renders through the shared
    // AureliaIcon primitive at the 16 px ink canvas, not a raw Text glyph.
    readonly property int iconCanvas: root.bar && root.bar.barIconCanvas
        ? root.bar.barIconCanvas : Theme.bar.iconCanvas
    readonly property var agentsPanel: agentsPanelLoader.item

    readonly property bool ipcOwner: {
        var revision = root.bar && root.bar.widgetRevision !== undefined
            ? root.bar.widgetRevision : -1
        if (!root.barAnchorItem) return false
        if (!root.bar || typeof root.bar.anchorItemFor !== "function") return true
        return root.bar.anchorItemFor(root.moduleName) === root.barAnchorItem
    }

    visible: root.hasAgents
    // A square slot that never widens: the icon is the whole affordance.
    implicitWidth: root.hasAgents ? (root.bar ? root.bar.barSize : 26) : 0
    implicitHeight: root.bar ? root.bar.barSize : 26

    function configurePanel(target) {
        if (!target) return
        if ("agentsWidget" in target) target.agentsWidget = root
        if ("bar" in target) target.bar = root.bar
        if ("shell" in target) target.shell = root.shell
        if ("anchorItem" in target) target.anchorItem = root.barAnchorItem || root
    }

    function open(payloadJson) {
        if (!root.agentsPanel || typeof root.agentsPanel.open !== "function") return "not-ready"
        root.configurePanel(root.agentsPanel)
        return root.agentsPanel.open(payloadJson || "{}")
    }

    function close() {
        if (!root.agentsPanel || typeof root.agentsPanel.close !== "function") return "not-ready"
        return root.agentsPanel.close()
    }

    function toggle(payloadJson) {
        if (root.isVisible()) return root.close()
        return root.open(payloadJson || "{}")
    }

    function isVisible() {
        return !!(root.agentsPanel && root.agentsPanel.shown === true)
    }

    function refresh(force) {
        if (!root.backendReady) return
        if (usageUpdateProcess.running || usageProcess.running) return
        root.pendingForce = force === true
        usageUpdateProcess.running = true
    }

    // Right-click launches the user's default agent in a terminal. This never
    // installs anything; `workstation-ai launch` fails closed when no default
    // agent is selected.
    function launch() {
        if (root.backendBin === "") return
        Quickshell.execDetached([root.backendBin, "launch"])
    }

    function scheduleRetry() {
        if (root.retryCount >= 3) return
        root.retryCount += 1
        backendRetryTimer.restart()
    }

    // Refresh only when the last load is older than the caller's tolerance, so
    // opening the panel does not trigger a live limit probe on every click.
    function maybeRefresh(maxAgeMs) {
        if (Date.now() - root.lastLoadedMs > maxAgeMs) root.refresh(false)
    }

    // Truthful tooltip: it names the unit (percentage for an authoritative
    // window, billable tokens for a local-only provider), the provider, the
    // window label, the reset countdown and the record freshness.
    function tooltipText() {
        if (!root.hasAgents) return ""
        if (root.readyAgents.length === 0) return "AI agents · waiting for usage data"
        var lines = []
        for (var i = 0; i < root.readyAgents.length; i++) {
            var agent = root.readyAgents[i]
            var name = String(agent.name || agent.id)
            var limit = AgentUsage.bindingLimit(agent, root.nowMs)
            if (limit) {
                var percent = Math.round(Number(limit.percent) * 100)
                var label = String(limit.label || "limit")
                var line = name + " · " + label + " " + percent + "% used"
                var remaining = AgentUsage.resetMsFor(limit, root.nowMs)
                if (remaining > 0) line += " · resets in " + AgentUsage.formatDuration(remaining)
                lines.push(line)
            } else {
                lines.push(name + " · " + AgentUsage.formatTokens(agent.todayBillableTokens) + " billable tokens today")
            }
        }
        var freshness = AgentUsage.freshnessPill(root.readyAgents[0], root.nowMs, root.staleMs)
        if (freshness.text !== "") lines.push("Updated " + freshness.text)
        return lines.join("\n")
    }

    // Notify on limit resets and near-exhaustion. The previous observation is
    // fed back so only transitions fire, not the steady state.
    function applyLimitNotifications() {
        var limits = AgentUsage.limitTransitions(root.agents, root.limitState)
        root.limitState = limits.state
        var renewals = AgentUsage.renewalReminders(root.agents, root.renewalState,
            AgentUsage.todayDate(Date.now()))
        root.renewalState = renewals.state
        var notices = limits.notifications.concat(renewals.notifications)
        for (var i = 0; i < notices.length; i++) {
            Quickshell.execDetached([
                "notify-send", "-a", "Aurelia Agents", "-u", "normal",
                notices[i].title, notices[i].body
            ])
        }
    }

    Component.onCompleted: {
        root.refresh(false)
        startupRetryTimer.restart()
    }
    onAureliaPathChanged: root.refresh(false)
    onBarChanged: root.refresh(false)
    onIpcOwnerChanged: {
        root.ipcReady = false
        ipcOwnerSettleTimer.restart()
    }

    Timer {
        id: ipcOwnerSettleTimer
        interval: 50
        repeat: false
        onTriggered: root.ipcReady = root.ipcOwner
    }

    Timer {
        id: startupRetryTimer
        interval: 4000
        repeat: false
        onTriggered: if (!root.loaded) root.refresh(false)
    }

    Timer {
        id: backendRetryTimer
        interval: 5000
        repeat: false
        onTriggered: root.refresh(false)
    }

    // Keeps stale detection and the tooltip countdown honest while visible.
    Timer {
        interval: 60000
        running: root.hasAgents
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    Component {
        id: agentsIpcHandler

        IpcHandler {
            target: "aurelia.agents"

            function ping(): bool { return root.agentsPanel !== null }
            function open(): void { root.open("{}") }
            function close(): void { root.close() }
            function show(): void { root.open("{}") }
            function hide(): void { root.close() }
            function toggle(): void { root.toggle("{}") }
            function refresh(): void { root.refresh(true) }
        }
    }

    Loader {
        active: root.ipcOwner && root.ipcReady
        sourceComponent: agentsIpcHandler
    }

    Loader {
        id: agentsPanelLoader
        active: true
        source: Qt.resolvedUrl("AgentsPanel.qml")
        onLoaded: root.configurePanel(item)
        onStatusChanged: {
            if (status === Loader.Error) console.error("[AGENTS] panel_load_failed")
        }
    }

    Process {
        id: usageUpdateProcess
        command: root.pendingForce
            ? [root.backendBin, "usage-update", "--force"]
            : [root.backendBin, "usage-update"]
        environment: root.processEnvironment
        running: false
        onExited: function (code) {
            usageProcess.running = true
        }
    }

    Process {
        id: usageProcess
        command: [root.backendBin, "usage"]
        environment: root.processEnvironment
        running: false
        stdout: StdioCollector { id: usageOut }
        onExited: function (code) {
            if (code !== 0) {
                root.lastError = "usage backend failed"
                root.loaded = true
                root.scheduleRetry()
                return
            }
            root.agents = AgentUsage.parseRecords(usageOut.text)
            root.loaded = true
            root.lastError = ""
            root.retryCount = 0
            root.lastLoadedMs = Date.now()
            root.nowMs = root.lastLoadedMs
            root.applyLimitNotifications()
        }
    }

    Timer {
        interval: root.refreshSeconds * 1000
        running: !!(root.bar && root.bar.barVisible)
        repeat: true
        onTriggered: root.refresh(false)
    }

    HoverHandler { id: pointerHover }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        // Hover paints only the selection fill. It must never replace the
        // severity tint, or hovering to inspect an alarm would erase it.
        color: root.isVisible() || pointerHover.hovered ? Theme.selection : "transparent"
    }

    AureliaIcon {
        id: agentGlyph
        anchors.centerIn: parent
        width: root.iconCanvas
        height: root.iconCanvas
        iconSize: root.iconCanvas
        glyph: "󰚩"
        tint: root.stateTint === "barForeground" ? root.barForeground : root.statusColor
        opacity: root.stateOpacity
    }

    // A 4 px dot marks warn/critical/error only; unknown and stale never get a
    // dot, because those are not actionable alarms.
    Rectangle {
        id: stateDot
        visible: root.stateDot
        width: 4
        height: 4
        radius: 2
        color: root.statusColor
        opacity: root.stateOpacity
        anchors.right: agentGlyph.right
        anchors.top: agentGlyph.top
    }

    MouseArea {
        id: clickArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function (mouse) {
            mouse.accepted = true
            if (mouse.button === Qt.RightButton) root.launch()
            else if (mouse.button === Qt.MiddleButton) root.refresh(true)
            else root.toggle("{}")
        }
    }

    AureliaToolTip {
        triggerItem: root
        bar: root.bar
        hovered: pointerHover.hovered
        text: root.tooltipText()
    }
}
