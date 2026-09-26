import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "SettingsRows.js" as SettingsRows
import "SettingsBackends.js" as SettingsBackends
import "../../../theme"
import "."

// Settings hub window: one screen for Hyprland and (when the resident shell
// is Aurelia) Aurelia Shell settings.
//
// Ownership boundary:
//   * Hyprland options go through the bounded workstation-hypr-settings
//     backend, which writes the user-owned overlay and live-applies it.
//   * Aurelia options go through the existing aurelia-* / workstation-aurelia
//     CLI helpers. This surface never mutates configuration directly.
//   * Every external command is bounded and executed sequentially.
PanelWindow {
    id: root

    property var pluginRoot: null

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aurelia-settings"

    // Self-contained close (mirrors the keybindings window lifecycle).
    // Never round-trips through the plugin, so plugin.close() -> requestClose()
    // cannot recurse.
    function requestClose(reason) {
        root.visible = false
        if (pluginRoot && pluginRoot.bar && typeof pluginRoot.bar.releasePopout === "function") {
            pluginRoot.bar.releasePopout(root)
        }
    }
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 1000
    implicitHeight: 680
    color: "transparent"
    visible: false

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    property string activeSection: "hypr-general"
    property var sections: SettingsRows.sections()
    property var schemas: []
    property var schemaMap: ({})
    property var statusMap: ({})
    property var statusMeta: ({ hyprctlAvailable: false })
    property var aureliaState: SettingsRows.emptyAureliaState()
    property var pageRows: []
    property string footerText: "Loading…"
    property bool busy: false
    property bool schemaReady: false
    property bool statusReady: false
    property bool pendingClearConfirm: false
    property bool _rebuildPending: false

    // System settings backend (power/audio/network/time). It is loaded in
    // addition to the Hyprland backend and routed by the "system." id prefix.
    property var hyprSchemas: []
    property var systemSchemas: []
    property var hyprStatusMap: ({})
    property var systemStatusMap: ({})
    property bool systemSchemaReady: false

    // Color picker modal state. The picker itself is presentation-only; the
    // window owns the mutation once a value is accepted.
    property string colorPickerOptionId: ""
    property string colorPickerValue: ""
    property string colorPickerTitle: ""

    readonly property string aureliaRoot: pluginRoot && pluginRoot.aureliaPath ? pluginRoot.aureliaPath : ""
    // Mutable probe targets, computed from pluginRoot.aureliaPath at runtime
    // (Component.onCompleted). Derived readonly bindings are evaluated once,
    // at window construction — before the host injects aureliaPath — and would
    // bake in the dead fallback paths forever.
    property string checkoutBackendPath: "/nonexistent-checkout-bin"
    property string candidateAureliaBin: "/nonexistent-aurelia-bin"
    readonly property string installedBackendPath: "/usr/local/bin/workstation-hypr-settings"

    property bool checkoutBackendAvailable: false
    property bool installedBackendAvailable: false
    // Mutable, set explicitly by the resolution probes. (A readonly JS-block
    // property would be evaluated once at creation — before the probes finish
    // — and could bake in a dead fallback path forever.)
    property string backendBin: "/usr/local/bin/workstation-hypr-settings"
    property bool checkoutAureliaAvailable: false
    property string aureliaBinDir: "/usr/local/bin"

    property string systemBackendBin: "/usr/local/bin/workstation-system-settings"
    property bool systemBackendAvailable: false
    property string aiBin: "/usr/local/bin/workstation-ai"
    property bool aiBackendAvailable: false

    function helperBin(name) {
        return aureliaBinDir + "/" + name
    }

    // Resolve the app-defaults CLI: checkout sibling when running from the
    // repository, otherwise /usr/local/bin, otherwise PATH.
    function resolveDefaultsCli() {
        var override = Quickshell.env("WORKSTATION_APP_DEFAULTS_BIN") || ""
        if (override.indexOf("/") === 0) return override
        var shellRoot = pluginRoot && pluginRoot.aureliaPath ? pluginRoot.aureliaPath : ""
        if (shellRoot.indexOf("/") === 0) {
            return shellRoot + "/../bin/workstation-app-defaults"
        }
        return "/usr/local/bin/workstation-app-defaults"
    }

    readonly property var backendEnvironment: makeEnvironment()
    function makeEnvironment() {
        var env = {
            "PATH": "/usr/local/bin:/usr/bin:/bin" + (Quickshell.env("PATH") ? ":" + Quickshell.env("PATH") : "")
        }
        var override = Quickshell.env("WORKSTATION_HYPR_SETTINGS_BIN") || ""
        if (override.indexOf("/") === 0) env["WORKSTATION_HYPR_SETTINGS_BIN"] = override
        return env
    }

    // ------------------------------------------------------------------
    // Resolution probes
    // ------------------------------------------------------------------
    Process {
        id: checkoutProbe
        command: [] // set at runtime in Component.onCompleted with resolved paths
        onExited: function(code) {
            root.checkoutBackendAvailable = (code === 0)
            var override = Quickshell.env("WORKSTATION_HYPR_SETTINGS_BIN") || ""
            if (override.indexOf("/") === 0) {
                root.backendBin = override
                aureliaBinProbe.command = ["/usr/bin/test", "-d", root.candidateAureliaBin]
                aureliaBinProbe.running = true
                return
            }
            if (code === 0) {
                root.backendBin = root.checkoutBackendPath
                aureliaBinProbe.command = ["/usr/bin/test", "-d", root.candidateAureliaBin]
                aureliaBinProbe.running = true
                return
            }
            installedProbe.command = ["/usr/bin/test", "-x", root.installedBackendPath]
            installedProbe.running = true
        }
    }

    Process {
        id: installedProbe
        command: []
        onExited: function(code) {
            root.installedBackendAvailable = (code === 0)
            if (code === 0) root.backendBin = root.installedBackendPath
            aureliaBinProbe.command = ["/usr/bin/test", "-d", root.candidateAureliaBin]
            aureliaBinProbe.running = true
        }
    }

    Process {
        id: aureliaBinProbe
        command: []
        onExited: function(code) {
            root.checkoutAureliaAvailable = (code === 0)
            if (code === 0) root.aureliaBinDir = root.candidateAureliaBin
            root.start()
        }
    }

    // ------------------------------------------------------------------
    // Schema + status
    // ------------------------------------------------------------------
    Process {
        id: schemaProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: schemaStdout }
        stderr: StdioCollector { id: schemaStderr }
        onExited: function(code) {
            if (code !== 0) {
                root.footerText = "Cannot load option schema: " + (schemaStderr.text || "backend unavailable").trim()
                return
            }
            try {
                var parsed = JSON.parse(schemaStdout.text || "[]")
                root.hyprSchemas = parsed
                root.schemaReady = true
                root.mergeSchemas()
                // Status was already requested in start() (in parallel with the
                // schema fetch); it owns the footer/readiness text.
            } catch (error) {
                root.footerText = "Option schema returned invalid data."
                console.warn("[SETTINGS] schema_parse_failed")
            }
        }
    }

    Process {
        id: statusProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: statusStdout }
        stderr: StdioCollector { id: statusStderr }
        onExited: function(code) {
            if (code !== 0) {
                root.footerText = "Cannot read live state: " + (statusStderr.text || "hyprctl unavailable").trim()
                return
            }
            try {
                var parsed = JSON.parse(statusStdout.text || "{}")
                var map = {}
                for (var i = 0; i < parsed.options.length; i++) {
                    map[parsed.options[i].id] = parsed.options[i]
                }
                root.hyprStatusMap = map
                root.statusMeta = {
                    hyprctlAvailable: parsed.hyprctlAvailable === true,
                    settingsPath: String(parsed.settingsPath || "")
                }
                root.statusReady = true
                root.applyAureliaPatch({ settingsPath: String(parsed.settingsPath || "") })
                root.footerText = root.statusMeta.hyprctlAvailable
                    ? "Ready — changes apply live"
                    : "Ready — Hyprland not reachable; changes apply on reload"
                root.mergeStatus()
            } catch (error) {
                root.footerText = "Live state returned invalid data."
                console.warn("[SETTINGS] status_parse_failed")
            }
        }
    }

    // ------------------------------------------------------------------
    // System settings backend (bounded, loaded alongside the Hyprland backend)
    // ------------------------------------------------------------------
    Process {
        id: systemProbe
        command: []
        onExited: function(code) {
            root.systemBackendAvailable = (code === 0)
            if (code !== 0) return
            systemSchemaProcess.command = [root.systemBackendBin, "schema"]
            systemSchemaProcess.running = true
        }
    }

    Process {
        id: systemSchemaProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: systemSchemaStdout }
        stderr: StdioCollector { id: systemSchemaStderr }
        onExited: function(code) {
            if (code !== 0) {
                console.warn("[SETTINGS] system_schema_unavailable")
                return
            }
            try {
                root.systemSchemas = JSON.parse(systemSchemaStdout.text || "[]")
                root.systemSchemaReady = true
                root.mergeSchemas()
                root.refreshSystemStatus()
            } catch (error) {
                console.warn("[SETTINGS] system_schema_parse_failed")
            }
        }
    }

    Process {
        id: systemStatusProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: systemStatusStdout }
        stderr: StdioCollector { id: systemStatusStderr }
        onExited: function(code) {
            if (code !== 0) {
                console.warn("[SETTINGS] system_status_unavailable")
                return
            }
            try {
                var parsed = JSON.parse(systemStatusStdout.text || "{}")
                var map = {}
                if (Array.isArray(parsed.options)) {
                    for (var i = 0; i < parsed.options.length; i++) {
                        map[parsed.options[i].id] = parsed.options[i]
                    }
                }
                root.systemStatusMap = map
                root.mergeStatus()
            } catch (error) {
                console.warn("[SETTINGS] system_status_parse_failed")
            }
        }
    }

    // ------------------------------------------------------------------
    // AI agent backend (bounded; detects and launches, never installs)
    // ------------------------------------------------------------------
    Process {
        id: aiProbe
        command: []
        onExited: function(code) {
            root.aiBackendAvailable = (code === 0)
            if (code === 0) root.refreshAi()
        }
    }

    Process {
        id: aiAgentsProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: aiAgentsStdout }
        onExited: function(code) {
            if (code !== 0) {
                console.warn("[SETTINGS] ai_agents_unavailable")
                return
            }
            try {
                var parsed = JSON.parse(aiAgentsStdout.text || "{}")
                var base = root.aureliaState.ai || {}
                root.applyAureliaPatch({
                    ai: {
                        default: parsed.default !== undefined ? parsed.default : null,
                        agents: Array.isArray(parsed.agents) ? parsed.agents : [],
                        subscriptions: base.subscriptions || {},
                        usageAgents: base.usageAgents || []
                    }
                })
                aiSubscriptionProcess.command = [root.aiBin, "subscription", "list", "--json"]
                aiSubscriptionProcess.running = true
            } catch (error) {
                console.warn("[SETTINGS] ai_agents_parse_failed")
            }
        }
    }

    Process {
        id: aiSubscriptionProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: aiSubscriptionStdout }
        onExited: function(code) {
            var subs = {}
            if (code === 0) {
                try { subs = JSON.parse(aiSubscriptionStdout.text || "{}") } catch (error) {
                    console.warn("[SETTINGS] ai_subscription_parse_failed")
                    subs = {}
                }
            }
            var base = root.aureliaState.ai || {}
            root.applyAureliaPatch({
                ai: {
                    default: base.default !== undefined ? base.default : null,
                    agents: base.agents || [],
                    subscriptions: subs,
                    usageAgents: base.usageAgents || []
                }
            })
            aiUsageProcess.command = [root.aiBin, "usage"]
            aiUsageProcess.running = true
        }
    }

    Process {
        id: aiUsageProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: aiUsageStdout }
        onExited: function(code) {
            var ids = []
            if (code === 0) {
                try {
                    var parsed = JSON.parse(aiUsageStdout.text || "{}")
                    var agents = Array.isArray(parsed.agents) ? parsed.agents : []
                    for (var i = 0; i < agents.length; i++) {
                        if (agents[i] && agents[i].detected === true && agents[i].id)
                            ids.push(String(agents[i].id))
                    }
                } catch (error) {
                    console.warn("[SETTINGS] ai_usage_parse_failed")
                    ids = []
                }
            }
            var base = root.aureliaState.ai || {}
            root.applyAureliaPatch({
                ai: {
                    default: base.default !== undefined ? base.default : null,
                    agents: base.agents || [],
                    subscriptions: base.subscriptions || {},
                    usageAgents: ids
                }
            })
        }
    }

    Process {
        id: aiLaunchProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stderr: StdioCollector { id: aiLaunchStderr }
        onExited: function(code) {
            root.footerText = code === 0
                ? "Agent launched."
                : "Failed: " + (aiLaunchStderr.text || "launch error").trim()
        }
    }

    // ------------------------------------------------------------------
    // Hyprland mutation backend
    // ------------------------------------------------------------------
    Process {
        id: applyProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: applyStdout }
        stderr: StdioCollector { id: applyStderr }
        onExited: function(code) {
            root.busy = false
            if (code === 0) {
                root.footerText = (applyStdout.text || "Applied.").trim().split("\n")[0]
            } else {
                root.footerText = "Failed: " + (applyStderr.text || "backend error").trim()
            }
            root.refreshStatus()
        }
    }

    // ------------------------------------------------------------------
    // Aurelia helper processes (bounded, one at a time)
    // ------------------------------------------------------------------
    Process {
        id: helperProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: helperStdout }
        stderr: StdioCollector { id: helperStderr }
        onExited: function(code) {
            root.busy = false
            if (code === 0) {
                root.footerText = (helperStdout.text || "Done.").trim().split("\n")[0]
                // Preferences are read by the Theme singleton; reload so a
                // preference change is visible without a shell restart.
                Theme.reloadPreferences()
            } else {
                root.footerText = "Failed: " + (helperStderr.text || "helper error").trim()
            }
            root.refreshAurelia()
        }
    }

    Process {
        id: pingProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        onExited: function(code) {
            root.applyAureliaPatch({ ipcOnline: (code === 0) })
            root.rebuildRows()
        }
    }

    Process {
        id: themeCatalogProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: themeCatalogStdout }
        onExited: function(code) {
            var themes = []
            var current = ""
            if (code === 0) {
                try {
                    var parsed = JSON.parse(themeCatalogStdout.text || "{}")
                    if (parsed && Array.isArray(parsed.themes)) {
                        for (var i = 0; i < parsed.themes.length; i++) {
                            var entry = parsed.themes[i]
                            var name = String(entry.name || entry.id || "")
                            if (name !== "") themes.push({ value: name, label: name })
                        }
                    }
                    if (parsed && parsed.currentTheme) current = String(parsed.currentTheme)
                } catch (error) {
                    console.warn("[SETTINGS] theme_catalog_parse_failed")
                }
            }
            root.applyAureliaPatch({ themes: themes, currentTheme: current })
        }
    }

    Process {
        id: motionProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: motionStdout }
        onExited: function(code) {
            var enabled = true
            var scale = 1
            if (code === 0) {
                var text = motionStdout.text || ""
                var enabledMatch = /enabled=(\w+)/.exec(text)
                var scaleMatch = /scale=([0-9.]+)/.exec(text)
                if (enabledMatch) enabled = enabledMatch[1] === "true"
                if (scaleMatch) scale = Number(scaleMatch[1])
            }
            root.applyAureliaPatch({ motionEnabled: enabled, motionScale: scale })
        }
    }

    Process {
        id: textSizeProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: textSizeStdout }
        onExited: function(code) {
            var size = 12
            if (code === 0) {
                var match = /([0-9]+)/.exec(textSizeStdout.text || "")
                if (match) {
                    var parsed = Number(match[1])
                    if (parsed >= 9 && parsed <= 20) size = parsed
                }
            }
            root.applyAureliaPatch({ textSize: size })
        }
    }

    Process {
        id: aureliaPrefsProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: aureliaPrefsStdout }
        onExited: function(code) {
            var lines = code === 0 ? String(aureliaPrefsStdout.text || "").split("\n") : []
            var format = String(lines[0] || "").trim()
            var hour24 = String(lines[1] || "").trim() === "true"
            var seconds = String(lines[2] || "").trim() === "true"
            var weekStart = String(lines[3] || "").trim()
            // Missing output (backend unavailable) fails safe to the default
            // in-use-only overview rather than silently widening the scope.
            var onlyWorkspacesInUse = String(lines[4] || "").trim() !== "false"
            if (format === "") format = "month_day_weekday_time"
            if (weekStart !== "monday") weekStart = "sunday"
            root.applyAureliaPatch({
                clockFormat: format,
                clockHour24: hour24,
                clockSeconds: seconds,
                weekStart: weekStart,
                onlyWorkspacesInUse: onlyWorkspacesInUse
            })
        }
    }

    // Dedicated reader for the persisted bar-hidden state. This used to share
    // the process that now serves defaults; it patches barHidden ONLY on a
    // successful hidden|visible read so an unreadable result can never make
    // the Bar Hidden toggle lie about the real state.
    Process {
        id: barHiddenProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: barHiddenStdout; waitForEnd: true }
        stderr: StdioCollector { id: barHiddenStderr; waitForEnd: true }
        onExited: function(code) {
            var state = String(barHiddenStdout.text || "").trim()
            if (code === 0 && (state === "hidden" || state === "visible")) {
                root.applyAureliaPatch({ barHidden: state === "hidden" })
            } else {
                // Bounded warning: never echo unbounded reader output.
                var detail = String(barHiddenStderr.text || "").trim()
                if (detail.length > 120) detail = detail.slice(0, 120)
                console.warn("[SETTINGS] bar_hidden_read_failed code=" + code +
                    " detail=" + (detail || "unreadable"))
            }
        }
    }

    Process {
        id: defaultsStatusProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: defaultsStatusStdout }
        onExited: function(code) {
            var currents = {}
            if (code === 0) {
                try {
                    var parsed = JSON.parse(defaultsStatusStdout.text || "{\"roles\":[]}")
                    if (parsed && Array.isArray(parsed.roles)) {
                        for (var i = 0; i < parsed.roles.length; i++) {
                            currents[parsed.roles[i].role] = String(parsed.roles[i].current || "")
                        }
                    }
                } catch (error) { console.warn("[SETTINGS] defaults_status_parse_failed") }
            }
            root.applyDefaultsPatch({ currents: currents })
        }
    }

    Process {
        id: defaultsChoicesProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: defaultsChoicesStdout }
        onExited: function(code) {
            var choices = {}
            if (code === 0) {
                try {
                    var parsed = JSON.parse(defaultsChoicesStdout.text || "{}")
                    if (parsed && typeof parsed === "object") {
                        for (var role in parsed) {
                            if (Array.isArray(parsed[role])) choices[role] = parsed[role]
                        }
                    }
                } catch (error) { console.warn("[SETTINGS] defaults_choices_parse_failed") }
            }
            root.applyDefaultsPatch({ choices: choices })
        }
    }

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------
    property bool probeStarted: false

    // Recompute probe targets from the injected plugin root and start the
    // probe chain. Called on construction and whenever the window is opened,
    // so resolution self-heals regardless of host injection timing.
    function resolveNow() {
        var shellRoot = (pluginRoot && pluginRoot.aureliaPath) ? pluginRoot.aureliaPath : ""
        // At construction the host may not have injected the plugin source
        // root yet; resolution self-heals on the next open. Only warn when a
        // VISIBLE attempt cannot resolve the checkout/installed backend.
        if (shellRoot.indexOf("/") === 0) {
            checkoutBackendPath = shellRoot + "/../bin/workstation-hypr-settings"
            candidateAureliaBin = shellRoot + "/bin"
        }
        if (probeStarted || checkoutBackendPath === "/nonexistent-checkout-bin") {
            // Already resolved in a previous open: refresh live state.
            if (probeStarted && checkoutBackendPath.indexOf("/") === 0) refreshStatus()
            return
        }
        probeStarted = true
        checkoutProbe.command = ["/usr/bin/test", "-x", checkoutBackendPath]
        checkoutProbe.running = true
    }

    Component.onCompleted: {
        resolveNow()
    }

    function start() {
        // Derive the system backend from the resolved Hyprland backend so both
        // resolve from the same root (checkout or /usr/local/bin).
        root.systemBackendBin = String(root.backendBin).replace(
            /workstation-hypr-settings$/, "workstation-system-settings")
        systemProbe.command = ["/usr/bin/test", "-x", root.systemBackendBin]
        systemProbe.running = true
        root.aiBin = String(root.backendBin).replace(
            /workstation-hypr-settings$/, "workstation-ai")
        aiProbe.command = ["/usr/bin/test", "-x", root.aiBin]
        aiProbe.running = true
        schemaProcess.command = [root.backendBin, "schema"]
        schemaProcess.running = true
        // Fetch live state in parallel with the schema; both are independent
        // reads, so the opening surface waits for the slower one, not the sum.
        refreshStatus()
        pingProcess.command = [root.helperBin("aurelia-shell"), "shell", "ping"]
        pingProcess.running = true
        refreshAurelia()
    }

    function refreshStatus() {
        // Never run with the unresolved fallback path: only query once a real
        // backend is confirmed (probes complete with checkout or installed).
        if ((checkoutBackendAvailable || installedBackendAvailable) &&
            !(backendBin === "/usr/local/bin/workstation-hypr-settings" && !installedBackendAvailable)) {
            statusProcess.command = [root.backendBin, "status"]
            statusProcess.running = true
        }
        root.refreshSystemStatus()
    }

    function refreshAurelia() {
        refreshDefaults()
        loadAureliaThemes()
        root.applyAureliaPatch({ activeWindowDisplayMode: root.readActiveWindowDisplayMode() })
        motionProcess.command = [root.helperBin("workstation-aurelia"), "motion", "status"]
        motionProcess.running = true
        textSizeProcess.command = [root.helperBin("aurelia-display-text-size")]
        textSizeProcess.running = true
        aureliaPrefsProcess.command = ["/usr/bin/sh", "-c",
            "\"$1\" preference get aurelia.clock.format; " +
            "\"$1\" preference get aurelia.clock.hour24; " +
            "\"$1\" preference get aurelia.clock.seconds; " +
            "\"$1\" preference get aurelia.calendar.week_start; " +
            "\"$1\" preference get aurelia.workspaces.only_in_use",
            "settings", root.helperBin("workstation-aurelia")]
        aureliaPrefsProcess.running = true
        barHiddenProcess.command = [root.helperBin("aurelia-bar-hidden"), "read"]
        barHiddenProcess.running = true
        root.refreshAi()
    }

    // Effective active-window display mode read straight from the registry's
    // manifest-default overlay (read-only; the hub never mutates config). Any
    // value that is not an explicit "title" reports the "app" default, which
    // matches the widget's own fail-closed normalization.
    function readActiveWindowDisplayMode() {
        var registry = pluginRoot ? pluginRoot.pluginRegistry : null
        var settings = registry && typeof registry.settingsForEntry === "function"
            ? registry.settingsForEntry("aurelia.active-window", {}) : null
        var mode = settings && settings.displayMode !== undefined
            ? String(settings.displayMode).toLowerCase() : ""
        return mode === "title" ? "title" : "app"
    }

    function refreshAi() {
        if (!root.aiBackendAvailable) return
        aiAgentsProcess.command = [root.aiBin, "agents"]
        aiAgentsProcess.running = true
    }

    function applyAiOption(optionId, value) {
        if (optionId === "ai.default") {
            runHelper([root.aiBin, "set", String(value)], "Setting default agent…")
            return
        }
        var prefix = "ai.subscription."
        if (String(optionId).indexOf(prefix) === 0) {
            var parts = String(optionId).slice(prefix.length).split(".")
            if (parts.length === 2 && parts[0] !== "" && parts[1] !== "") {
                runHelper([root.aiBin, "subscription", "set", parts[0], parts[1], String(value)],
                    "Saving subscription…")
            }
        }
    }

    function launchAgent() {
        if (!root.aiBackendAvailable) return
        root.footerText = "Launching default agent…"
        aiLaunchProcess.command = [root.aiBin, "launch"]
        aiLaunchProcess.running = true
    }

    function loadAureliaThemes() {
        themeCatalogProcess.command = [root.helperBin("aurelia-theme"), "catalog", "--json"]
        themeCatalogProcess.running = true
    }

    // Single authoritative key list. Both patchers route through it so a new
    // field can never be dropped when one patcher rebuilds the state (which
    // is what emptied the AI/defaults dropdowns).
    readonly property var aureliaStateKeys: ["ipcOnline", "themes", "currentTheme",
        "motionEnabled", "motionScale", "textSize", "barHidden",
        "activeWindowDisplayMode", "weekStart",
        "clockFormat", "clockHour24", "clockSeconds", "onlyWorkspacesInUse",
        "defaults", "ai", "settingsPath"]

    function applyAureliaPatch(patch) {
        var next = {}
        var keys = root.aureliaStateKeys
        for (var i = 0; i < keys.length; i++) {
            next[keys[i]] = keys[i] in patch ? patch[keys[i]] : root.aureliaState[keys[i]]
        }
        root.aureliaState = next // new object so onAureliaStateChanged fires
    }

    // Defaults (workstation-app-defaults CLI; bounded status + choices queries).
    property var defaultsState: ({ currents: {}, choices: {}, ready: false })

    function refreshDefaults() {
        defaultsStatusProcess.command = [root.resolveDefaultsCli(), "status"]
        defaultsStatusProcess.running = true
        defaultsChoicesProcess.command = [root.resolveDefaultsCli(), "choices"]
        defaultsChoicesProcess.running = true
    }

    function applyDefaultsPatch(patch) {
        // keep rows reactive: new objects all the way down
        var next = { currents: {}, choices: {}, ready: true }
        var k
        for (k in root.defaultsState.currents) next.currents[k] = root.defaultsState.currents[k]
        for (k in root.defaultsState.choices) next.choices[k] = root.defaultsState.choices[k]
        if (patch.currents) {
            for (k in patch.currents) next.currents[k] = patch.currents[k]
        }
        if (patch.choices) {
            for (k in patch.choices) next.choices[k] = patch.choices[k]
        }
        root.defaultsState = next
        root.applyAureliaPatch({ defaults: root.defaultsState })
    }

    function applyDefaultsOption(optionId, value) {
        var role = String(optionId).slice("defaults.".length)
        if (role === "") return
        if (String(value) === "") {
            runHelper([root.resolveDefaultsCli(), "reset", role], "Resetting " + role + "…")
        } else {
            runHelper([root.resolveDefaultsCli(), "set", role, String(value)], "Setting " + role + "…")
        }
    }

    // ------------------------------------------------------------------
    // User intent
    // ------------------------------------------------------------------
    function applyOption(optionId, value) {
        if (optionId === "" || busy) return
        // System and Hyprland backends load independently; apply once the
        // owning backend's schema is ready.
        var ready = SettingsBackends.isSystemOption(optionId) ? root.systemSchemaReady : root.schemaReady
        if (!ready) return
        busy = true
        footerText = "Applying " + optionId + " …"
        applyProcess.command = [
            SettingsBackends.backendFor(optionId, root.backendBin, root.systemBackendBin),
            "set", optionId, String(value)]
        applyProcess.running = true
    }

    function applyAureliaOption(optionId, value) {
        switch (optionId) {
        case "aurelia.theme":
            runHelper([root.helperBin("aurelia-theme"), "set", String(value)], "Setting theme…")
            break
        case "aurelia.motion.enabled":
            runHelper([root.helperBin("workstation-aurelia"), "motion", value ? "enable" : "disable"], "Setting motion…")
            break
        case "aurelia.motion.scale":
            runHelper([root.helperBin("workstation-aurelia"), "motion", "scale", String(value)], "Setting motion scale…")
            break
        case "aurelia.display.textSize":
            runHelper([root.helperBin("aurelia-display-text-size"), String(Math.round(value))], "Setting text size…")
            break
        case "aurelia.bar":
            runHelper([root.helperBin("aurelia-bar-hidden"), value ? "on" : "off"], "Toggling bar…")
            break
        case "aurelia.active-window.displayMode":
            runHelper([root.helperBin("aurelia-bar"), "set", "aurelia.active-window",
                       "displayMode", String(value)], "Setting active window display…")
            break
        case "aurelia.calendar.weekStart":
            runHelper([root.helperBin("workstation-aurelia"), "preference", "set",
                       "aurelia.calendar.week_start", String(value)], "Setting week start…")
            break
        case "aurelia.clock.format":
            runHelper([root.helperBin("workstation-aurelia"), "preference", "set",
                       "aurelia.clock.format", String(value)], "Setting clock format…")
            break
        case "aurelia.clock.hour24":
            runHelper([root.helperBin("workstation-aurelia"), "preference", "set",
                       "aurelia.clock.hour24", value ? "true" : "false"], "Setting hour format…")
            break
        case "aurelia.clock.seconds":
            runHelper([root.helperBin("workstation-aurelia"), "preference", "set",
                       "aurelia.clock.seconds", value ? "true" : "false"], "Setting clock seconds…")
            break
        case "aurelia.workspaces.only_in_use":
            runHelper([root.helperBin("workstation-aurelia"), "preference", "set",
                       "aurelia.workspaces.only_in_use", value ? "true" : "false"], "Setting workspace overview…")
            break
        default:
            console.warn("[SETTINGS] unknown aurelia option: " + optionId)
        }
    }

    function runAction(actionId) {
        switch (actionId) {
        case "openThemePanel":
            if (pluginRoot && pluginRoot.shell && typeof pluginRoot.shell.summon === "function") {
                pluginRoot.shell.summon("aurelia.theme", "{}")
            }
            break
        case "openKeybindings":
            if (pluginRoot && pluginRoot.shell && typeof pluginRoot.shell.toggle === "function") {
                pluginRoot.shell.toggle("aurelia.keybindings", "{}")
            }
            break
        case "openNetworkPanel":
            if (pluginRoot && pluginRoot.shell && typeof pluginRoot.shell.toggle === "function") {
                pluginRoot.shell.toggle("aurelia.network", "{}")
            }
            break
        case "launchAgent":
            root.launchAgent()
            break
        case "installSkill":
            runHelper([root.aiBin, "skill", "install"], "Installing workstation skill…")
            break
        case "removeSkill":
            runHelper([root.aiBin, "skill", "remove"], "Removing workstation skill…")
            break
        case "resetSection":
            clearAllOverrides()
            break
        default:
            console.warn("[SETTINGS] unknown action: " + actionId)
        }
    }

    function clearAllOverrides() {
        if (busy) return
        if (!pendingClearConfirm) {
            pendingClearConfirm = true
            footerText = "Confirm: click Clear all once more, or press Esc to cancel."
            return
        }
        pendingClearConfirm = false
        busy = true
        footerText = "Clearing all Hyprland overrides…"
        applyProcess.command = [root.backendBin, "clear"]
        applyProcess.running = true
    }

    function runHelper(argv, message) {
        if (busy) return
        busy = true
        footerText = message
        helperProcess.command = argv
        helperProcess.running = true
    }

    // ------------------------------------------------------------------
    // Color picker
    // ------------------------------------------------------------------
    function openColorPicker(optionId, value, title) {
        root.colorPickerValue = String(value || "")
        root.colorPickerTitle = String(title || "Color")
        root.colorPickerOptionId = String(optionId || "")
        colorPicker.openWith(root.colorPickerValue)
    }

    function closeColorPicker() {
        root.colorPickerOptionId = ""
    }

    function applyColorPicker(value) {
        var optionId = root.colorPickerOptionId
        root.closeColorPicker()
        if (optionId === "") return
        if (String(optionId).indexOf("aurelia.") === 0) {
            root.applyAureliaOption(optionId, value)
        } else {
            root.applyOption(optionId, value)
        }
    }

    // ------------------------------------------------------------------
    // Page projection
    // ------------------------------------------------------------------
    function mergeSchemas() {
        var all = SettingsBackends.mergeSchemas(root.hyprSchemas, root.systemSchemas)
        root.schemas = all
        root.schemaMap = SettingsBackends.schemaMap(all)
        root.rebuildRows()
    }

    function mergeStatus() {
        root.statusMap = SettingsBackends.mergeStatusMaps(root.hyprStatusMap, root.systemStatusMap)
        root.rebuildRows()
    }

    function refreshSystemStatus() {
        if (!root.systemBackendAvailable || !root.systemSchemaReady) return
        systemStatusProcess.command = [root.systemBackendBin, "status"]
        systemStatusProcess.running = true
    }

    function rebuildRows() {
        // Coalesce bursts of updates (schema/status/preferences all arrive
        // during open) into a single model reset; each reset rebuilds every
        // delegate, so resetting the list several times on open was both slow
        // and visibly flickery.
        if (!schemaReady || _rebuildPending) return
        _rebuildPending = true
        Qt.callLater(function() {
            root._rebuildPending = false
            if (!root.schemaReady) return
            root.pageRows = SettingsRows.buildRows(root.activeSection, root.schemas, root.statusMap, root.aureliaState)
        })
    }

    onActiveSectionChanged: rebuildRows()
    // Any state change (AI list, defaults choices, clock/week preferences) must
    // refresh the projected rows; without this the dropdowns stayed empty when
    // their data arrived after the initial rebuild.
    onAureliaStateChanged: rebuildRows()

    function kindFor(optionId) {
        var schema = root.schemaMap[optionId]
        return schema ? schema.type : ""
    }

    // ------------------------------------------------------------------
    // UI
    // ------------------------------------------------------------------
    // Dimmed backdrop: centered card over the desktop; clicking outside
    // closes (mirrors the keybindings palette interaction).
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        z: 0

        MouseArea {
            anchors.fill: parent
            onClicked: root.requestClose()
        }
    }

    // Centered chrome card (~60% width, ~76% height).
    Rectangle {
        id: chrome
        anchors.centerIn: parent
        width: Math.round(parent ? parent.width * 0.57 : 960)
        height: Math.round(parent ? parent.height * 0.76 : 680)
        radius: Theme.radiusLg
        color: Theme.popups.background
        border.width: Theme.borderWidthDefault
        border.color: Theme.popups.border
        z: 1
        focus: true
        clip: true

        // Click shield: blocks every click on the card (empty areas, rows)
        // from falling through to the close-on-outside scrim; real controls
        // (switches, combos, text fields) sit above this shield.
        MouseArea {
            anchors.fill: parent
            z: 0
            acceptedButtons: Qt.AllButtons
            preventStealing: true
            onClicked: {}
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (root.colorPickerOptionId !== "") {
                    root.closeColorPicker()
                } else if (root.pendingClearConfirm) {
                    root.pendingClearConfirm = false
                    root.footerText = "Cancelled."
                } else {
                    root.requestClose()
                }
                event.accepted = true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingLg
            spacing: 0
            z: 1 // above the click shield

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMd

                Rectangle {
                    width: 8
                    height: 22
                    radius: 3
                    color: Theme.accent
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    Text {
                        text: "Settings"
                        color: Theme.text
                        font.family: Theme.fontFamilyResolved
                        font.pixelSize: Theme.fontSizeXl
                        font.weight: Font.Bold
                    }

                    Text {
                        text: root.activeSection === "aurelia"
                            ? "Hyprland + Aurelia Shell desktop settings"
                            : "Hyprland desktop settings"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeSm
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    radius: Theme.radiusMd
                    color: root.statusReady
                        ? (root.statusMeta.hyprctlAvailable ? Theme.success : Theme.warning)
                        : Theme.textSubtle
                    width: 8
                    height: 8
                }

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.statusReady
                        ? (root.statusMeta.hyprctlAvailable ? "Live" : "Persisted only")
                        : "…"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamilyResolved
                    font.pixelSize: Theme.fontSizeXs
                }

                SettingButton {
                    compact: true
                    label: "\u2715"
                    onClicked: root.requestClose()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingMd
                Layout.bottomMargin: Theme.spacingMd
                height: 1
                color: Theme.border
            }

            // Body
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.spacingLg

                SettingsNav {
                    Layout.preferredWidth: 210
                    Layout.fillHeight: true
                    sections: root.sections
                    activeId: root.activeSection
                    onSelectSection: function(sectionId) {
                        if (root.pendingClearConfirm) root.pendingClearConfirm = false
                        root.activeSection = sectionId
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.maximumWidth: 1
                    Layout.fillHeight: true
                    color: Theme.border
                }

                SettingsPage {
                    id: page
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    rows: root.pageRows
                    onChanged: function(optionId, value) {
                        if (String(optionId).indexOf("aurelia.") === 0) {
                            root.applyAureliaOption(optionId, value)
                        } else if (String(optionId).indexOf("defaults.") === 0) {
                            root.applyDefaultsOption(optionId, value)
                        } else if (String(optionId).indexOf("ai.") === 0) {
                            root.applyAiOption(optionId, value)
                        } else {
                            root.applyOption(optionId, value)
                        }
                    }
                    onAction: function(actionId) {
                        root.runAction(actionId)
                    }
                    onColorPickerRequested: function(optionId, value, title) {
                        root.openColorPicker(optionId, value, title)
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingMd
                Layout.bottomMargin: Theme.spacingMd
                height: 1
                color: Theme.border
            }

            // Footer
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMd

                Text {
                    Layout.fillWidth: true
                    text: root.footerText
                    color: root.busy ? Theme.warning : (root.pendingClearConfirm ? Theme.warning : Theme.textMuted)
                    font.family: Theme.fontFamilyResolved
                    font.pixelSize: Theme.fontSizeXs
                    elide: Text.ElideRight
                }

                Text {
                    text: "Esc closes"
                    color: Theme.textSubtle
                    font.family: Theme.fontFamilyResolved
                    font.pixelSize: Theme.fontSizeXs
                }
            }
        }

        // Opening state: a centered 'Opening Settings…' surface over the
        // chrome; revealed only until schema + live state are ready. Sibling
        // of the layout (never a layout-managed item).
        Rectangle {
            id: openingSurface
            anchors.fill: parent
            radius: Theme.radiusLg
            color: Theme.popups.background
            visible: !(root.schemaReady && root.statusReady)
            z: 20

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Theme.spacingMd

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.busy ? "Opening Settings…" : "Reading current settings…"
                    color: Theme.text
                    font.family: Theme.fontFamilyResolved
                    font.pixelSize: Theme.fontSizeLg
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.footerText
                    color: Theme.textSecondary
                    font.family: Theme.fontFamilyProse
                    font.pixelSize: Theme.fontSizeXs
                    elide: Text.ElideRight
                    Layout.maximumWidth: 360
                }
            }
        }

        // Color picker: a modal overlay centered over the whole card. It is a
        // sibling of the layout (never layout-managed), so it can cover the
        // rows without changing their fixed heights.
        Rectangle {
            id: colorPickerScrim
            anchors.fill: parent
            radius: Theme.radiusLg
            color: Qt.rgba(0, 0, 0, 0.45)
            visible: root.colorPickerOptionId !== ""
            z: 25

            MouseArea {
                anchors.fill: parent
                onClicked: root.closeColorPicker()
            }
        }

        ColorPicker {
            id: colorPicker
            anchors.centerIn: parent
            visible: root.colorPickerOptionId !== ""
            z: 26
            title: root.colorPickerTitle
            onAccepted: function(value) { root.applyColorPicker(value) }
            onCancelled: root.closeColorPicker()
        }
    }

    onVisibleChanged: {
        if (visible) {
            pendingClearConfirm = false
            resolveNow()
            chrome.forceActiveFocus()
            // refreshStatus() runs after backend probes finish (start()), so
            // the status call never races the resolvers.
        }
    }
}
