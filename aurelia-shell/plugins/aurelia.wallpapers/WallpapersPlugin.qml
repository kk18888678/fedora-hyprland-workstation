import QtQuick
import Quickshell
import Quickshell.Io
import "ui"

// Resident wallpaper library surface. The plugin owns discovery, preview, and
// selection only: every mutation is delegated to the aurelia-wallpaper command,
// which itself delegates activation to aurelia-theme-bg / aurelia-theme.
Item {
    id: pluginRoot

    property string aureliaPath: ""
    property var shell: null
    property var bar: null
    property var manifest: ({})
    property var pluginRegistry: null

    function open(payloadJson) {
        wallpapersPanel.open(payloadJson || "{}")
        return "ok"
    }

    function close() {
        wallpapersPanel.close()
        return "ok"
    }

    function toggle(payloadJson) {
        if (wallpapersPanel.opened) return close()
        return open(payloadJson || "{}")
    }

    function isVisible() {
        return wallpapersPanel.opened
    }

    function refresh() {
        wallpapersPanel.refresh()
        return "ok"
    }

    IpcHandler {
        target: "aurelia.wallpapers"

        function ping(): bool { return true }
        function open(payload: string): void { pluginRoot.open(payload) }
        function close(): void { pluginRoot.close() }
        function toggle(payload: string): void { pluginRoot.toggle(payload) }
        function isVisible(): bool { return pluginRoot.isVisible() }
    }

    WallpapersPanel {
        id: wallpapersPanel
        aureliaPath: pluginRoot.aureliaPath
    }
}
