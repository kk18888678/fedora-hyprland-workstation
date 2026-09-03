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

    // IPC Endpoint for Aurelia Hotkeys Component
    IpcHandler {
        target: "hotkeys"

        function toggle(): void {
            if (hotkeysLoader.item) {
                hotkeysLoader.item.visible = !hotkeysLoader.item.visible
            }
        }

        function open(): void {
            if (hotkeysLoader.item) {
                hotkeysLoader.item.visible = true
            }
        }

        function close(): void {
            if (hotkeysLoader.item) {
                hotkeysLoader.item.visible = false
            }
        }

        function isVisible(): bool {
            return hotkeysLoader.item ? hotkeysLoader.item.visible : false
        }
    }

    // Lazy/Conditional Loader for Hotkeys Component
    // Inactive components do not allocate windows or timers.
    Loader {
        id: hotkeysLoader
        active: root.hotkeysEnabled
        sourceComponent: HotkeysWindow {
            visible: false
        }
    }
}
