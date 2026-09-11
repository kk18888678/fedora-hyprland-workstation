import QtQuick
import Quickshell

// Standalone secondary surface. The network bar widget summons this plugin
// through the resident shell, so QR generation and password lifetime do not
// belong to the main network panel.
Item {
    id: root

    property string aureliaPath: ""
    property var shell: null
    property var manifest: ({})
    property var pluginRegistry: null
    readonly property var panel: panelLoader.item

    function configure(target) {
        if (!target) return
        if ("aureliaPath" in target) target.aureliaPath = root.aureliaPath
        if ("shell" in target) target.shell = root.shell
        if ("manifest" in target) target.manifest = root.manifest
    }

    function open(payloadJson) {
        if (!panel) return "not-ready"
        root.configure(panel)
        panel.open(payloadJson || "{}")
        return "ok"
    }

    function close() {
        if (!panel) return "not-ready"
        panel.close()
        return "ok"
    }

    function toggle(payloadJson) {
        if (panel && panel.opened) return close()
        return open(payloadJson || "{}")
    }

    function isVisible() { return !!panel && panel.opened === true }

    IpcHandler {
        target: "aurelia.wifiqr"
        function ping(): bool { return panel !== null }
        function open(): void { root.open("{}") }
        function close(): void { root.close() }
        function toggle(): void { root.toggle("{}") }
        function isVisible(): bool { return root.isVisible() }
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("WifiQrPanel.qml")
        onLoaded: root.configure(item)
        onStatusChanged: if (status === Loader.Error) console.error("[NETWORK] wifiqr_load_failed")
    }

    onAureliaPathChanged: root.configure(panelLoader.item)
    onShellChanged: root.configure(panelLoader.item)
}
