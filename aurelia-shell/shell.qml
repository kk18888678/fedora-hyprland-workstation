import QtQuick
import Quickshell
import Quickshell.Io
import "./services"

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

    AureliaAppLibrary {
        id: aureliaAppLibrary
    }

    PluginHost {
        id: pluginHost
        registry: pluginRegistry
        shellApi: shellIpc
        appLibrary: aureliaAppLibrary
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
            return pluginRegistry.scan() ? "ok" : "scanning"
        }

        function reloadConfig(): string {
            shellConfig.reload()
            pluginRegistry.registryRevision++
            pluginRegistry.pluginsChanged()
            return "ok"
        }

        function setPluginEnabled(pluginId: string, enabled: string): string {
            return pluginRegistry.setPluginEnabled(pluginId, enabled === "true") ? "ok" : (pluginRegistry.lastError || "error")
        }

        function listPlugins(): string {
            return JSON.stringify(pluginHost.summaries())
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
        console.info("[PERF] Aurelia Shell resident host ready version=" + root.shellVersion)
    }
}
