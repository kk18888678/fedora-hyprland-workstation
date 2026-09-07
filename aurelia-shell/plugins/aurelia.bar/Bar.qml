import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"

// Aurelia's first bar host follows the Omarchy boundary: the host owns the
// bar surface and configuration, while each configured module is a manifest-
// backed `bar-widget` entry point. The bar is mounted by the resident host;
// Noctalia remains independently selectable as the active desktop shell.
PanelWindow {
    id: barRoot

    property string aureliaPath: ""
    property var shell: null
    property var shellConfig: null
    property var manifest: ({})
    property var pluginRegistry: null
    property var widgetSlots: []

    readonly property var defaultConfig: ({
        position: "top",
        transparent: false,
        centerAnchor: "aurelia.clock",
        layout: {
            left: [{ id: "aurelia.workspaces" }],
            center: [
                { id: "aurelia.clock", format: "MMM d, dddd HH:mm" },
                { id: "aurelia.weather", location: "auto" }
            ],
            right: [
                { id: "aurelia.tray" },
                { id: "aurelia.screenshot" },
                { id: "aurelia.power" }
            ]
        }
    })
    readonly property var barConfig: shellConfig && shellConfig.config && shellConfig.config.bar
        ? shellConfig.config.bar
        : defaultConfig
    readonly property string position: barConfig.position === "bottom" ? "bottom" : "top"
    readonly property string centerAnchor: typeof barConfig.centerAnchor === "string" ? barConfig.centerAnchor : ""
    readonly property bool transparent: barConfig.transparent === true
    readonly property bool barConfigReady: barConfig && barConfig.layout
    // Match the horizontal size used by Omarchy's reference bar. Popouts use
    // this value as their exact clearance below the bar.
    readonly property int barSize: 26
    property var activePopout: null

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "aurelia-bar"
    anchors.top: position === "top"
    anchors.bottom: position === "bottom"
    anchors.left: true
    anchors.right: true
    implicitHeight: barSize
    exclusionMode: ExclusionMode.Auto
    color: "transparent"
    visible: true

    function entriesFor(region) {
        if (!barConfigReady || !Array.isArray(barConfig.layout[region])) return []
        return barConfig.layout[region]
    }

    function registerWidgetSlot(slot) {
        if (!slot || widgetSlots.indexOf(slot) !== -1) return
        var next = widgetSlots.slice()
        next.push(slot)
        widgetSlots = next
    }

    function unregisterWidgetSlot(slot) {
        widgetSlots = widgetSlots.filter(function(item) { return item !== slot })
    }

    function callWidget(pluginId, method, argument) {
        for (var i = 0; i < widgetSlots.length; i++) {
            var slot = widgetSlots[i]
            if (slot && slot.pluginId === pluginId) return slot.invoke(method, argument)
        }
        return "not-loaded"
    }

    function hasWidget(pluginId) {
        for (var i = 0; i < widgetSlots.length; i++) {
            var slot = widgetSlots[i]
            if (slot && slot.pluginId === pluginId && slot.widgetItem) return true
        }
        return false
    }

    function open(payloadJson) {
        visible = true
        return "ok"
    }

    // A bar owns the single-popout invariant. Widgets remain independent
    // plugins, but they cannot leave two floating surfaces stacked over one
    // another or strand an old surface after switching widgets.
    function requestPopout(owner) {
        if (!owner || activePopout === owner) return
        var previous = activePopout
        activePopout = owner
        if (previous) {
            if (typeof previous.closeForPopoutSwitch === "function") previous.closeForPopoutSwitch()
            else if (typeof previous.close === "function") previous.close()
            else if (typeof previous.requestClose === "function") previous.requestClose("popout-switch")
        }
    }

    function releasePopout(owner) {
        if (activePopout === owner) activePopout = null
    }

    function close() {
        if (activePopout && typeof activePopout.closeForPopoutSwitch === "function") activePopout.closeForPopoutSwitch()
        else if (activePopout && typeof activePopout.requestClose === "function") activePopout.requestClose("bar-close")
        activePopout = null
        visible = false
        return "ok"
    }

    function toggle(payloadJson) {
        visible = !visible
        return visible ? "ok" : "closed"
    }

    function isVisible() {
        return visible
    }

    IpcHandler {
        target: "aurelia.bar"

        function ping(): bool { return true }
        function open(): void { barRoot.open("{}") }
        function close(): void { barRoot.close() }
        function toggle(): void { barRoot.toggle("{}") }
        function isVisible(): bool { return barRoot.isVisible() }
    }

    Rectangle {
        anchors.fill: parent
        color: barRoot.transparent ? "transparent" : Theme.bgBase
        border.color: barRoot.transparent ? "transparent" : Theme.border
        border.width: barRoot.transparent ? 0 : Theme.borderWidthDefault

        Item {
            id: content
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingLg
            anchors.rightMargin: Theme.spacingLg

            RowLayout {
                id: leftGroup
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingSm

                AureliaLogo {
                    shell: barRoot.shell
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: implicitHeight
                }

                BarWidgetRow {
                    entries: barRoot.entriesFor("left")
                    bar: barRoot
                    shell: barRoot.shell
                    pluginRegistry: barRoot.pluginRegistry
                    aureliaPath: barRoot.aureliaPath
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: barRoot.height
                }
            }

            BarCenter {
                anchors.fill: parent
                entries: barRoot.entriesFor("center")
                anchorId: barRoot.centerAnchor
                bar: barRoot
                shell: barRoot.shell
                pluginRegistry: barRoot.pluginRegistry
                aureliaPath: barRoot.aureliaPath
            }

            BarWidgetRow {
                id: rightGroup
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                entries: barRoot.entriesFor("right")
                bar: barRoot
                shell: barRoot.shell
                pluginRegistry: barRoot.pluginRegistry
                aureliaPath: barRoot.aureliaPath
            }
        }
    }
}
