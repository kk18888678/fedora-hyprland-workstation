import QtQuick
import Quickshell
import "./ui"

// Manifest-backed first-party panel plugin. The host injects the optional
// environment properties after URL loading; the entry point deliberately has
// safe defaults so construction cannot fail before injection.
Item {
    id: pluginRoot

    property string aureliaPath: ""
    property var shell: null
    property var manifest: ({})
    property var pluginRegistry: null

    readonly property string pluginId: "aurelia.keybindings"
    readonly property bool configured: shell !== null && pluginRegistry !== null

    function open(payloadJson) {
        keybindingsWindow.visible = true
        return "ok"
    }

    function close() {
        if (keybindingsWindow.visible && typeof keybindingsWindow.requestClose === "function") {
            keybindingsWindow.requestClose("plugin-close")
        } else {
            keybindingsWindow.visible = false
        }
        return "ok"
    }

    function toggle(payloadJson) {
        if (keybindingsWindow.visible) return close()
        return open(payloadJson || "{}")
    }

    function isVisible() {
        return keybindingsWindow.visible
    }

    // Plugin-owned IPC target. The shell target remains the stable lifecycle
    // surface for callers; this target is useful for direct component calls.
    IpcHandler {
        target: "aurelia.keybindings"

        function ping(): bool {
            return pluginRoot.configured && keybindingsWindow !== null
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

        function activeView(): string {
            return keybindingsWindow.keybindingsModel.activeView
        }

        function revision(): string {
            return KeybindingsConfig.uiRevision
        }
    }

    KeybindingsWindow {
        id: keybindingsWindow
        visible: false
    }
}
