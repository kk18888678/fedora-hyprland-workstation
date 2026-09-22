import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "BarInteractionModel.js" as BarInteractionModel
import "BarTransparencyModel.js" as BarTransparencyModel
import "."

// Aurelia's first bar host follows the Omarchy boundary: the host owns the
// bar surface and configuration, while each configured module is a manifest-
// backed `bar-widget` entry point. The bar is mounted by the resident host;
// Noctalia remains independently selectable as the active desktop shell.
Item {
    id: barRoot

    property string aureliaPath: String(Qt.resolvedUrl("../../")).replace(/^file:\/\//, "")
    property var shell: null
    property var shellConfig: null
    property var manifest: ({})
    property var pluginRegistry: null
    property var barWidgetRegistry: null
    property var pluginHost: null
    property var widgetSlots: []
    property var barPanels: []
    property int widgetRevision: 0
    property bool barMoveActive: false
    property string barMoveCandidate: ""
    property var barMoveScreen: null
    property var barMovePanel: null
    property bool widgetDragActive: false
    property var widgetDragSource: null
    property var widgetDragPanel: null
    property var widgetDragTarget: null
    property bool widgetDragAfter: false
    property var widgetDropMarkerGeometry: null
    property real widgetDragLastSceneX: NaN
    property real widgetDragLastSceneY: NaN

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
    property bool transparentForegroundAidStrong: false
    property bool foregroundAnimationEnabled: true
    readonly property color foreground: requestedTransparent ? transparentForeground : themeForeground
    readonly property color barForeground: foreground
    readonly property color background: Theme.bar.background
    readonly property color urgent: Theme.bar.active
    // The user's explicit transparency choice is always honoured. A transparent
    // bar renders no surface and no scrim. When the sampled wallpaper cannot
    // provide a legible foreground the helper emits its `action=halo` signal;
    // the bar responds by strengthening the non-surface legibility halo behind
    // the content, never by drawing a background plane or forcing an opaque
    // surface that would override the user's setting.
    readonly property var transparentRender: BarTransparencyModel.renderState(
        requestedTransparent, transparentForegroundAidStrong)
    readonly property bool transparent: transparentRender.transparent
    readonly property bool transparentHalo: transparentRender.halo
    readonly property bool transparentHaloStrong: transparentRender.haloStrong
    // The halo colour contrasts the resolved foreground so it stays visible
    // over both light and dark wallpaper patches. It is a shadow behind glyphs
    // and icons, never a background plane.
    readonly property color transparentHaloColor: {
        var fg = barRoot.barForeground
        var luminance = 0.2126 * fg.r + 0.7152 * fg.g + 0.0722 * fg.b
        return luminance > 0.5 ? "#000000" : "#ffffff"
    }
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

    function registerBarPanel(panel) {
        if (!panel || barPanels.indexOf(panel) !== -1) return
        var next = barPanels.slice()
        next.push(panel)
        barPanels = next
    }

    function unregisterBarPanel(panel) {
        barPanels = barPanels.filter(function(item) { return item !== panel })
        if (barMovePanel === panel) clearBarMove()
        if (widgetDragPanel === panel) clearWidgetDrag()
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

    function focusedScreenName() {
        try {
            return Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
        } catch (error) {
            console.warn("[BAR] focused_monitor_read_failed")
            return ""
        }
    }

    function panelScreenName(panel) {
        return panel && panel.screen ? String(panel.screen.name || "") : ""
    }

    function slotScreenName(slot) {
        return slot && slot.barPanel ? barRoot.panelScreenName(slot.barPanel) : ""
    }

    function visibleSlot(slot) {
        return !!slot && slot.visible === true && slot.width > 0 && slot.height > 0 &&
            !!slot.widgetItem
    }

    function chooseWidgetSlot(candidates) {
        var visible = candidates.filter(barRoot.visibleSlot)
        if (visible.length === 0) visible = candidates.filter(function(slot) { return !!slot })
        if (visible.length === 0) return {slot: null, ambiguous: false}

        var focused = barRoot.focusedScreenName()
        if (focused !== "") {
            var onFocused = visible.filter(function(slot) {
                return barRoot.slotScreenName(slot) === focused
            })
            if (onFocused.length > 0) visible = onFocused
        }
        if (visible.length === 1) return {slot: visible[0], ambiguous: false}

        // One configured widget is replicated once per monitor. It is not an
        // ambiguous instance; select the first drawn copy when no focused
        // monitor has been reported. Duplicate entries on one monitor remain
        // ambiguous and are rejected by the caller.
        var firstScreen = barRoot.slotScreenName(visible[0])
        var sameScreen = visible.filter(function(slot) {
            return barRoot.slotScreenName(slot) === firstScreen
        })
        return {slot: sameScreen.length === 1 ? sameScreen[0] : null,
            ambiguous: sameScreen.length > 1}
    }

    function anchorItemFor(pluginId) {
        var matches = []
        for (var i = 0; i < widgetSlots.length; i++) {
            var slot = widgetSlots[i]
            if (slot && slot.pluginId === pluginId) matches.push(slot)
        }
        var selected = barRoot.chooseWidgetSlot(matches)
        return selected.ambiguous ? null : selected.slot
    }

    function barAnchorItem() {
        var focused = barRoot.focusedScreenName()
        var panels = barRoot.barPanels.filter(function(panel) {
            return panel && panel.contentAnchorItem
        })
        if (focused !== "") {
            var focusedPanel = panels.filter(function(panel) {
                return barRoot.panelScreenName(panel) === focused
            })
            if (focusedPanel.length > 0) return focusedPanel[0].contentAnchorItem
        }
        return panels.length > 0 ? panels[0].contentAnchorItem : null
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
        var selected = barRoot.chooseWidgetSlot(exactMatches)
        if (selected.ambiguous) return "ambiguous"
        if (selected.slot) return selected.slot.invoke(method, argument)
        selected = barRoot.chooseWidgetSlot(baseMatches)
        if (selected.ambiguous) return "ambiguous"
        if (selected.slot) return selected.slot.invoke(method, argument)
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
        var focused = barRoot.focusedScreenName()
        if (focused !== "") {
            for (var i = 0; i < barPanels.length; i++) {
                var focusedPanel = barPanels[i]
                if (focusedPanel && barRoot.panelScreenName(focusedPanel) === focused)
                    return focusedPanel.screen
            }
            try {
                if (Quickshell.screens) {
                    for (var screenIndex = 0; screenIndex < Quickshell.screens.length; screenIndex++) {
                        var focusedScreen = Quickshell.screens[screenIndex]
                        if (focusedScreen && String(focusedScreen.name || "") === focused)
                            return focusedScreen
                    }
                }
            } catch (error) {
                console.warn("[BAR] screen_lookup_failed")
            }
        }
        if (barPanels.length > 0 && barPanels[0].screen) return barPanels[0].screen
        try {
            if (Quickshell.screens && Quickshell.screens.length > 0) return Quickshell.screens[0]
        } catch (error2) {
            console.warn("[BAR] screen_fallback_failed")
        }
        return null
    }

    function screenPointFromItem(item, x, y, panel) {
        var point = {x: Number(x) || 0, y: Number(y) || 0}
        try {
            if (item && typeof item.mapToItem === "function") point = item.mapToItem(null, point.x, point.y)
        } catch (error) {
            console.warn("[BAR] coordinate_mapping_failed")
            return point
        }

        var activePanel = panel || barRoot.barMovePanel
        var activeScreen = activePanel && activePanel.screen ? activePanel.screen : barRoot.screenForBar()
        if (!activeScreen) return point
        var screenWidth = Number(activeScreen.width) || 0
        var screenHeight = Number(activeScreen.height) || 0
        var panelWidth = activePanel ? Number(activePanel.width || 0) : 0
        var panelHeight = activePanel ? Number(activePanel.height || 0) : 0
        if (barRoot.position === "bottom") point.y += Math.max(0, screenHeight - panelHeight)
        else if (barRoot.position === "right") point.x += Math.max(0, screenWidth - panelWidth)
        return point
    }

    function screenPointForDrag(point) {
        var activeScreen = barRoot.screenForBar()
        if (!activeScreen) return point || {x: 0, y: 0}
        return {
            x: Math.max(0, Math.min(Number(activeScreen.width) || 0, Number(point && point.x) || 0)),
            y: Math.max(0, Math.min(Number(activeScreen.height) || 0, Number(point && point.y) || 0))
        }
    }

    function beginBarMove(panel) {
        barRoot.barMovePanel = panel || null
        barRoot.barMoveScreen = panel && panel.screen ? panel.screen : barRoot.screenForBar()
        barRoot.barMoveCandidate = barRoot.position
        barRoot.barMoveActive = !!barRoot.barMoveScreen
        if (barRoot.barMoveActive) console.info("[BAR] direct_move_started")
        else console.error("[BAR] direct_move_failed reason=screen_unavailable")
    }

    function updateBarMove(point) {
        if (!barRoot.barMoveActive || !barRoot.barMoveScreen) return
        barRoot.barMoveCandidate = BarInteractionModel.nearestScreenEdge(point,
            barRoot.barMoveScreen.width, barRoot.barMoveScreen.height)
    }

    function clearBarMove() {
        barRoot.barMoveActive = false
        barRoot.barMoveCandidate = ""
        barRoot.barMoveScreen = null
        barRoot.barMovePanel = null
    }

    function setBarPosition(value) {
        var requested = String(value || "")
        if (["top", "bottom", "left", "right"].indexOf(requested) === -1) {
            console.error("[BAR] direct_move_failed reason=invalid_position value=" + requested)
            return "invalid-position"
        }
        if (!barRoot.shell || typeof barRoot.shell.setBarPosition !== "function") {
            console.error("[BAR] direct_move_failed reason=mutation_owner_unavailable")
            return "not-ready"
        }
        var result = String(barRoot.shell.setBarPosition(requested) || "")
        if (result === "ok") console.info("[BAR] direct_move_committed position=" + requested)
        else console.error("[BAR] direct_move_failed position=" + requested + " detail=" + result)
        return result
    }

    function finishBarMove() {
        var candidate = barRoot.barMoveCandidate
        if (!barRoot.barMoveActive || candidate === "" || candidate === barRoot.position) {
            barRoot.clearBarMove()
            return "ok"
        }
        barRoot.clearBarMove()
        return barRoot.setBarPosition(candidate)
    }

    function toggleTransparency() {
        if (!barRoot.shell || typeof barRoot.shell.setBarTransparent !== "function") {
            console.error("[BAR] transparency_toggle_failed reason=mutation_owner_unavailable")
            return "not-ready"
        }
        var result = String(barRoot.shell.setBarTransparent("toggle") || "")
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
        var activeScreen = barRoot.screenForBar()
        var width = activeScreen ? Number(activeScreen.width) : Number(barRoot.width)
        var height = activeScreen ? Number(activeScreen.height) : Number(barRoot.height)
        return (isFinite(width) && width > 0 ? Math.round(width) : 0) + "x" +
            (isFinite(height) && height > 0 ? Math.round(height) : 0)
    }

    function scheduleTransparentForegroundRefresh() {
        if (!barRoot.requestedTransparent) {
            barRoot.transparentForeground = barRoot.themeForeground
            barRoot.transparentForegroundFallbackReported = false
            barRoot.transparentForegroundAidStrong = false
            return
        }
        transparentForegroundTimer.restart()
    }

    function refreshTransparentForeground() {
        if (!barRoot.requestedTransparent || transparentForegroundProcess.running) return
        if (barRoot.barTextColorToolPath === "") {
            barRoot.transparentForeground = barRoot.themeForeground
            // The helper is unavailable, so contrast is unverified. Fail safe
            // to the strong halo rather than assuming the theme foreground is
            // legible over the wallpaper.
            barRoot.transparentForegroundAidStrong = true
            if (!barRoot.transparentForegroundFallbackReported) {
                barRoot.transparentForegroundFallbackReported = true
                console.warn("[BAR] transparent_foreground_fallback reason=helper_unavailable")
            }
            return
        }
        transparentForegroundProcess.command = [
            barRoot.barTextColorToolPath,
            barRoot.position,
            String(barRoot.barSize),
            barRoot.colorHex(barRoot.themeForeground),
            barRoot.colorHex(barRoot.themeContrastForeground),
            "--screen",
            barRoot.screenSizeArgument()
        ]
        transparentForegroundProcess.running = true
    }

    function reportBarFacadeState() {
        if (barRoot.pluginHost && typeof barRoot.pluginHost.syncScopedFacades === "function")
            Qt.callLater(function() { barRoot.pluginHost.syncScopedFacades() })
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

    function clearWidgetDrag() {
        barRoot.widgetDragActive = false
        barRoot.widgetDragSource = null
        barRoot.widgetDragPanel = null
        barRoot.widgetDragTarget = null
        barRoot.widgetDragAfter = false
        barRoot.widgetDropMarkerGeometry = null
        barRoot.widgetDragLastSceneX = NaN
        barRoot.widgetDragLastSceneY = NaN
    }

    function beginWidgetDrag(source, point) {
        if (!source || !barRoot.shell || typeof barRoot.shell.moveBarWidget !== "function") return false
        barRoot.widgetDragActive = true
        barRoot.widgetDragSource = source
        barRoot.widgetDragPanel = source.barPanel || null
        barRoot.widgetDragLastSceneX = NaN
        barRoot.widgetDragLastSceneY = NaN
        barRoot.updateWidgetDrag(source, point)
        console.info("[BAR] widget_drag_started id=" + String(source.instanceId || source.pluginId || ""))
        return true
    }

    function updateWidgetDrag(source, point) {
        if (!barRoot.widgetDragActive || barRoot.widgetDragSource !== source) return
        var sceneX = Number(point && point.x)
        var sceneY = Number(point && point.y)
        if (isFinite(barRoot.widgetDragLastSceneX) && isFinite(barRoot.widgetDragLastSceneY) &&
            Math.abs(sceneX - barRoot.widgetDragLastSceneX) < 2 &&
            Math.abs(sceneY - barRoot.widgetDragLastSceneY) < 2) return
        barRoot.widgetDragLastSceneX = sceneX
        barRoot.widgetDragLastSceneY = sceneY
        var panel = barRoot.widgetDragPanel || source.barPanel || null
        var candidates = []
        for (var i = 0; i < barRoot.widgetSlots.length; i++) {
            var candidate = barRoot.widgetSlots[i]
            if (!candidate || candidate === source || candidate.visible !== true ||
                !candidate.widgetItem || (panel && candidate.barPanel !== panel)) continue
            var rect = barRoot.widgetSlotSceneRect(candidate)
            if (rect) candidates.push(rect)
        }
        var target = BarInteractionModel.nearestDropTarget(candidates, point, barRoot.vertical)
        barRoot.widgetDragTarget = target ? target.slot : null
        barRoot.widgetDragAfter = target ? target.after === true : false
        barRoot.widgetDropMarkerGeometry = target && panel &&
            typeof panel.widgetDropMarkerFor === "function"
            ? panel.widgetDropMarkerFor(target.slot, target.after === true) : null
    }

    function endWidgetDrag(source) {
        if (!barRoot.widgetDragActive || barRoot.widgetDragSource !== source) return "ok"
        var target = barRoot.widgetDragTarget
        var after = barRoot.widgetDragAfter
        barRoot.clearWidgetDrag()
        if (!target || target === source) return "ok"

        var sourceId = String(source.instanceId || source.pluginId || "")
        var targetId = String(target.instanceId || target.pluginId || "")
        var placement = BarInteractionModel.placementForDrop(sourceId, targetId, target.region, after)
        if (!placement) {
            console.error("[BAR] widget_drag_failed reason=invalid_target")
            return "invalid-target"
        }
        var result = String(barRoot.shell.moveBarWidget(sourceId, JSON.stringify(placement)) || "")
        if (result === "ok") console.info("[BAR] widget_drag_committed id=" + sourceId +
            " section=" + target.region + " relation=" + (after ? "after" : "before") +
            " target=" + targetId)
        else console.error("[BAR] widget_drag_failed id=" + sourceId + " detail=" + result)
        return result
    }

    function cancelWidgetDrag(source) {
        if (barRoot.widgetDragSource === source) barRoot.clearWidgetDrag()
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
        var panel = barRoot.barPanels.length > 0 ? barRoot.barPanels[0] : null
        var focused = barRoot.focusedScreenName()
        for (var panelIndex = 0; panelIndex < barRoot.barPanels.length; panelIndex++) {
            var candidate = barRoot.barPanels[panelIndex]
            if (candidate && barRoot.panelScreenName(candidate) === focused) {
                panel = candidate
                break
            }
        }
        return JSON.stringify({
            visible: panel ? panel.visible === true : barRoot.visible,
            hidden: barRoot.barHidden,
            hiddenState: barRoot.hiddenStateReadState,
            hiddenStateError: barRoot.hiddenStateReadError,
            transparent: barRoot.transparent,
            surface: panel ? panel.surfaceColor : "",
            border: panel ? panel.surfaceBorderColor : "",
            themeBackground: String(Theme.bar.background),
            themeAccent: String(Theme.bar.active),
            themeText: String(barRoot.foreground),
            themeForeground: String(barRoot.themeForeground),
            transparentForeground: String(barRoot.transparentForeground),
            foregroundFallback: barRoot.transparentForegroundFallbackReported,
            foregroundAidStrong: barRoot.transparentForegroundAidStrong,
            transparentHalo: barRoot.transparentHalo,
            transparentHaloStrong: barRoot.transparentHaloStrong,
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
            // Any helper diagnostic or non-zero exit means contrast was not
            // verified. The helper emits `action=halo` for that case, but the
            // bar also fails safe on any diagnostic so a missed or malformed
            // signal can never leave content unreadable. The response is the
            // stronger non-surface content halo, never a scrim or a forced
            // opaque surface.
            var signal = BarTransparencyModel.parseForegroundSignal(detail)
            var contrastUnverified = code !== 0 || detail !== ""
            if (code === 0 && /^#[0-9A-Fa-f]{6}$/.test(value)) {
                barRoot.transparentForeground = value
                barRoot.transparentForegroundAidStrong = contrastUnverified || signal.strengthenAid
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
            // A missing or invalid helper result also leaves contrast
            // unverified, so the strong halo is the fail-safe state.
            barRoot.transparentForegroundAidStrong = true
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

    // Omarchy creates the mapped bar surface once per monitor. Keeping this
    // variant boundary in the resident host is what prevents a position or
    // monitor transition from reusing one window's stale global geometry.
    Variants {
        model: Quickshell.screens

        delegate: Component {
            BarPanel {
                required property var modelData
                bar: barRoot
                screenModel: modelData
            }
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
