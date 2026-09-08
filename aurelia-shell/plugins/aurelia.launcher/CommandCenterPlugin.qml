import QtQuick
import Quickshell
import Quickshell.Io
import "ui"

// Raycast-style command surface. The historical plugin id remains
// aurelia.launcher so existing Hyprland bindings and user overrides continue
// to work; the user-facing capability is now the Aurelia Command Center.
Item {
    id: pluginRoot

    property string aureliaPath: ""
    property var shell: null
    property var bar: null
    property var appLibrary: null
    property var manifest: ({})
    property var pluginRegistry: null

    readonly property string backendBin: aureliaPath !== ""
        ? aureliaPath + "/bin/aurelia-shell-keybindings"
        : "/usr/local/bin/aurelia-shell-keybindings"
    readonly property var processEnvironment: ({})

    CommandCenterModuleRegistry {
        id: moduleRegistry
    }

    function open(payloadJson) {
        commandCenterPanel.open(payloadJson || "{}")
        return "ok"
    }

    function close() {
        commandCenterPanel.close()
        return "ok"
    }

    function toggle(payloadJson) {
        if (commandCenterPanel.visible) return close()
        return open(payloadJson || "{}")
    }

    function isVisible() {
        return commandCenterPanel.visible
    }

    function listModules() {
        return JSON.stringify(moduleRegistry.summaries())
    }

    function setModuleEnabled(id, enabled) {
        var value = enabled
        if (typeof enabled === "string") {
            var text = enabled.toLowerCase()
            if (text !== "true" && text !== "false") return "enabled must be true or false"
            value = text === "true"
        } else if (enabled !== true && enabled !== false) {
            return "enabled must be true or false"
        }
        return moduleRegistry.setModuleEnabled(id, value) ? "ok" : moduleRegistry.lastError
    }

    IpcHandler {
        target: "aurelia.launcher"

        function ping(): bool { return true }
        function open(): void { pluginRoot.open("{}") }
        function close(): void { pluginRoot.close() }
        function toggle(): void { pluginRoot.toggle("{}") }
        function isVisible(): bool { return pluginRoot.isVisible() }
        function listModules(): string { return pluginRoot.listModules() }
        function setModuleEnabled(id: string, enabled: string): string {
            return pluginRoot.setModuleEnabled(id, enabled)
        }
    }

    CommandCenterPanel {
        id: commandCenterPanel
        backendBin: pluginRoot.backendBin
        processEnvironment: pluginRoot.processEnvironment
        appLibrary: pluginRoot.appLibrary
        moduleRegistry: moduleRegistry
        anchorWindow: pluginRoot.bar
    }
}
