import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../ui"
import "../../services"
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
    // Durable announced-state. It is loaded from disk once, then advanced in
    // memory and persisted atomically. Emission is blocked until it has loaded,
    // otherwise a restart would plan against an empty baseline and overwrite
    // the durable state before the real value arrived.
    property var notificationState: null
    property bool notificationStateLoaded: false
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
    // Resolved, fail-closed presentation mode for the panel and the tooltip.
    // `remaining` (100% = fully available) is the default; only an explicit
    // `used` switches to the consumed-fraction presentation.
    readonly property string percentMode: AgentUsage.normalizePercentMode(
        root.settings && root.settings.percentMode !== undefined
            ? root.settings.percentMode : "remaining")
    // Notification settings are read from the manifest-default overlay the host
    // injects. These MUST be honoured by applyLimitNotifications: a stored
    // setting that is not read is exactly the reported failure.
    function boolSetting(key, fallback) {
        var value = root.settings ? root.settings[key] : undefined
        if (value === true || value === false) return value
        if (value === undefined || value === null || value === "") return fallback
        var text = String(value).toLowerCase()
        if (text === "true") return true
        if (text === "false") return false
        return fallback
    }
    readonly property bool notificationsEnabled: root.boolSetting("notifications", true)
    readonly property string notifyMinSeverity: {
        var raw = root.settings && root.settings.notifyMinSeverity !== undefined
            ? String(root.settings.notifyMinSeverity).toLowerCase() : "warn"
        return raw === "critical" ? "critical" : "warn"
    }
    readonly property bool notifyRenewals: root.boolSetting("notifyRenewals", true)
    // First-party sender. The explicit "Aurelia Agents" app name is required:
    // the sender defaults to "aurelia-action", which the notification service
    // treats as a DND bypass. "Aurelia Agents" is a normal app name, so global
    // DND keeps working.
    readonly property string notificationSender: {
        if (root.aureliaPath !== "") return root.aureliaPath + "/bin/aurelia-notification-send"
        return "/usr/local/bin/aurelia-notification-send"
    }
    readonly property string notificationStatePath: {
        var stateHome = Quickshell.env("XDG_STATE_HOME") || ""
        if (stateHome.indexOf("/") !== 0) {
            var home = Quickshell.env("HOME") || ""
            stateHome = home !== "" ? home + "/.local/state" : ""
        }
        if (stateHome === "" || stateHome === "/") return ""
        return stateHome + "/aurelia/agents/notification-state.json"
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
    // The transparent bar's global halo is derived from the adaptive bar
    // foreground, and the adaptive sampler never selects an alert tint
    // (status colours hardcode Theme.error/Theme.warning). So an alert icon
    // derives its own halo from the ALERT COLOUR's luminance: a dark red gets
    // a light halo, a bright yellow a dark one. It is applied inside this
    // widget, independent of stateOpacity, so a (theoretical) dim can never
    // weaken the legibility aid. This is defence in depth: across an arbitrary
    // wallpaper no fixed token can guarantee a 4.5:1 ratio, so the transparent
    // bar alert additionally relies on this halo and on the non-colour dot.
    readonly property bool alertTint: root.stateTint === "error" || root.stateTint === "warning"
    readonly property bool transparentBar: root.bar ? root.bar.transparent === true : false
    readonly property color alertHaloColor: {
        var c = root.statusColor
        var luminance = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        return luminance > 0.5 ? "#000000" : "#ffffff"
    }
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
                var percent = Math.round(
                    AgentUsage.displayPercent(Number(limit.percent), root.percentMode) * 100)
                var label = String(limit.label || "limit")
                var unit = root.percentMode === "used" ? "used" : "remaining"
                var line = name + " · " + label + " " + percent + "% " + unit
                var remaining = AgentUsage.resetMsFor(limit, root.nowMs)
                if (remaining > 0) line += " · resets in " + AgentUsage.formatDuration(remaining)
                lines.push(line)
            } else {
                lines.push(name + " · " + AgentUsage.formatTokens(agent.todayBillableTokens) + " billable tokens today")
            }
        }
        // Freshness is across every ready account, not just the first one, and
        // the helper already supplies the `updated …` prefix.
        var freshness = AgentUsage.overallFreshnessPill(root.readyAgents, root.nowMs, root.staleMs)
        if (freshness.text !== "") lines.push(freshness.text)
        return lines.join("\n")
    }

    // Decide and emit notifications. The pure policy owns every anti-flood
    // rule; this only reads settings, gates on the single owner, persists the
    // returned state atomically, and hands the bounded list to the sender.
    function applyLimitNotifications() {
        // Gate emission to the one anchored instance so N screens cannot each
        // emit their own copy of the same event. The persisted state plus the
        // minimum interval keep even a race non-flooding.
        if (!root.ipcOwner) return
        if (!root.notificationsEnabled) return
        if (!root.notificationStateLoaded) return
        var plan = AgentUsage.notificationPlan(root.agents, root.notificationState, {
            enabled: root.notificationsEnabled,
            minSeverity: root.notifyMinSeverity,
            renewals: root.notifyRenewals
        }, Date.now())
        root.notificationState = plan.state
        // Persist the advanced state atomically (0600, temp-file-plus-rename).
        // The write is async, but the in-memory state is already advanced, so a
        // crash before the rename only means the next start re-baselines.
        notificationStore.setValue(AgentUsage.serializeNotificationState(plan.state))
        for (var i = 0; i < plan.notifications.length; i++) {
            var notice = plan.notifications[i]
            // DND remains respected: normal urgency plus a non-bypassing app
            // name. The announced state above still advances while DND mutes
            // display, so disabling DND cannot replay a backlog.
            Quickshell.execDetached([
                root.notificationSender, "--app-name", "Aurelia Agents", "-u", "normal",
                String(notice.title || "AI usage"), String(notice.body || "")
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

    // Atomic 0600 announced-state persistence at
    // $XDG_STATE_HOME/aurelia/agents/notification-state.json. A missing, empty
    // or corrupt file loads as empty state, which baseline-suppresses rather
    // than bursting. The write is a temp-file-plus-rename in the store.
    OptionalFileStore {
        id: notificationStore
        path: root.notificationStatePath
        writable: true
        watchChanges: false
        onLoaded: function(value) {
            root.notificationState = AgentUsage.deserializeNotificationState(value)
            root.notificationStateLoaded = true
        }
        onLoadFailed: function(reason) {
            root.notificationState = AgentUsage.deserializeNotificationState("")
            root.notificationStateLoaded = true
        }
    }

    HoverHandler { id: pointerHover }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        // Hover paints only the selection fill. It must never replace the
        // severity tint, or hovering to inspect an alarm would erase it.
        color: root.isVisible() || pointerHover.hovered ? Theme.selection : "transparent"
    }

    // The glyph and its dot share one legibility halo so the alert icon is
    // legible over an arbitrary wallpaper. It is enabled only on a transparent
    // bar and only for a status tint, so the opaque bar and the general
    // (non-alert) bar content keep their existing global halo behaviour.
    Item {
        id: glyphHaloLayer
        anchors.centerIn: parent
        width: root.iconCanvas
        height: root.iconCanvas

        AureliaIcon {
            id: agentGlyph
            objectName: "agentGlyph"
            anchors.centerIn: parent
            // Optical nudge: the robot's visual centre of mass is y = 14.3 on
            // the 24-unit grid against an ink centre of 12, so it looks about
            // 11% low. This is applied to this glyph only; AureliaIcon keeps
            // its generic centring.
            anchors.verticalCenterOffset: -1
            width: root.iconCanvas
            height: root.iconCanvas
            iconSize: root.iconCanvas
            glyph: "󰚩"
            // Usage is shown ONLY by the dot; the glyph itself never takes the
            // status colour or a dimmed opacity.
            tint: root.barForeground
        }

        // A 4 px dot marks warn/critical/error only; staleness never removes
        // it, because it is the colour-blind-safe cue for the alert. Unknown
        // is not an actionable alarm and keeps no dot.
        Rectangle {
            id: stateDot
            objectName: "stateDot"
            visible: root.stateDot
            width: 4
            height: 4
            radius: 2
            color: root.statusColor
            opacity: root.stateOpacity
            // 󰚩 head top-right is a quarter circle centred at (14,14) r=7 on
            // the 24-unit MDI grid. At the 16 px icon canvas (ink ≈ 0.584
            // px/unit) a 4 px dot with a 1 px gap has its centre at ink-box
            // fractions (0.98, 0.17): outside the glyph shape, tangent to the
            // head's top-right shoulder. There is deliberately NO ring and no
            // surface behind the dot: painting one would break the documented
            // "transparent = no surface, opaque = themed surface" invariant.
            x: Math.round(agentGlyph.x + agentGlyph.glyphInkRect.x + 0.98 * agentGlyph.glyphInkRect.width - width / 2)
            y: Math.round(agentGlyph.y + agentGlyph.glyphInkRect.y + 0.17 * agentGlyph.glyphInkRect.height - height / 2)
            // The transparent-bar alert halo now wraps ONLY the dot. The
            // neutral glyph takes the bar's normal global halo like every
            // other widget, and the opaque bar shows neither halo nor ring.
            layer.enabled: root.transparentBar && root.alertTint
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: root.alertHaloColor
                shadowOpacity: 0.95
                shadowBlur: 0.55
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                shadowScale: 1.0
            }
        }
    }

    MouseArea {
        id: clickArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        // Dismiss the tooltip the moment the pointer presses, so after a click
        // it never sits on top of the panel that just opened.
        onPressed: barToolTip.dismiss()
        onClicked: function (mouse) {
            mouse.accepted = true
            if (mouse.button === Qt.RightButton) root.launch()
            else if (mouse.button === Qt.MiddleButton) root.refresh(true)
            else root.toggle("{}")
        }
    }

    AureliaToolTip {
        id: barToolTip
        triggerItem: root
        bar: root.bar
        // The tooltip may reappear only after the pointer leaves and re-enters
        // while the panel is closed.
        hovered: pointerHover.hovered && !root.isVisible()
        text: root.tooltipText()
    }
}
