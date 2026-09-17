import QtQuick
import Quickshell
import Quickshell.Io
import "./ui"

// Manifest-backed first-party settings hub plugin.
//
// The host injects the optional environment properties after URL loading; the
// entry point deliberately has safe defaults so construction cannot fail
// before injection. All mutations are delegated to the bounded CLI backends
// (workstation-hypr-settings, aurelia-theme, workstation-aurelia, ...);
// this surface only renders state and forwards user intent.
Item {
    id: pluginRoot

    property string aureliaPath: ""
    property var shell: null
    property var bar: null
    property var manifest: ({})
    property var pluginRegistry: null

    readonly property string pluginId: "aurelia.settings"
    readonly property bool configured: shell !== null && pluginRegistry !== null

    function open(payloadJson) {
        if (bar && typeof bar.requestPopout === "function" && settingsWindow) {
            bar.requestPopout(settingsWindow, "aurelia.settings")
        }
        if (settingsWindow) settingsWindow.visible = true
        return "ok"
    }

    function close() {
        // requestClose is a self-contained window function (visible=false +
        // popout release); it never re-enters this plugin, so the IPC toggle
        // close path cannot recurse.
        if (settingsWindow &&
            typeof settingsWindow.requestClose === "function") {
            settingsWindow.requestClose("plugin-close")
        }
        return "ok"
    }

    function toggle(payloadJson) {
        if (typeof isVisible() === "boolean" && isVisible()) return close()
        return open(payloadJson || "{}")
    }

    function isVisible() {
        return settingsWindow ? settingsWindow.visible : false
    }

    // Plugin-owned IPC target. `aurelia-shell shell toggle aurelia.settings`
    // (the desktop_settings keybinding) reaches this surface.
    IpcHandler {
        target: "aurelia.settings"

        function ping(): bool {
            return settingsWindow !== null
        }

        function open(): void {
            pluginRoot.open("{}")
        }

        function close(): void {
            pluginRoot.close()
        }

        function toggle(): void {
            pluginRoot.toggle("{}")
        }

        function isVisible(): bool {
            return pluginRoot.isVisible()
        }

        function activeSection(): string {
            return settingsWindow ? settingsWindow.activeSection : ""
        }

        function resolve(): string {
            if (settingsWindow && typeof settingsWindow.resolveNow === "function") {
                settingsWindow.resolveNow()
                return "ok"
            }
            return "no-window"
        }

        function debugInfo(): string {
            if (!settingsWindow) return '{"windowReady":false}'
            var w = settingsWindow
            return JSON.stringify({
                windowReady: true,
                aureliaPath: pluginRoot && pluginRoot.aureliaPath ? pluginRoot.aureliaPath : "",
                checkoutBackendPath: w.checkoutBackendPath || "",
                candidateAureliaBin: w.candidateAureliaBin || "",
                checkoutBackendAvailable: !!w.checkoutBackendAvailable,
                installedBackendAvailable: !!w.installedBackendAvailable,
                checkoutAureliaAvailable: !!w.checkoutAureliaAvailable,
                backendBin: w.backendBin || "",
                aureliaBinDir: w.aureliaBinDir || "",
                schemaReady: !!w.schemaReady,
                statusReady: !!w.statusReady,
                rowCount: Array.isArray(w.pageRows) ? w.pageRows.length : -1,
                themeCount: Array.isArray(w.aureliaState && w.aureliaState.themes) ? w.aureliaState.themes.length : -1,
                currentTheme: (w.aureliaState && w.aureliaState.currentTheme) || "",
                activeSection: w.activeSection || "",
                footerText: w.footerText || ""
            })
        }
    }

    SettingsWindow {
        id: settingsWindow
        pluginRoot: pluginRoot
        visible: false
    }
}
