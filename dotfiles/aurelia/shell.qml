import QtQuick
import Quickshell
import Quickshell.Io
import "./theme"
import "./components/keybindings"

ShellRoot {
    id: root

    // Aurelia Desktop Shell Host
    // Single-process host for resident and on-demand Aurelia shell components.
    //
    // Lifecycle policy:
    // Keybindings is intentionally kept resident in memory to guarantee sub-100ms warm
    // opening times on Super+K without process spawn latency. Inactive state consumes
    // zero CPU and no background polling timers.

    property bool keybindingsEnabled: true
    property alias hotkeysEnabled: root.keybindingsEnabled

    Component.onCompleted: {
        console.info("[PERF] ShellRoot: Aurelia shell initialization complete (keybindingsEnabled=" + root.keybindingsEnabled + ")")
    }

    // Primary IPC Endpoint: Aurelia Keybindings Component
    IpcHandler {
        id: keybindingsIpc
        target: "keybindings"

        function ping(): bool {
            return keybindingsLoader.item !== null
        }

        function toggle(): void {
            if (keybindingsLoader.item) {
                var next = !keybindingsLoader.item.visible
                console.info("[IPC] keybindings.toggle() -> visible=" + next + " stack=" + new Error().stack)
                if (!next && typeof keybindingsLoader.item.requestClose === "function") {
                    keybindingsLoader.item.requestClose("ipc-toggle")
                } else {
                    keybindingsLoader.item.visible = next
                }
            } else {
                console.warn("[IPC-WARN] keybindings.toggle() called but item not loaded")
            }
        }

        function open(): void {
            if (keybindingsLoader.item) {
                console.info("[IPC] keybindings.open() stack=" + new Error().stack)
                keybindingsLoader.item.visible = true
            }
        }

        function close(): void {
            if (keybindingsLoader.item) {
                console.info("[IPC] keybindings.close() stack=" + new Error().stack)
                if (typeof keybindingsLoader.item.requestClose === "function") {
                    keybindingsLoader.item.requestClose("ipc-close")
                } else {
                    keybindingsLoader.item.visible = false
                }
            }
        }

        function isVisible(): bool {
            return keybindingsLoader.item ? keybindingsLoader.item.visible : false
        }

        function selectIndex(idx: int): void {
            if (keybindingsLoader.item && keybindingsLoader.item.keybindingsModel) {
                keybindingsLoader.item.keybindingsModel.selectedIndex = idx
            }
        }

        function activeView(): string {
            return (keybindingsLoader.item && keybindingsLoader.item.keybindingsModel) ? keybindingsLoader.item.keybindingsModel.activeView : ""
        }

        function cycleView(forward: bool): string {
            if (keybindingsLoader.item && typeof keybindingsLoader.item.cycleTopLevelView === "function") {
                keybindingsLoader.item.cycleTopLevelView(forward)
                return keybindingsLoader.item.keybindingsModel ? keybindingsLoader.item.keybindingsModel.activeView : ""
            }
            return ""
        }

        function switchView(viewName: string): bool {
            if (keybindingsLoader.item && keybindingsLoader.item.keybindingsModel) {
                keybindingsLoader.item.keybindingsModel.switchView(viewName)
                return true
            }
            return false
        }

        function revision(): string {
            return KeybindingsConfig.uiRevision
        }
    }

    // Backwards compatibility IPC Endpoint: forwards hotkeys target to keybindings
    IpcHandler {
        target: "hotkeys"

        function ping(): bool {
            return keybindingsIpc.ping()
        }

        function toggle(): void {
            keybindingsIpc.toggle()
        }

        function open(): void {
            keybindingsIpc.open()
        }

        function close(): void {
            keybindingsIpc.close()
        }

        function isVisible(): bool {
            return keybindingsIpc.isVisible()
        }

        function selectIndex(idx: int): void {
            keybindingsIpc.selectIndex(idx)
        }

        function activeView(): string {
            return keybindingsIpc.activeView()
        }

        function cycleView(forward: bool): string {
            return keybindingsIpc.cycleView(forward)
        }

        function switchView(viewName: string): bool {
            return keybindingsIpc.switchView(viewName)
        }

        function revision(): string {
            return keybindingsIpc.revision()
        }
    }

    // Resident Loader for Keybindings Component
    Loader {
        id: keybindingsLoader
        active: root.keybindingsEnabled
        onLoaded: {
            console.info("[PERF] ShellRoot: KeybindingsWindow component loaded successfully")
        }
        sourceComponent: KeybindingsWindow {
            visible: false
        }
    }

    // Compatibility alias
    property alias hotkeysLoader: keybindingsLoader
}
