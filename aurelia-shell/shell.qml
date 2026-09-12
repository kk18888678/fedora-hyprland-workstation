import QtQuick
import Quickshell
import Quickshell.Io
import "./services"
import "./theme"

// Aurelia Shell is the resident Quickshell host. It provides shared services,
// plugin discovery, Loader lifecycle, and the stable shell IPC contract. A
// plugin owns its own UI and component IPC; the host does not contain
// keybindings-specific business logic.
ShellRoot {
    id: root

    readonly property string shellVersion: "1.0.0"

    ShellConfig {
        id: shellConfig
    }

    PluginRegistry {
        id: pluginRegistry
        shellConfig: shellConfig
    }

    BarWidgetRegistry {
        id: barWidgetRegistry
        pluginRegistry: pluginRegistry
    }

    AureliaAppLibrary {
        id: aureliaAppLibrary
    }

    PluginHost {
        id: pluginHost
        registry: pluginRegistry
        shellApi: shellIpc
        appLibrary: aureliaAppLibrary
        barWidgetRegistry: barWidgetRegistry
    }

    // Omarchy-style plugin hot reload. Only plugin-owned entry points are
    // reloaded automatically; shell.qml and host services remain explicit
    // restart boundaries so a half-written core tree cannot create a second
    // host generation in the session.
    property bool pluginReloading: false
    property bool pluginReloadPending: false
    property bool fullPluginReloadPending: false
    property bool activeFullPluginReload: false
    property var pendingPluginReloadIds: ({})

    Timer {
        id: localPluginReloadTimer
        interval: 150
        repeat: false
        onTriggered: root.reloadPlugins()
    }

    function queuePluginReload(pluginId) {
        var id = String(pluginId || "").trim()
        if (!id) return
        var next = {}
        for (var existingId in root.pendingPluginReloadIds) next[existingId] = true
        next[id] = true
        root.pendingPluginReloadIds = next
        localPluginReloadTimer.restart()
    }

    function requestFullPluginReload() {
        root.fullPluginReloadPending = true
        return root.reloadPlugins()
    }

    function reloadPlugins() {
        if (root.pluginReloading || pluginRegistry.scanning) {
            root.pluginReloadPending = true
            return "pending"
        }

        var reloadIds = null
        if (!root.fullPluginReloadPending) {
            var ids = Object.keys(root.pendingPluginReloadIds)
            if (ids.length === 0) return "ok"
            reloadIds = {}
            for (var i = 0; i < ids.length; i++) reloadIds[ids[i]] = true
        }
        root.pendingPluginReloadIds = ({})
        root.fullPluginReloadPending = false
        root.pluginReloading = true
        root.activeFullPluginReload = reloadIds === null
        pluginHost.beginReload(reloadIds)
        Qt.callLater(root.finishPluginReload)
        return "ok"
    }

    function finishPluginReload() {
        if (!root.pluginReloading) return
        if (pluginRegistry.scanning) {
            root.pluginReloadPending = true
            return
        }

        // Qt.clearComponentCache() is available in some Qt/QML builds but is
        // not exposed by the Fedora QuickShell runtime. Guard the optional API
        // so a reload cannot strand every resident plugin in reloading state.
        if (typeof Qt.clearComponentCache === "function") Qt.clearComponentCache()
        if (!pluginRegistry.scan()) {
            root.pluginReloadPending = true
            return
        }
    }

    Connections {
        target: pluginRegistry

        function onLocalPluginChanged(pluginId) {
            console.info("[PLUGIN] aurelia.plugin.changed id=" + pluginId)
            root.queuePluginReload(pluginId)
        }

        function onScanFinished() {
            if (root.pluginReloading) {
                root.pluginReloading = false
                pluginHost.finishReload()
                if (root.activeFullPluginReload) {
                    var bar = pluginHost.activeBar()
                    if (bar && typeof bar.reloadWidgets === "function") bar.reloadWidgets()
                }
                root.activeFullPluginReload = false
            }
            if (root.pluginReloadPending || root.fullPluginReloadPending
                || Object.keys(root.pendingPluginReloadIds).length > 0) {
                root.pluginReloadPending = false
                Qt.callLater(root.reloadPlugins)
            }
        }
    }

    IpcHandler {
        id: shellIpc
        target: "shell"

        function ping(): string {
            return pluginRegistry.scanning ? "not-ready" : "ok"
        }

        function summon(pluginId: string, payloadJson: string): string {
            return pluginHost.open(pluginId, payloadJson || "{}")
        }

        function hide(pluginId: string): string {
            return pluginHost.close(pluginId)
        }

        function toggle(pluginId: string, payloadJson: string): string {
            return pluginHost.toggle(pluginId, payloadJson || "{}")
        }

        function call(pluginId: string, method: string, argument: string): string {
            return pluginHost.call(pluginId, method, argument || "")
        }

        function rescanPlugins(): string {
            return root.requestFullPluginReload()
        }

        function reloadConfig(): string {
            shellConfig.reload()
            pluginRegistry.registryRevision++
            pluginRegistry.pluginsChanged()
            return "ok"
        }

        function migrateConfig(): string {
            return shellConfig.migrate()
        }

        function reloadTheme(): string {
            Theme.reloadTheme()
            return "ok"
        }

        // One public theme-application boundary. The resident background owner
        // reloads the palette and wallpaper state together so selectors do not
        // have to race two independent shell calls. Keep reloadTheme above for
        // older callers that only need to refresh palette data.
        function applyTheme(): string {
            var background = pluginHost.itemFor("aurelia.background")
            if (background && typeof background.applyTheme === "function")
                return String(background.applyTheme() || "ok")
            Theme.reloadTheme()
            return "ok"
        }

        function themeStatus(): string {
            return JSON.stringify({
                effectivePath: Theme.effectiveThemePath,
                activePath: Theme.activeThemePath,
                activeAvailable: Theme.activeThemeAvailable,
                overrideAvailable: Theme.themeOverrideAvailable,
                shellPath: Theme.effectiveShellPath,
                shellAvailable: Theme.activeShellAvailable,
                mode: Theme.themeMode,
                background: String(Theme.background),
                surface: String(Theme.surface),
                accent: String(Theme.accent),
                text: String(Theme.text),
                barBackground: String(Theme.bar.background),
                popupBackground: String(Theme.popups.background),
                imagePickerScrim: String(Theme.imagePicker.scrim)
            })
        }

        function barThemeStatus(): string {
            var bar = pluginHost.activeBar()
            if (!bar || typeof bar.themeStatus !== "function") return "not-loaded"
            return bar.themeStatus()
        }

        function setPluginEnabled(pluginId: string, enabled: string): string {
            return pluginRegistry.setPluginEnabled(pluginId, enabled === "true") ? "ok" : (pluginRegistry.lastError || "error")
        }

        function listPlugins(): string {
            return JSON.stringify(pluginHost.summaries())
        }

        function catalogPlugins(): string {
            return JSON.stringify(pluginRegistry.pluginCatalog())
        }
    }

    // Stable compatibility target for existing Hyprland bindings and callers.
    // New callers should use `shell toggle aurelia.keybindings {}`.
    IpcHandler {
        id: keybindingsIpc
        target: "keybindings"

        function ping(): bool {
            return pluginHost.itemFor("aurelia.keybindings") !== null
        }

        function toggle(): void {
            pluginHost.toggle("aurelia.keybindings", "{}")
        }

        function open(): void {
            pluginHost.open("aurelia.keybindings", "{}")
        }

        function close(): void {
            pluginHost.close("aurelia.keybindings")
        }

        function isVisible(): bool {
            return pluginHost.isVisible("aurelia.keybindings")
        }

        function activeView(): string {
            return pluginHost.call("aurelia.keybindings", "activeView", "")
        }

        function revision(): string {
            return pluginHost.call("aurelia.keybindings", "revision", "")
        }
    }

    // Historical target retained as a forwarding alias, never as a second
    // implementation or a second shell process.
    IpcHandler {
        target: "hotkeys"

        function ping(): bool { return keybindingsIpc.ping() }
        function toggle(): void { keybindingsIpc.toggle() }
        function open(): void { keybindingsIpc.open() }
        function close(): void { keybindingsIpc.close() }
        function isVisible(): bool { return keybindingsIpc.isVisible() }
        function activeView(): string { return keybindingsIpc.activeView() }
        function revision(): string { return keybindingsIpc.revision() }
    }

    Component.onCompleted: {
        // Force the Theme singleton to instantiate its lazy file probes during
        // the initial shell start. Without this first read, the shell can
        // remain on the shipped palette until a later theme IPC call.
        Theme.reloadTheme()
        console.info("[PERF] Aurelia Shell resident host ready version=" + root.shellVersion)
    }
}
