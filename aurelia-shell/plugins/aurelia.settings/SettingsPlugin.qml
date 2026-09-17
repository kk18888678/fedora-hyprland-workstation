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
        if (bar && typeof bar.requestPopout === "function" && settingsWindowLoader.item) {
            bar.requestPopout(settingsWindowLoader.item, "aurelia.settings")
        }
        if (settingsWindowLoader.item) settingsWindowLoader.item.visible = true
        return "ok"
    }

    function close() {
        // requestClose is a self-contained window function (visible=false +
        // popout release); it never re-enters this plugin, so the IPC toggle
        // close path cannot recurse.
        if (settingsWindowLoader.item &&
            typeof settingsWindowLoader.item.requestClose === "function") {
            settingsWindowLoader.item.requestClose("plugin-close")
        }
        return "ok"
    }

    function toggle(payloadJson) {
        if (typeof isVisible() === "boolean" && isVisible()) return close()
        return open(payloadJson || "{}")
    }

    function isVisible() {
        return settingsWindowLoader.item ? settingsWindowLoader.item.visible : false
    }

    // Plugin-owned IPC target. `aurelia-shell shell toggle aurelia.settings`
    // (the desktop_settings keybinding) reaches this surface.
    IpcHandler {
        target: "aurelia.settings"

        function ping(): bool {
            return settingsWindowLoader.item !== null
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
            return settingsWindowLoader.item ? settingsWindowLoader.item.activeSection : ""
        }
    }

    Loader {
        id: settingsWindowLoader
        active: pluginRoot.configured
        sourceComponent: SettingsWindow {
            pluginRoot: pluginRoot
        }
    }
}
