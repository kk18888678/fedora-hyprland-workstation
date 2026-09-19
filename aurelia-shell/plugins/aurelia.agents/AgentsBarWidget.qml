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
    readonly property color barForeground: root.bar && root.bar.barForeground !== undefined
        ? root.bar.barForeground : Theme.text
    readonly property bool vertical: root.bar ? root.bar.vertical === true : false

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

        Text {
            id: agentGlyph
            anchors.verticalCenter: parent.verticalCenter
            text: "󰚩"
            font.family: Theme.fontFamily
            font.pixelSize: root.bar && root.bar.barIconFont ? root.bar.barIconFont : 13
            color: root.barForeground
        }

        Text {
            id: agentLabel
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.vertical
            text: AgentUsage.formatTokens(root.todayTokens)
            font.family: Theme.fontFamily
            font.pixelSize: root.bar && root.bar.barTextSize ? root.bar.barTextSize : Theme.fontSizeSm
            color: clickArea.containsMouse ? Theme.accent : root.barForeground
        }
    }
}
