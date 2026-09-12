import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../ui"

// The network plugin follows Omarchy's proven boundary: the bar widget owns
// the live NetworkManager-backed status affordance, while NetworkPanel owns
// the keyboard-capable popout and connection actions.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string aureliaPath: ""
    property string moduleName: "aurelia.network"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var barAnchorItem: null
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
    readonly property var networkPanel: panelLoader.item
    // Keep the bar compact by default. A user can opt into the SSID/type label
    // with { "showLabel": true } on the bar entry.
    readonly property bool showLabel: !!(settings &&
        (settings.showLabel === true || settings.showLabel === "true"))

    implicitWidth: showLabel ? barContent.implicitWidth + Theme.spacingSm * 2 : (bar ? bar.barSize : 32)
    implicitHeight: bar ? bar.barSize : 32

    function configurePanel(target) {
        if (!target) return
        if ("bar" in target) target.bar = root.bar
        if ("shell" in target) target.shell = root.shell
        if ("aureliaPath" in target) target.aureliaPath = root.aureliaPath
        if ("backendRoot" in target) target.backendRoot = root.backendRoot
        if ("anchorItem" in target) target.anchorItem = root.resolveAnchor()
        if ("manifest" in target) target.manifest = root.manifest
        if ("pluginRegistry" in target) target.pluginRegistry = root.pluginRegistry
    }

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

    function open(payloadJson) {
        if (!networkPanel) return "not-ready"
        root.configurePanel(networkPanel)
        networkPanel.open(payloadJson || "{}")
        return "ok"
    }

    function close() {
        if (!networkPanel) return "not-ready"
        networkPanel.close()
        return "ok"
    }

    function toggle(payloadJson) {
        if (networkPanel && networkPanel.shown) return close()
        return open(payloadJson || "{}")
    }

    function isVisible() {
        return !!networkPanel && networkPanel.shown === true
    }

    Component {
        id: networkIpcHandler

        IpcHandler {
            target: "aurelia.network"

            function ping(): bool { return networkPanel !== null }
            function open(): void { root.open("{}") }
            function close(): void { root.close() }
            function show(): void { root.open("{}") }
            function hide(): void { root.close() }
            function toggle(): void { root.toggle("{}") }
            function toggleNetwork(): void {
                if (networkPanel && typeof networkPanel.toggleNetwork === "function") networkPanel.toggleNetwork()
            }
            function checkConnectivity(): void {
                if (networkPanel && typeof networkPanel.checkConnectivity === "function") networkPanel.checkConnectivity()
            }
        }
    }

    Loader {
        active: root.ipcOwner && root.ipcReady
        sourceComponent: networkIpcHandler
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("NetworkPanel.qml")
        onLoaded: root.configurePanel(item)
        onStatusChanged: {
            if (status === Loader.Error) console.error("[NETWORK] panel_load_failed")
        }
    }

    onBarChanged: root.configurePanel(panelLoader.item)
    onShellChanged: root.configurePanel(panelLoader.item)
    onAureliaPathChanged: root.configurePanel(panelLoader.item)
    onBarAnchorItemChanged: root.configurePanel(panelLoader.item)

    HoverHandler { id: pointerHover }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: root.isVisible() || pointerHover.hovered ? Theme.selection : "transparent"

        Row {
            id: barContent
            anchors.centerIn: parent
            spacing: Theme.spacingXs

            AureliaIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
                height: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
                iconSize: root.bar && root.bar.barIconFont ? root.bar.barIconFont : 13
                glyph: root.networkPanel && root.networkPanel.icon
                    ? root.networkPanel.icon : "󰤮"
                tint: root.networkPanel && root.networkPanel.restricted
                    ? Theme.warning : Theme.textSecondary
            }

            Text {
                visible: root.showLabel
                anchors.verticalCenter: parent.verticalCenter
                text: root.networkPanel ? root.networkPanel.barLabel : "Network"
                width: root.showLabel ? Math.min(150, implicitWidth) : 0
                color: root.networkPanel && root.networkPanel.restricted
                ? Theme.warning
                : Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: root.bar && root.bar.barCaptionSize ? root.bar.barCaptionSize : Theme.fontSizeXs
                elide: Text.ElideRight
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                mouse.accepted = true
                root.toggle("{}")
            }
        }
    }

    AureliaToolTip {
        triggerItem: root
        bar: root.bar
        hovered: pointerHover.hovered
        text: root.networkPanel
            ? (root.networkPanel.hasCaptivePortal
                ? "Sign in to this network"
                : (root.networkPanel.restricted
                    ? "Limited internet access"
                    : root.networkPanel.barLabel))
            : "Network"
    }
}
