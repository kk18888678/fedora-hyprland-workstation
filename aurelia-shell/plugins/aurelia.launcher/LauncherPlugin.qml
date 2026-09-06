import QtQuick
import Quickshell
import Quickshell.Io
import "ui"

Item {
    id: pluginRoot

    property string aureliaPath: ""
    property var shell: null
    property var manifest: ({})
    property var pluginRegistry: null

    readonly property string backendBin: aureliaPath !== ""
        ? aureliaPath + "/bin/workstation-keybindings"
        : "/usr/local/bin/workstation-keybindings"
    readonly property var processEnvironment: ({
        "PATH": "/usr/local/bin:/usr/bin:/bin" + (Quickshell.env("PATH") ? ":" + Quickshell.env("PATH") : ""),
        "HOME": Quickshell.env("HOME") || "",
        "XDG_DATA_HOME": Quickshell.env("XDG_DATA_HOME") || "",
        "XDG_DATA_DIRS": Quickshell.env("XDG_DATA_DIRS") || "/usr/local/share:/usr/share"
    })

    function open(payloadJson) {
        launcherPanel.open(payloadJson || "{}")
        return "ok"
    }

    function close() {
        launcherPanel.close()
        return "ok"
    }

    function toggle(payloadJson) {
        if (launcherPanel.visible) return close()
        return open(payloadJson || "{}")
    }

    function isVisible() {
        return launcherPanel.visible
    }

    IpcHandler {
        target: "aurelia.launcher"

        function ping(): bool { return true }
        function open(): void { pluginRoot.open("{}") }
        function close(): void { pluginRoot.close() }
        function toggle(): void { pluginRoot.toggle("{}") }
        function isVisible(): bool { return pluginRoot.isVisible() }
    }

    LauncherPanel {
        id: launcherPanel
        backendBin: pluginRoot.backendBin
        processEnvironment: pluginRoot.processEnvironment
    }
}
