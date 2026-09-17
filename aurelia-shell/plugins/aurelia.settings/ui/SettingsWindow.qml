import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "SettingsRows.js" as SettingsRows
import "../../../theme"

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

    readonly property string aureliaRoot: pluginRoot && pluginRoot.aureliaPath ? pluginRoot.aureliaPath : ""
    readonly property string checkoutBackendPath: aureliaRoot.indexOf("/") === 0
        ? aureliaRoot + "/../bin/workstation-hypr-settings" : "/nonexistent-checkout-bin"
    readonly property string installedBackendPath: "/usr/local/bin/workstation-hypr-settings"
    readonly property string candidateAureliaBin: aureliaRoot.indexOf("/") === 0
        ? aureliaRoot + "/bin" : "/nonexistent-aurelia-bin"

    property bool checkoutBackendAvailable: false
    property bool installedBackendAvailable: false
    readonly property string backendBin: {
        var override = Quickshell.env("WORKSTATION_HYPR_SETTINGS_BIN") || ""
        if (override.indexOf("/") === 0) return override
        if (checkoutBackendAvailable) return checkoutBackendPath
        if (installedBackendAvailable) return installedBackendPath
        return installedBackendPath
    }
    property bool checkoutAureliaAvailable: false
    readonly property string aureliaBinDir: checkoutAureliaAvailable ? candidateAureliaBin : "/usr/local/bin"

    function helperBin(name) {
        return aureliaBinDir + "/" + name
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
        command: ["/usr/bin/test", "-x", root.checkoutBackendPath]
        onExited: function(code) {
            root.checkoutBackendAvailable = (code === 0)
            installedProbe.command = ["/usr/bin/test", "-x", root.installedBackendPath]
            installedProbe.running = true
        }
    }

    Process {
        id: installedProbe
        command: []
        onExited: function(code) {
            root.installedBackendAvailable = (code === 0)
            aureliaBinProbe.command = ["/usr/bin/test", "-d", root.candidateAureliaBin]
            aureliaBinProbe.running = true
        }
    }

    Process {
        id: aureliaBinProbe
        command: []
        onExited: function(code) {
            root.checkoutAureliaAvailable = (code === 0)
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
                var map = {}
                for (var i = 0; i < parsed.length; i++) map[parsed[i].id] = parsed[i]
                root.schemas = parsed
                root.schemaMap = map
                root.schemaReady = true
                root.footerText = "Loading live state…"
                root.refreshStatus()
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
                root.statusMap = map
                root.statusMeta = {
                    hyprctlAvailable: parsed.hyprctlAvailable === true,
                    settingsPath: String(parsed.settingsPath || "")
                }
                root.statusReady = true
                root.applyAureliaPatch({ settingsPath: String(parsed.settingsPath || "") })
                root.footerText = root.statusMeta.hyprctlAvailable
                    ? "Ready — changes apply live"
                    : "Ready — Hyprland not reachable; changes apply on reload"
                root.rebuildRows()
            } catch (error) {
                root.footerText = "Live state returned invalid data."
                console.warn("[SETTINGS] status_parse_failed")
            }
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
        id: barProcess
        command: []
        environment: root.backendEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: barStdout }
        onExited: function(code) {
            var hidden = false
            if (code === 0) {
                var text = (barStdout.text || "").trim()
                hidden = (text === "hidden")
            }
            root.applyAureliaPatch({ barHidden: hidden })
        }
    }

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------
    Component.onCompleted: {
        checkoutProbe.command = ["/usr/bin/test", "-x", root.checkoutBackendPath]
        checkoutProbe.running = true
    }

    function start() {
        schemaProcess.command = [root.backendBin, "schema"]
        schemaProcess.running = true
        pingProcess.command = [root.helperBin("aurelia-shell"), "shell", "ping"]
        pingProcess.running = true
        refreshAurelia()
    }

    function refreshStatus() {
        statusProcess.command = [root.backendBin, "status"]
        statusProcess.running = true
    }

    function refreshAurelia() {
        loadAureliaThemes()
        motionProcess.command = [root.helperBin("workstation-aurelia"), "motion", "status"]
        motionProcess.running = true
        textSizeProcess.command = [root.helperBin("aurelia-display-text-size")]
        textSizeProcess.running = true
        barProcess.command = [root.helperBin("aurelia-bar-hidden"), "read"]
        barProcess.running = true
    }

    function loadAureliaThemes() {
        themeCatalogProcess.command = [root.helperBin("aurelia-theme"), "catalog", "--json"]
        themeCatalogProcess.running = true
    }

    function applyAureliaPatch(patch) {
        var next = {}
        var keys = ["ipcOnline", "themes", "currentTheme", "motionEnabled", "motionScale",
                    "textSize", "barHidden", "settingsPath"]
        for (var i = 0; i < keys.length; i++) {
            next[keys[i]] = keys[i] in patch ? patch[keys[i]] : root.aureliaState[keys[i]]
        }
        root.aureliaState = next // new object so onAureliaStateChanged fires
    }

    // ------------------------------------------------------------------
    // User intent
    // ------------------------------------------------------------------
    function applyOption(optionId, value) {
        if (!schemaReady || optionId === "" || busy) return
        busy = true
        footerText = "Applying " + optionId + " …"
        applyProcess.command = [root.backendBin, "set", optionId, String(value)]
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
    // Page projection
    // ------------------------------------------------------------------
    function rebuildRows() {
        if (!schemaReady) return
        pageRows = SettingsRows.buildRows(activeSection, root.schemas, root.statusMap, root.aureliaState)
    }

    onActiveSectionChanged: rebuildRows()

    function kindFor(optionId) {
        var schema = root.schemaMap[optionId]
        return schema ? schema.type : ""
    }

    // ------------------------------------------------------------------
    // UI
    // ------------------------------------------------------------------
    Rectangle {
        id: chrome
        anchors.fill: parent
        anchors.margins: 18
        radius: Theme.radiusLg
        color: Theme.popups.background
        border.width: Theme.borderWidthDefault
        border.color: Theme.popups.border

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingLg
            spacing: 0

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
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXl
                        font.weight: Font.Bold
                    }

                    Text {
                        text: root.activeSection === "aurelia"
                            ? "Hyprland + Aurelia Shell desktop settings"
                            : "Hyprland desktop settings"
                        color: Theme.textMuted
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
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                }

                Button {
                    Layout.alignment: Qt.AlignVCenter
                    text: "\u2715"
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
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    width: 1
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
                        } else {
                            root.applyOption(optionId, value)
                        }
                    }
                    onAction: function(actionId) {
                        root.runAction(actionId)
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
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    elide: Text.ElideRight
                }

                Text {
                    text: "Esc closes"
                    color: Theme.textSubtle
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                }
            }
        }
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            if (root.pendingClearConfirm) {
                root.pendingClearConfirm = false
                root.footerText = "Cancelled."
            } else {
                root.requestClose()
            }
            event.accepted = true
        }
    }

    onVisibleChanged: {
        if (visible) {
            pendingClearConfirm = false
            refreshStatus()
        }
    }
}
