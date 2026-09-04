import QtQuick
import Quickshell
import Quickshell.Io
import "./theme"
import "./components/hotkeys"

ShellRoot {
    id: root

    // Aurelia Quickshell Shell Root
    // Production-ready, event-driven, single-process host for Aurelia desktop shell components.

    property bool hotkeysEnabled: true

    Component.onCompleted: {
        console.info("[PERF] ShellRoot: Aurelia shell initialization complete (hotkeysEnabled=" + root.hotkeysEnabled + ")")
    }

    // IPC Endpoint for Aurelia Hotkeys Component
    IpcHandler {
        target: "hotkeys"

        function ping(): bool {
            return hotkeysLoader.item !== null
        }

        function toggle(): void {
            if (hotkeysLoader.item) {
                var next = !hotkeysLoader.item.visible
                console.info("[IPC] hotkeys.toggle() -> visible=" + next)
                hotkeysLoader.item.visible = next
            } else {
                console.warn("[IPC-WARN] hotkeys.toggle() called but item not loaded")
            }
        }

        function open(): void {
            if (hotkeysLoader.item) {
                console.info("[IPC] hotkeys.open()")
                hotkeysLoader.item.visible = true
            }
        }

        function close(): void {
            if (hotkeysLoader.item) {
                console.info("[IPC] hotkeys.close()")
                hotkeysLoader.item.visible = false
            }
        }

        function isVisible(): bool {
            return hotkeysLoader.item ? hotkeysLoader.item.visible : false
        }

        function selectIndex(idx: int): void {
            if (hotkeysLoader.item && hotkeysLoader.item.hotkeysModel) {
                hotkeysLoader.item.hotkeysModel.selectedIndex = idx
            }
        }
    }

    // Lazy/Conditional Loader for Hotkeys Component
    // Inactive components do not allocate windows or timers.
    Loader {
        id: hotkeysLoader
        active: root.hotkeysEnabled
        onLoaded: {
            console.info("[PERF] ShellRoot: HotkeysWindow component loaded successfully")
        }
        sourceComponent: HotkeysWindow {
            visible: false
        }
    }
}
