import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../ui"

// This is the plugin's only manifest entry point and is a bar-widget. It owns
// the Bluetooth trigger and its internal popup lifecycle. Bluetooth state and
// actions remain in the popup implementation, following the reference bar
// widget's BlueZ discovery and pending-action model.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string aureliaPath: ""
    property string moduleName: "aurelia.bluetooth"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var barAnchorItem: null
    property bool bluezServiceAvailable: false
    property int bluezProbeAttempts: 0
    property bool ipcReady: false

    readonly property bool ipcOwner: {
        var revision = root.bar && root.bar.widgetRevision !== undefined
            ? root.bar.widgetRevision : -1
        if (!root.barAnchorItem) return false
        if (!root.bar || typeof root.bar.anchorItemFor !== "function") return true
        return root.bar.anchorItemFor(root.moduleName) === root.barAnchorItem
    }

    Timer {
        id: ipcOwnerSettleTimer
        interval: 50
        repeat: false
        onTriggered: root.ipcReady = root.ipcOwner
    }

    onIpcOwnerChanged: {
        root.ipcReady = false
        ipcOwnerSettleTimer.restart()
    }
    readonly property string sourceBinRoot: decodeURIComponent(
        String(Qt.resolvedUrl("../../bin")).replace(/^file:\/\//, "")
    )
    readonly property string backendRoot: aureliaPath !== ""
        ? aureliaPath + "/bin"
        : sourceBinRoot
    readonly property var bluetoothPopup: panelLoader.item
    readonly property bool adapterAvailable: !!(bluetoothPopup && bluetoothPopup.adapter)

    implicitWidth: adapterAvailable ? (bar ? bar.barSize : 32) : 0
    implicitHeight: bar ? bar.barSize : 32
    visible: adapterAvailable

    function resolveAnchor() {
        if (root.bar && typeof root.bar.anchorItemFor === "function") {
            var configured = root.bar.anchorItemFor(root.moduleName)
            if (configured) return configured
        }
        if (root.bar && typeof root.bar.barAnchorItem === "function") {
            var fallback = root.bar.barAnchorItem()
            if (fallback) return fallback
        }
        return root.barAnchorItem || root
    }

    function configurePanel(target) {
        if (!target) return
        if ("bluetoothWidget" in target) target.bluetoothWidget = root
        if ("bar" in target) target.bar = root.bar
        if ("anchorItem" in target) target.anchorItem = root.resolveAnchor()
        if ("backendRoot" in target) target.backendRoot = root.backendRoot
        if ("shell" in target) target.shell = root.shell
        if ("manifest" in target) target.manifest = root.manifest
        if ("pluginRegistry" in target) target.pluginRegistry = root.pluginRegistry
    }

    function open(payloadJson) {
        if (!bluetoothPopup) return "not-ready"
        root.configurePanel(bluetoothPopup)
        return bluetoothPopup.open(payloadJson || "{}")
    }

    function close() {
        if (!bluetoothPopup) return "not-ready"
        bluetoothPopup.close()
        return "ok"
    }

    function toggle(payloadJson) {
        if (!bluetoothPopup) return "not-ready"
        return bluetoothPopup.shown ? root.close() : root.open(payloadJson || "{}")
    }

    function isVisible() {
        return !!bluetoothPopup && bluetoothPopup.shown === true
    }

    function hasBluezService(output) {
        return String(output || "").indexOf("org.freedesktop.DBus.ObjectManager") !== -1
    }

    function probeBluez() {
        if (root.bluezServiceAvailable || bluezProbe.running || root.bluezProbeAttempts >= 3) return
        root.bluezProbeAttempts++
        bluezProbe.running = true
    }

    Component.onDestruction: {
        if (root.bluetoothPopup && typeof root.bluetoothPopup.releaseDiscoveryOnDestruction === "function")
            root.bluetoothPopup.releaseDiscoveryOnDestruction()
    }

    Component {
        id: bluetoothIpcHandler

        IpcHandler {
            target: "aurelia.bluetooth"

            function ping(): bool { return root.adapterAvailable }
            function open(): void { root.open("{}") }
            function close(): void { root.close() }
            function show(): void { root.open("{}") }
            function hide(): void { root.close() }
            function toggle(): void { root.toggle("{}") }
            function toggleBluetooth(): void {
                if (root.bluetoothPopup) root.bluetoothPopup.toggleBluetooth()
            }
        }
    }

    Loader {
        active: root.ipcOwner && root.ipcReady
        sourceComponent: bluetoothIpcHandler
    }

    Loader {
        id: panelLoader
        // Quickshell.Bluetooth creates its BlueZ object manager at component
        // construction time. Probe the system bus first so machines without
        // BlueZ never instantiate that import and emit a startup warning.
        active: root.bluezServiceAvailable
        source: Qt.resolvedUrl("BluetoothPanel.qml")
        onLoaded: root.configurePanel(item)
        onStatusChanged: {
            if (status === Loader.Error) console.error("[BLUETOOTH] panel_load_failed")
        }
    }

    Process {
        id: bluezProbe
        command: [
            "/usr/bin/timeout", "--kill-after=1s", "2s",
            "/usr/bin/busctl", "--system", "--no-pager", "introspect",
            "org.bluez", "/", "org.freedesktop.DBus.ObjectManager"
        ]
        running: false
        stdout: StdioCollector {
            id: bluezProbeStdout
            waitForEnd: true
        }
        stderr: StdioCollector { waitForEnd: true }

        onExited: function(code) {
            if (code === 0 && root.hasBluezService(bluezProbeStdout.text)) {
                root.bluezServiceAvailable = true
                return
            }
            if (root.bluezProbeAttempts < 3) bluezProbeRetry.restart()
        }
    }

    Timer {
        id: bluezProbeRetry
        interval: 500
        repeat: false
        onTriggered: root.probeBluez()
    }

    onBarChanged: root.configurePanel(panelLoader.item)
    onShellChanged: root.configurePanel(panelLoader.item)
    onAureliaPathChanged: root.configurePanel(panelLoader.item)
    onBarAnchorItemChanged: root.configurePanel(panelLoader.item)
    Component.onCompleted: root.probeBluez()

    HoverHandler { id: pointerHover }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: root.isVisible() || pointerHover.hovered ? Theme.selection : "transparent"

        AureliaIcon {
            anchors.centerIn: parent
            width: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            height: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            name: root.bluetoothPopup ? root.bluetoothPopup.iconName : "bluetooth"
            iconSize: root.bar && root.bar.barIconFont ? root.bar.barIconFont : 13
            tint: root.isVisible() ? Theme.accent : Theme.textSecondary
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                mouse.accepted = true
                if (mouse.button === Qt.RightButton) {
                    if (root.bluetoothPopup) root.bluetoothPopup.toggleBluetooth()
                } else {
                    root.toggle("{}")
                }
            }
        }
    }

    AureliaToolTip {
        triggerItem: root
        bar: root.bar
        hovered: pointerHover.hovered
        text: root.bluetoothPopup && root.bluetoothPopup.adapter && root.bluetoothPopup.adapter.enabled
            ? "Bluetooth"
            : "Bluetooth unavailable"
    }
}
