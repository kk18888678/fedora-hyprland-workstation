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

    property string aureliaPath: String(Qt.resolvedUrl("../../")).replace(/^file:\/\//, "")
    property var shell: null
    property var shellConfig: null
    property var manifest: ({})
    property var pluginRegistry: null
    property var barWidgetRegistry: null
    property var pluginHost: null
    property var widgetSlots: []
    property int widgetRevision: 0

    // ShellConfig is present in the production host. Keep only a minimal
    // recovery shape here so a missing state object cannot prevent a bar from
    // constructing; the canonical default layout lives in bar-default.json.
    readonly property var defaultConfig: shellConfig && typeof shellConfig.defaultBarConfig === "function"
        ? shellConfig.defaultBarConfig()
        : ({id: "aurelia.bar", position: "top", transparent: false,
            centerAnchor: "aurelia.clock", layout: {left: [], center: [], right: []}})
    readonly property var barConfig: shellConfig && shellConfig.config && shellConfig.config.bar
        ? shellConfig.config.bar
        : defaultConfig
    readonly property string position: ["top", "bottom", "left", "right"].indexOf(barConfig.position) !== -1
        ? barConfig.position
        : "top"
    readonly property string centerAnchor: typeof barConfig.centerAnchor === "string" ? barConfig.centerAnchor : ""
    readonly property bool transparent: barConfig.transparent === true
    readonly property bool barConfigReady: barConfig && barConfig.layout
    readonly property bool vertical: position === "left" || position === "right"
    // The cross-axis size follows the reference bar's structural scale. Popup
    // panels read this same property from their actual anchor window.
    readonly property int barSize: vertical ? Theme.bar.sizeVertical : Theme.bar.sizeHorizontal
    readonly property int barOuterMargin: Theme.bar.outerMargin
    readonly property int barIconSlot: Theme.bar.iconSlot
    readonly property int barIconCanvas: Theme.bar.iconCanvas
    readonly property int barIconFont: Theme.bar.iconFont
    readonly property int barStatusSlot: Theme.bar.statusSlot
    readonly property int barTrayIcon: Theme.bar.trayIcon
    readonly property real barTextMargin: Theme.bar.textMargin
    readonly property int barTextSize: Theme.bar.text
    readonly property int barCaptionSize: Theme.bar.caption
    property bool barHidden: false
    readonly property bool barVisible: !barHidden
    property var activePopout: null
    property string activePopoutId: ""

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "aurelia-bar"
    anchors.top: position === "top" || vertical
    anchors.bottom: position === "bottom" || vertical
    anchors.left: position === "left" || !vertical
    anchors.right: position === "right" || !vertical
    implicitWidth: vertical ? barSize : 0
    implicitHeight: vertical ? 0 : barSize
    margins {
        top: barRoot.barHidden && position === "top" ? -barSize : 0
        bottom: barRoot.barHidden && position === "bottom" ? -barSize : 0
        left: barRoot.barHidden && position === "left" ? -barSize : 0
        right: barRoot.barHidden && position === "right" ? -barSize : 0
    }
    exclusionMode: barHidden ? ExclusionMode.Ignore : ExclusionMode.Auto
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
        widgetRevision++
    }

    function unregisterWidgetSlot(slot) {
        widgetSlots = widgetSlots.filter(function(item) { return item !== slot })
        widgetRevision++
    }

    function bumpWidgetRevision() {
        widgetRevision++
    }

    function reloadWidgets() {
        var slots = widgetSlots.slice()
        for (var i = 0; i < slots.length; i++) {
            if (slots[i] && typeof slots[i].reload === "function") slots[i].reload()
        }
    }

    function anchorItemFor(pluginId) {
        var revision = widgetRevision
        for (var i = 0; i < widgetSlots.length; i++) {
            var slot = widgetSlots[i]
            if (slot && slot.pluginId === pluginId) return slot
        }
        return null
    }

    function barAnchorItem() {
        return barContentAnchor
    }

    function callWidget(pluginId, method, argument) {
        var exactMatches = []
        var baseMatches = []
        for (var i = 0; i < widgetSlots.length; i++) {
            var slot = widgetSlots[i]
            if (!slot) continue
            if (slot.instanceId === pluginId) exactMatches.push(slot)
            else if (slot.pluginId === pluginId) baseMatches.push(slot)
        }
        if (exactMatches.length > 1) return "ambiguous"
        if (exactMatches.length === 1) return exactMatches[0].invoke(method, argument)
        if (baseMatches.length > 1) return "ambiguous"
        if (baseMatches.length === 1) return baseMatches[0].invoke(method, argument)
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
        barHidden = false
        return "ok"
    }

    // A bar owns the single-popout invariant. Widgets remain independent
    // plugins, but they cannot leave two floating surfaces stacked over one
    // another or strand an old surface after switching widgets.
    function requestPopout(owner, ownerId) {
        if (!owner || activePopout === owner) return
        var previous = activePopout
        activePopout = owner
        activePopoutId = String(ownerId || "")
        if (previous) {
            if (typeof previous.closeForPopoutSwitch === "function") previous.closeForPopoutSwitch()
            else if (typeof previous.close === "function") previous.close()
            else if (typeof previous.requestClose === "function") previous.requestClose("popout-switch")
        }
    }

    function releasePopout(owner) {
        if (activePopout === owner) {
            activePopout = null
            activePopoutId = ""
        }
    }

    function close() {
        if (activePopout && typeof activePopout.closeForPopoutSwitch === "function") activePopout.closeForPopoutSwitch()
        else if (activePopout && typeof activePopout.requestClose === "function") activePopout.requestClose("bar-close")
        activePopout = null
        activePopoutId = ""
        barHidden = true
        return "ok"
    }

    function toggle(payloadJson) {
        barHidden = !barHidden
        return barHidden ? "closed" : "ok"
    }

    function isVisible() {
        return !barHidden
    }

    function themeStatus() {
        return JSON.stringify({
            visible: barRoot.visible,
            hidden: barRoot.barHidden,
            transparent: barRoot.transparent,
            surface: String(barSurface.color),
            border: String(barSurface.border.color),
            themeBackground: String(Theme.bar.background),
            themeAccent: String(Theme.bar.active),
            themeText: String(Theme.bar.foreground),
            widgetSlots: barRoot.widgetSlots.length,
            position: barRoot.position,
            size: barRoot.barSize
        })
    }

    IpcHandler {
        target: "aurelia.bar"

        function ping(): bool { return true }
        function open(): void { barRoot.open("{}") }
        function close(): void { barRoot.close() }
        function toggle(): void { barRoot.toggle("{}") }
        function isVisible(): bool { return barRoot.isVisible() }
        function themeStatus(): string { return barRoot.themeStatus() }
    }

    Rectangle {
        id: barSurface
        anchors.fill: parent
        color: barRoot.transparent ? "transparent" : Theme.bar.background
        border.color: barRoot.transparent ? "transparent" : Theme.bar.border
        border.width: barRoot.transparent ? 0 : Theme.borderWidthDefault

        Item {
            id: content
            anchors.fill: parent
            anchors.leftMargin: barRoot.vertical ? 0 : barRoot.barOuterMargin
            anchors.rightMargin: barRoot.vertical ? 0 : barRoot.barOuterMargin
            anchors.topMargin: barRoot.vertical ? barRoot.barOuterMargin : 0
            anchors.bottomMargin: barRoot.vertical ? barRoot.barOuterMargin : 0

            // Stable fallback anchor for center-on-bar panels while a widget
            // slot is still being registered. It is non-interactive and does
            // not replace a real widget anchor when one is available.
            Item {
                id: barContentAnchor
                objectName: "aurelia-bar-content-anchor"
                anchors.fill: parent
                visible: true
                opacity: 0
                enabled: false
                z: -100
            }

            GridLayout {
                id: leftGroup
                anchors.left: barRoot.vertical ? undefined : parent.left
                anchors.top: barRoot.vertical ? parent.top : undefined
                anchors.horizontalCenter: barRoot.vertical ? parent.horizontalCenter : undefined
                anchors.verticalCenter: barRoot.vertical ? undefined : parent.verticalCenter
                columns: barRoot.vertical ? 1 : 2
                columnSpacing: barRoot.vertical ? 0 : Theme.spacingSm
                rowSpacing: barRoot.vertical ? Theme.spacingSm : 0

                AureliaLogo {
                    bar: barRoot
                    shell: barRoot.shell
                    Layout.preferredWidth: barRoot.vertical ? barRoot.barSize : implicitWidth
                    Layout.preferredHeight: barRoot.vertical ? implicitHeight : barRoot.barSize
                }

                BarWidgetRow {
                    entries: barRoot.entriesFor("left")
                    bar: barRoot
                    shell: barRoot.shell
                    pluginRegistry: barRoot.pluginRegistry
                    barWidgetRegistry: barRoot.barWidgetRegistry
                    pluginHost: barRoot.pluginHost
                    aureliaPath: barRoot.aureliaPath
                    Layout.preferredWidth: barRoot.vertical ? barRoot.barSize : implicitWidth
                    Layout.preferredHeight: barRoot.vertical ? implicitHeight : barRoot.barSize
                }
            }

            BarCenter {
                anchors.fill: parent
                entries: barRoot.entriesFor("center")
                anchorId: barRoot.centerAnchor
                bar: barRoot
                shell: barRoot.shell
                pluginRegistry: barRoot.pluginRegistry
                barWidgetRegistry: barRoot.barWidgetRegistry
                pluginHost: barRoot.pluginHost
                aureliaPath: barRoot.aureliaPath
            }

            BarWidgetRow {
                id: rightGroup
                anchors.right: barRoot.vertical ? undefined : parent.right
                anchors.bottom: barRoot.vertical ? parent.bottom : undefined
                anchors.horizontalCenter: barRoot.vertical ? parent.horizontalCenter : undefined
                anchors.verticalCenter: barRoot.vertical ? undefined : parent.verticalCenter
                entries: barRoot.entriesFor("right")
                bar: barRoot
                shell: barRoot.shell
                pluginRegistry: barRoot.pluginRegistry
                barWidgetRegistry: barRoot.barWidgetRegistry
                pluginHost: barRoot.pluginHost
                aureliaPath: barRoot.aureliaPath
            }
        }
    }
}
