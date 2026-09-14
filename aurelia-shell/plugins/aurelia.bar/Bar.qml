import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "BarInteractionModel.js" as BarInteractionModel

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
    property bool barMoveActive: false
    property string barMoveCandidate: ""
    property var barMoveScreen: null
    property bool widgetDragActive: false
    property var widgetDragSource: null
    property var widgetDragTarget: null
    property bool widgetDragAfter: false
    property var widgetDropMarkerGeometry: null

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
    readonly property bool requestedTransparent: barConfig.transparent === true
    property color themeForeground: Theme.bar.foreground
    property color themeContrastForeground: Theme.background
    property color transparentForeground: Theme.bar.foreground
    property bool transparentForegroundFallbackReported: false
    property bool foregroundAnimationEnabled: true
    readonly property color foreground: requestedTransparent ? transparentForeground : themeForeground
    readonly property color barForeground: foreground
    readonly property color background: Theme.bar.background
    readonly property color urgent: Theme.bar.active
    readonly property bool transparent: requestedTransparent
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
    readonly property string hiddenStateToolPath: aureliaPath !== "" && aureliaPath.charAt(0) === "/"
        ? aureliaPath + "/bin/aurelia-bar-hidden" : ""
    readonly property string barTextColorToolPath: aureliaPath !== "" && aureliaPath.charAt(0) === "/"
        ? aureliaPath + "/bin/aurelia-bar-text-color" : ""
    readonly property int barDragThreshold: 4
    property bool hiddenStateDirectoryPresent: false
    readonly property bool hiddenStateWatcherUnavailable: !!hiddenStateWatcher &&
        hiddenStateWatcher.unavailable === true
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
    surfaceFormat.opaque: false
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
        if (widgetDragSource === slot) clearWidgetDrag()
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

    function screenForBar() {
        try {
            if (barRoot.screen) return barRoot.screen
        } catch (error) {
            console.warn("[BAR] screen_lookup_failed")
        }
        try {
            if (Quickshell.screens && Quickshell.screens.length > 0) return Quickshell.screens[0]
        } catch (error2) {
            console.warn("[BAR] screen_fallback_failed")
        }
        return null
    }

    function screenPointFromItem(item, x, y) {
        var point = {x: Number(x) || 0, y: Number(y) || 0}
        try {
            if (item && typeof item.mapToItem === "function") point = item.mapToItem(null, point.x, point.y)
        } catch (error) {
            console.warn("[BAR] coordinate_mapping_failed")
            return point
        }

        var activeScreen = root.screenForBar()
        if (!activeScreen) return point
        var screenWidth = Number(activeScreen.width) || 0
        var screenHeight = Number(activeScreen.height) || 0
        if (root.position === "bottom") point.y += Math.max(0, screenHeight - Number(barRoot.height || 0))
        else if (root.position === "right") point.x += Math.max(0, screenWidth - Number(barRoot.width || 0))
        return point
    }

    function screenPointForDrag(point) {
        var activeScreen = root.screenForBar()
        if (!activeScreen) return point || {x: 0, y: 0}
        return {
            x: Math.max(0, Math.min(Number(activeScreen.width) || 0, Number(point && point.x) || 0)),
            y: Math.max(0, Math.min(Number(activeScreen.height) || 0, Number(point && point.y) || 0))
        }
    }

    function beginBarMove() {
        root.barMoveScreen = root.screenForBar()
        root.barMoveCandidate = root.position
        root.barMoveActive = !!root.barMoveScreen
        if (root.barMoveActive) console.info("[BAR] direct_move_started")
        else console.error("[BAR] direct_move_failed reason=screen_unavailable")
    }

    function updateBarMove(point) {
        if (!root.barMoveActive || !root.barMoveScreen) return
        root.barMoveCandidate = BarInteractionModel.nearestScreenEdge(point,
            root.barMoveScreen.width, root.barMoveScreen.height)
    }

    function clearBarMove() {
        root.barMoveActive = false
        root.barMoveCandidate = ""
        root.barMoveScreen = null
    }

    function setBarPosition(value) {
        var requested = String(value || "")
        if (["top", "bottom", "left", "right"].indexOf(requested) === -1) {
            console.error("[BAR] direct_move_failed reason=invalid_position value=" + requested)
            return "invalid-position"
        }
        if (!root.shell || typeof root.shell.setBarPosition !== "function") {
            console.error("[BAR] direct_move_failed reason=mutation_owner_unavailable")
            return "not-ready"
        }
        var result = String(root.shell.setBarPosition(requested) || "")
        if (result === "ok") console.info("[BAR] direct_move_committed position=" + requested)
        else console.error("[BAR] direct_move_failed position=" + requested + " detail=" + result)
        return result
    }

    function finishBarMove() {
        var candidate = root.barMoveCandidate
        if (!root.barMoveActive || candidate === "" || candidate === root.position) {
            root.clearBarMove()
            return "ok"
        }
        root.clearBarMove()
        return root.setBarPosition(candidate)
    }

    function toggleTransparency() {
        if (!root.shell || typeof root.shell.setBarTransparent !== "function") {
            console.error("[BAR] transparency_toggle_failed reason=mutation_owner_unavailable")
            return "not-ready"
        }
        var result = String(root.shell.setBarTransparent("toggle") || "")
        if (result === "ok") console.info("[BAR] transparency_toggled")
        else console.error("[BAR] transparency_toggle_failed detail=" + result)
        return result
    }

    function colorHex(value) {
        var colorValue = value
        if (typeof colorValue === "string") colorValue = Qt.color(colorValue)
        if (!colorValue) return "#ffffff"
        function channel(number) {
            var encoded = Math.round(Math.max(0, Math.min(1, Number(number) || 0)) * 255).toString(16)
            return encoded.length < 2 ? "0" + encoded : encoded
        }
        return "#" + channel(colorValue.r) + channel(colorValue.g) + channel(colorValue.b)
    }

    function screenSizeArgument() {
        var activeScreen = root.screenForBar()
        var width = activeScreen ? Number(activeScreen.width) : Number(root.width)
        var height = activeScreen ? Number(activeScreen.height) : Number(root.height)
        return (isFinite(width) && width > 0 ? Math.round(width) : 0) + "x" +
            (isFinite(height) && height > 0 ? Math.round(height) : 0)
    }

    function scheduleTransparentForegroundRefresh() {
        if (!root.requestedTransparent) {
            root.transparentForeground = root.themeForeground
            root.transparentForegroundFallbackReported = false
            return
        }
        transparentForegroundTimer.restart()
    }

    function refreshTransparentForeground() {
        if (!root.requestedTransparent || transparentForegroundProcess.running) return
        if (root.barTextColorToolPath === "") {
            root.transparentForeground = root.themeForeground
            if (!root.transparentForegroundFallbackReported) {
                root.transparentForegroundFallbackReported = true
                console.warn("[BAR] transparent_foreground_fallback reason=helper_unavailable")
            }
            return
        }
        transparentForegroundProcess.command = [
            root.barTextColorToolPath,
            root.position,
            String(root.barSize),
            root.colorHex(root.themeForeground),
            root.colorHex(root.themeContrastForeground),
            "--screen",
            root.screenSizeArgument()
        ]
        transparentForegroundProcess.running = true
    }

    function reportBarFacadeState() {
        if (root.pluginHost && typeof root.pluginHost.syncScopedFacades === "function")
            Qt.callLater(function() { root.pluginHost.syncScopedFacades() })
    }

    function widgetSlotSceneRect(slot) {
        if (!slot || slot.width <= 0 || slot.height <= 0) return null
        try {
            var point = slot.mapToItem(null, 0, 0)
            return {slot: slot, x: point.x, y: point.y, width: slot.width, height: slot.height}
        } catch (error) {
            console.warn("[BAR] widget_coordinate_mapping_failed")
            return null
        }
    }

    function widgetDropMarkerFor(target, after) {
        if (!target || !barSurface) return null
        try {
            var point = target.mapToItem(barSurface, 0, 0)
            var thickness = 2
            if (root.vertical) return {
                x: Math.round(point.x),
                y: Math.round(point.y + (after ? target.height : 0) - thickness / 2),
                width: Math.max(1, target.width),
                height: thickness
            }
            return {
                x: Math.round(point.x + (after ? target.width : 0) - thickness / 2),
                y: Math.round(point.y),
                width: thickness,
                height: Math.max(1, target.height)
            }
        } catch (error) {
            console.warn("[BAR] widget_drop_marker_failed")
            return null
        }
    }

    function clearWidgetDrag() {
        root.widgetDragActive = false
        root.widgetDragSource = null
        root.widgetDragTarget = null
        root.widgetDragAfter = false
        root.widgetDropMarkerGeometry = null
    }

    function beginWidgetDrag(source, point) {
        if (!source || !root.shell || typeof root.shell.moveBarWidget !== "function") return false
        root.widgetDragActive = true
        root.widgetDragSource = source
        root.updateWidgetDrag(source, point)
        console.info("[BAR] widget_drag_started id=" + String(source.instanceId || source.pluginId || ""))
        return true
    }

    function updateWidgetDrag(source, point) {
        if (!root.widgetDragActive || root.widgetDragSource !== source) return
        var candidates = []
        for (var i = 0; i < root.widgetSlots.length; i++) {
            var candidate = root.widgetSlots[i]
            if (!candidate || candidate === source || candidate.visible !== true ||
                !candidate.widgetItem) continue
            var rect = root.widgetSlotSceneRect(candidate)
            if (rect) candidates.push(rect)
        }
        var target = BarInteractionModel.nearestDropTarget(candidates, point, root.vertical)
        root.widgetDragTarget = target ? target.slot : null
        root.widgetDragAfter = target ? target.after === true : false
        root.widgetDropMarkerGeometry = target
            ? root.widgetDropMarkerFor(target.slot, target.after === true) : null
    }

    function endWidgetDrag(source) {
        if (!root.widgetDragActive || root.widgetDragSource !== source) return "ok"
        var target = root.widgetDragTarget
        var after = root.widgetDragAfter
        root.clearWidgetDrag()
        if (!target || target === source) return "ok"

        var sourceId = String(source.instanceId || source.pluginId || "")
        var targetId = String(target.instanceId || target.pluginId || "")
        var placement = BarInteractionModel.placementForDrop(sourceId, targetId, target.region, after)
        if (!placement) {
            console.error("[BAR] widget_drag_failed reason=invalid_target")
            return "invalid-target"
        }
        var result = String(root.shell.moveBarWidget(sourceId, JSON.stringify(placement)) || "")
        if (result === "ok") console.info("[BAR] widget_drag_committed id=" + sourceId +
            " section=" + target.region + " relation=" + (after ? "after" : "before") +
            " target=" + targetId)
        else console.error("[BAR] widget_drag_failed id=" + sourceId + " detail=" + result)
        return result
    }

    function cancelWidgetDrag(source) {
        if (root.widgetDragSource === source) root.clearWidgetDrag()
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

    function startHiddenStateWatcher() {
        if (!hiddenStateDirectoryPresent || hiddenStateDirectory === "" ||
            !hiddenStateWatcher) return
        hiddenStateWatcher.start()
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
            themeText: String(barRoot.foreground),
            themeForeground: String(barRoot.themeForeground),
            transparentForeground: String(barRoot.transparentForeground),
            foregroundFallback: barRoot.transparentForegroundFallbackReported,
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
                if (present) barRoot.startHiddenStateWatcher()
                else if (hiddenStateWatcher) hiddenStateWatcher.active = false
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

    property QtObject hiddenStateWatcher: BarHiddenWatcher {
        directory: barRoot.hiddenStateDirectory
        active: barRoot.hiddenStateDirectoryPresent
        onSyncRequested: function(path) {
            if (String(path || "") !== "") barRoot.syncHidden()
        }
    }

    Timer {
        id: hiddenStateDirectoryTimer
        interval: 500
        running: true
        repeat: true
        onTriggered: barRoot.probeHiddenStateDirectory()
    }

    Timer {
        id: hiddenStateResyncTimer
        interval: 1500
        running: !barRoot.hiddenStateDirectoryPresent || barRoot.hiddenStateWatcherUnavailable
        repeat: true
        onTriggered: {
            barRoot.syncHidden()
            barRoot.probeHiddenStateDirectory()
            if (barRoot.hiddenStateDirectoryPresent) barRoot.startHiddenStateWatcher()
        }
    }

    Timer {
        id: transparentForegroundTimer
        interval: 120
        repeat: false
        onTriggered: barRoot.refreshTransparentForeground()
    }

    Timer {
        id: transparentForegroundRefreshTimer
        interval: 2500
        running: barRoot.requestedTransparent
        repeat: true
        onTriggered: barRoot.refreshTransparentForeground()
    }

    Process {
        id: transparentForegroundProcess
        command: []
        running: false
        stdout: StdioCollector { id: transparentForegroundOutput; waitForEnd: true }
        stderr: StdioCollector { id: transparentForegroundError; waitForEnd: true }
        onExited: function(code) {
            var value = String(transparentForegroundOutput.text || "").trim()
            var detail = String(transparentForegroundError.text || "").trim()
            if (code === 0 && /^#[0-9A-Fa-f]{6}$/.test(value)) {
                barRoot.transparentForeground = value
                barRoot.reportBarFacadeState()
                if (detail !== "" && !barRoot.transparentForegroundFallbackReported) {
                    barRoot.transparentForegroundFallbackReported = true
                    console.warn("[BAR] transparent_foreground_fallback detail=" + detail)
                } else if (detail === "") {
                    barRoot.transparentForegroundFallbackReported = false
                }
                return
            }
            if (!barRoot.transparentForegroundFallbackReported) {
                barRoot.transparentForegroundFallbackReported = true
                console.error("[BAR] transparent_foreground_failed code=" + code +
                    (detail === "" ? "" : " detail=" + detail))
            }
            barRoot.transparentForeground = barRoot.themeForeground
            barRoot.reportBarFacadeState()
        }
    }

    onRequestedTransparentChanged: {
        barRoot.scheduleTransparentForegroundRefresh()
        barRoot.reportBarFacadeState()
    }
    onPositionChanged: {
        barRoot.scheduleTransparentForegroundRefresh()
        barRoot.reportBarFacadeState()
    }
    onThemeForegroundChanged: {
        barRoot.scheduleTransparentForegroundRefresh()
        barRoot.reportBarFacadeState()
    }
    onThemeContrastForegroundChanged: {
        barRoot.scheduleTransparentForegroundRefresh()
        barRoot.reportBarFacadeState()
    }
    onBarHiddenChanged: barRoot.reportBarFacadeState()

    Component.onCompleted: {
        barRoot.syncHidden()
        barRoot.probeHiddenStateDirectory()
        if (barRoot.hiddenStateDirectoryPresent) barRoot.startHiddenStateWatcher()
        barRoot.scheduleTransparentForegroundRefresh()
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
                    region: "left"
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
                region: "right"
            }
        }

        Rectangle {
            id: widgetDropMarker
            readonly property var geometry: barRoot.widgetDropMarkerGeometry
            visible: barRoot.widgetDragActive && geometry !== null
            x: geometry ? geometry.x : 0
            y: geometry ? geometry.y : 0
            width: geometry ? geometry.width : 0
            height: geometry ? geometry.height : 0
            radius: Math.min(width, height) / 2
            color: barRoot.barForeground
            z: 100
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: barMovePreviewWindow
                required property var modelData

                readonly property bool screenMatches: barRoot.barMoveScreen === modelData ||
                    (barRoot.barMoveScreen && modelData && barRoot.barMoveScreen.name && modelData.name &&
                        String(barRoot.barMoveScreen.name) === String(modelData.name))

                screen: modelData
                visible: barRoot.barMoveActive && screenMatches
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "aurelia-bar-move-preview"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true
                mask: Region {}

                Repeater {
                    model: ["top", "bottom", "left", "right"]

                    Rectangle {
                        required property string modelData
                        readonly property bool edgeVertical: modelData === "left" || modelData === "right"
                        readonly property int edgeSize: edgeVertical
                            ? Theme.bar.sizeVertical : Theme.bar.sizeHorizontal
                        x: modelData === "right" ? parent.width - edgeSize : 0
                        y: modelData === "bottom" ? parent.height - edgeSize : 0
                        width: edgeVertical ? edgeSize : parent.width
                        height: edgeVertical ? parent.height : edgeSize
                        color: barRoot.barForeground
                        opacity: barRoot.barMoveCandidate === modelData
                            ? (barRoot.transparent ? 0.42 : 0.68) : 0
                        visible: opacity > 0

                        Behavior on opacity {
                            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        }
    }
}
