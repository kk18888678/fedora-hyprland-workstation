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
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string stateHomeOverride: Quickshell.env("XDG_STATE_HOME") || ""
    readonly property string stateHome: stateHomeOverride.charAt(0) === "/" && stateHomeOverride !== "/"
        ? stateHomeOverride
        : (home.charAt(0) === "/" && home !== "/" ? home + "/.local/state" : "")
    // This override is test-only in the fixture; production always uses the
    // XDG state namespace so bar hiding follows the user's state home.
    property string hiddenStatePathOverride: ""
    readonly property string hiddenStatePath: hiddenStatePathOverride.charAt(0) === "/" && hiddenStatePathOverride !== "/"
        ? hiddenStatePathOverride
        : (stateHome !== "" ? stateHome + "/aurelia/toggles/bar-off" : "")
    readonly property string hiddenStateDirectory: hiddenStatePath === ""
        ? "" : hiddenStatePath.substring(0, hiddenStatePath.lastIndexOf("/"))
    readonly property string hiddenStateWatchPath: hiddenStateDirectoryPresent && hiddenStateDirectory !== ""
        ? hiddenStateDirectory : stateHome
    readonly property string hiddenStateToolPath: aureliaPath !== "" && aureliaPath.charAt(0) === "/"
        ? aureliaPath + "/bin/aurelia-bar-hidden" : ""
    property bool hiddenStateDirectoryPresent: false
    property bool hiddenStateSyncPending: false
    property string hiddenStateReadState: "uninitialized"
    property string hiddenStateReadError: ""
    property var hiddenStateWriteQueue: []
    property string hiddenStateWriteOperation: ""
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
        queueHiddenState("off")
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
        queueHiddenState("on")
        return "ok"
    }

    function toggle(payloadJson) {
        var wasHidden = barHidden
        queueHiddenState("toggle")
        return wasHidden ? "ok" : "closed"
    }

    function isVisible() {
        return !barHidden
    }

    function queueHiddenState(operation) {
        var value = String(operation || "")
        if (["on", "off", "toggle"].indexOf(value) === -1) {
            console.error("[BAR] hidden_state_invalid_operation operation=" + value)
            return "error"
        }
        var next = hiddenStateWriteQueue.slice()
        next.push(value)
        hiddenStateWriteQueue = next
        pumpHiddenStateWrites()
        return "pending"
    }

    function pumpHiddenStateWrites() {
        if (hiddenStateWriteProcess.running || hiddenStateWriteQueue.length === 0) return
        if (hiddenStateToolPath === "") {
            console.error("[BAR] hidden_state_writer_unavailable path=" + hiddenStateToolPath)
            hiddenStateWriteQueue = []
            return
        }
        var next = hiddenStateWriteQueue.slice()
        hiddenStateWriteOperation = String(next.shift())
        hiddenStateWriteQueue = next
        hiddenStateWriteProcess.command = [hiddenStateToolPath, hiddenStateWriteOperation]
        hiddenStateWriteProcess.running = true
    }

    function syncHidden() {
        if (hiddenStatePath === "" || hiddenStateToolPath === "") {
            barHidden = false
            hiddenStateReadState = "invalid-path"
            hiddenStateReadError = "Aurelia bar-hidden state path is unavailable."
            console.error("[BAR] hidden_state_read_failed reason=invalid-path")
            return
        }
        if (hiddenStateProbe.running) {
            hiddenStateSyncPending = true
            return
        }
        hiddenStateProbe.running = true
    }

    function probeHiddenStateDirectory() {
        if (hiddenStateDirectory === "" || hiddenStateDirectoryProbe.running) return
        hiddenStateDirectoryProbe.running = true
    }

    function themeStatus() {
        return JSON.stringify({
            visible: barRoot.visible,
            hidden: barRoot.barHidden,
            hiddenState: barRoot.hiddenStateReadState,
            hiddenStateError: barRoot.hiddenStateReadError,
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
        function syncHidden(): void { barRoot.syncHidden() }
        function themeStatus(): string { return barRoot.themeStatus() }
    }

    Process {
        id: hiddenStateProbe
        command: barRoot.hiddenStateToolPath === "" ? [] : [barRoot.hiddenStateToolPath, "read"]
        running: false
        stdout: StdioCollector { id: hiddenStateProbeOutput; waitForEnd: true }
        stderr: StdioCollector { id: hiddenStateProbeError; waitForEnd: true }
        onExited: function(code) {
            var state = String(hiddenStateProbeOutput.text || "").trim()
            var detail = String(hiddenStateProbeError.text || "").trim()
            if (code === 0 && (state === "hidden" || state === "visible")) {
                barRoot.barHidden = state === "hidden"
                barRoot.hiddenStateReadState = state
                barRoot.hiddenStateReadError = ""
            } else {
                barRoot.barHidden = false
                barRoot.hiddenStateReadState = "error"
                barRoot.hiddenStateReadError = detail || ("bar-hidden reader exited with code " + code)
                console.error("[BAR] hidden_state_read_failed code=" + code +
                    " detail=" + barRoot.hiddenStateReadError)
            }
            if (barRoot.hiddenStateSyncPending) {
                barRoot.hiddenStateSyncPending = false
                Qt.callLater(barRoot.syncHidden)
            }
        }
    }

    Process {
        id: hiddenStateDirectoryProbe
        command: barRoot.hiddenStateDirectory === "" ? [] : ["/usr/bin/test", "-d", barRoot.hiddenStateDirectory]
        running: false
        onExited: function(code) {
            if (code !== 0 && code !== 1) {
                console.error("[BAR] hidden_state_directory_probe_failed code=" + code)
                return
            }
            var present = code === 0
            if (present !== barRoot.hiddenStateDirectoryPresent) {
                barRoot.hiddenStateDirectoryPresent = present
                barRoot.syncHidden()
            }
        }
    }

    Process {
        id: hiddenStateWriteProcess
        command: barRoot.hiddenStateToolPath === "" || barRoot.hiddenStateWriteOperation === ""
            ? [] : [barRoot.hiddenStateToolPath, barRoot.hiddenStateWriteOperation]
        running: false
        stdout: StdioCollector { id: hiddenStateWriteOutput; waitForEnd: true }
        stderr: StdioCollector { id: hiddenStateWriteError; waitForEnd: true }
        onExited: function(code) {
            var detail = String(hiddenStateWriteError.text || hiddenStateWriteOutput.text || "").trim()
            if (code !== 0) {
                console.error("[BAR] hidden_state_write_failed operation=" +
                    barRoot.hiddenStateWriteOperation + " code=" + code +
                    (detail === "" ? "" : " detail=" + detail))
            }
            barRoot.hiddenStateWriteOperation = ""
            barRoot.syncHidden()
            barRoot.pumpHiddenStateWrites()
        }
    }

    FileView {
        id: hiddenStateDirectoryView
        path: barRoot.hiddenStateWatchPath
        watchChanges: true
        blockWrites: true
        // Missing state is represented by a valid visible default. The
        // fallback path is the XDG state root; any watcher failure remains
        // visible through FileView and the explicit diagnostic below.
        printErrors: true
        onFileChanged: barRoot.syncHidden()
        onLoadFailed: {
            if (barRoot.hiddenStateDirectoryPresent)
                console.error("[BAR] hidden_state_watcher_failed path=" + barRoot.hiddenStateWatchPath)
        }
    }

    Timer {
        id: hiddenStateDirectoryTimer
        interval: 500
        running: true
        repeat: true
        onTriggered: barRoot.probeHiddenStateDirectory()
    }

    Component.onCompleted: {
        barRoot.syncHidden()
        barRoot.probeHiddenStateDirectory()
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
