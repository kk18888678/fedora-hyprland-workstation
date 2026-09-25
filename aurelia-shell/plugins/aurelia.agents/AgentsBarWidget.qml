import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../ui"
import "AgentUsage.js" as AgentUsage

// Local AI subscription usage in the bar. The widget reads records produced by
// `workstation-ai usage` (collectors under bin/ai-usage-*) and stays hidden
// until at least one record is ready, matching Omarchy's self-hiding behavior.
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

    property var agents: []
    property bool loaded: false
    property string lastError: ""
    property int retryCount: 0
    property double lastLoadedMs: 0
    property var limitState: ({})
    property var renewalState: ({})

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
    readonly property int refreshSeconds: {
        var raw = root.settings && root.settings.refreshIntervalSec !== undefined
            ? parseInt(root.settings.refreshIntervalSec) : 900
        if (isNaN(raw) || raw < 60 || raw > 3600) return 900
        return raw
    }
    readonly property var readyAgents: AgentUsage.readyAgents(root.agents)
    readonly property var visibleAgents: AgentUsage.detectedAgents(root.agents)
    readonly property bool hasAgents: root.loaded && root.visibleAgents.length > 0
    readonly property real todayTokens: AgentUsage.todayTotal(root.readyAgents)
    // The bar surfaces the binding limit (the one that will stop the next
    // prompt) as used% plus time-to-reset, coloured by severity, instead of a
    // raw token count.
    readonly property var statusAgent: {
        var best = null
        var bestPercent = -1
        for (var i = 0; i < root.readyAgents.length; i++) {
            var limit = AgentUsage.bindingWindow(root.readyAgents[i])
            var percent = limit ? Number(limit.percent) : -1
            if (percent > bestPercent) {
                bestPercent = percent
                best = root.readyAgents[i]
            }
        }
        return best
    }
    readonly property var statusLimit: AgentUsage.bindingWindow(root.statusAgent)
    readonly property string statusText: {
        if (!root.statusLimit) return AgentUsage.formatTokens(root.todayTokens)
        var percent = Math.round(Number(root.statusLimit.percent) * 100)
        var remaining = AgentUsage.resetMsFor(root.statusLimit, Date.now())
        return remaining > 0 ? percent + "% · " + AgentUsage.formatDuration(remaining) : percent + "%"
    }
    readonly property color statusColor: {
        var severity = AgentUsage.severityForLimit(root.statusLimit)
        if (severity === "critical") return Theme.error
        if (severity === "warn") return Theme.warning
        return root.barForeground
    }
    readonly property color barForeground: root.bar && root.bar.barForeground !== undefined
        ? root.bar.barForeground : Theme.text
    readonly property bool vertical: root.bar ? root.bar.vertical === true : false
    // Uniform bar-icon contract: the usage glyph renders through the shared
    // AureliaIcon primitive at the 16 px ink canvas, not a raw Text glyph.
    readonly property int iconCanvas: root.bar && root.bar.barIconCanvas
        ? root.bar.barIconCanvas : Theme.bar.iconCanvas

    visible: root.hasAgents
    implicitWidth: root.hasAgents && !root.vertical ? agentRow.implicitWidth + Theme.spacingSm * 2
        : (root.hasAgents ? (root.bar ? root.bar.barSize : 26) : 0)
    implicitHeight: root.bar ? root.bar.barSize : 26

    function refresh() {
        if (!root.backendReady) return
        if (usageUpdateProcess.running || usageProcess.running) return
        usageUpdateProcess.running = true
    }

    function scheduleRetry() {
        if (root.retryCount >= 3) return
        root.retryCount += 1
        backendRetryTimer.restart()
    }

    // Refresh only when the last load is older than the caller's tolerance, so
    // opening the panel does not trigger a live limit probe on every click.
    function maybeRefresh(maxAgeMs) {
        if (Date.now() - root.lastLoadedMs > maxAgeMs) root.refresh()
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

    function togglePanel() {
        var panel = agentsPanelLoader.item
        if (!panel) return
        if (panel.shown) panel.close()
        else panel.open()
    }

    Component.onCompleted: {
        root.refresh()
        startupRetryTimer.restart()
    }
    onAureliaPathChanged: root.refresh()
    onBarChanged: root.refresh()

    Timer {
        id: startupRetryTimer
        interval: 4000
        repeat: false
        onTriggered: if (!root.loaded) root.refresh()
    }

    Timer {
        id: backendRetryTimer
        interval: 5000
        repeat: false
        onTriggered: root.refresh()
    }

    Loader {
        id: agentsPanelLoader
        active: true
        source: Qt.resolvedUrl("AgentsPanel.qml")
        onLoaded: item.agentsWidget = root
    }

    Process {
        id: usageUpdateProcess
        command: [root.backendBin, "usage-update"]
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
            root.applyLimitNotifications()
        }
    }

    Timer {
        interval: root.refreshSeconds * 1000
        running: !!(root.bar && root.bar.barVisible)
        repeat: true
        onTriggered: root.refresh()
    }

    MouseArea {
        id: clickArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.togglePanel()
    }

    Row {
        id: agentRow
        anchors.centerIn: parent
        spacing: Theme.spacingXs

        AureliaIcon {
            id: agentGlyph
            anchors.verticalCenter: parent.verticalCenter
            width: root.iconCanvas
            height: root.iconCanvas
            iconSize: root.iconCanvas
            glyph: "󰚩"
            tint: root.barForeground
        }

        Text {
            id: agentLabel
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.vertical
            text: root.statusText
            font.family: Theme.fontFamily
            font.pixelSize: root.bar && root.bar.barTextSize ? root.bar.barTextSize : Theme.fontSizeSm
            color: clickArea.containsMouse ? Theme.accent : root.statusColor
        }
    }
}
