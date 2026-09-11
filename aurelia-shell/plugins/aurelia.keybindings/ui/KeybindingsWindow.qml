import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "."
import "../../../theme"
import "../../../ui"

// Aurelia Keybindings is a first-party shell component hosted by the resident
// Aurelia Shell. This Window owns lifecycle, navigation, capture state, and
// controller contracts; visual/input surfaces are composed from the sibling
// components below.
PanelWindow {
    id: windowRoot

    property var anchorWindow: null

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aurelia-keybindings"
    WlrLayershell.keyboardFocus: windowRoot.browseActive ? WlrKeyboardFocus.None : (windowRoot.isRecording ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
    mask: windowRoot.browseActive ? browseRegion : null

    Region {
        id: browseRegion
        item: surfaceCard
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: KeybindingsConfig.palettePreferredWidth
    implicitHeight: KeybindingsConfig.palettePreferredHeight
    color: "transparent"

    property bool browseActive: false
    property string captureState: "idle"
    property int initiatingKey: 0
    property string candidateKey: ""
    property var conflictItem: null
    property var recordingItem: null
    property bool isActivating: false
    property bool activationGestureHeld: false
    property int activationGestureKey: 0

    property bool isRecording: (captureState === "entering_capture" || captureState === "capture_armed" || captureState === "validating" || captureState === "conflict" || keybindingsModel.operationState === "capturing" || keybindingsModel.operationState === "conflict")

    property alias keybindingsModel: keybindingsModel
    property alias hotkeysModel: keybindingsModel

    // Stable controller contract consumed by the visual/input surfaces.
    function focusSearch() {
        header.focusSearch()
    }

    function appendSearchText(value) {
        header.appendSearchText(value)
    }

    function beginSearch(value) {
        header.beginSearch(value)
    }

    function focusList() {
        actionList.focusList()
    }

    function clearSearch() {
        header.clearSearch()
    }

    function focusSettings() {
        if (settingsView) settingsView.forceActiveFocus()
    }

    function eventMatchesShortcut(event, shortcutStr): bool {
        if (!shortcutStr || !event) return false
        var target = shortcutStr.trim().toUpperCase()
        var actual = formatKeyEvent(event)
        if (actual === target) return true
        if (target.indexOf("+") === -1) {
            if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
                    return String.fromCharCode(event.key) === target
                }
            }
        }
        return false
    }

    function hasModifier(shortcutStr): bool {
        if (!shortcutStr) return false
        var upper = shortcutStr.toUpperCase()
        return upper.indexOf("ALT") !== -1 || upper.indexOf("CTRL") !== -1 || upper.indexOf("SUPER") !== -1 || upper.indexOf("MOD") !== -1
    }

    function resolveSemanticCommand(event, context): string {
        if (!event) return ""
        var isTextInput = context === "text_input"
        if (eventMatchesShortcut(event, Theme.shortcutAddAction)) {
            if (!isTextInput || hasModifier(Theme.shortcutAddAction)) return "add_action"
        }
        if (eventMatchesShortcut(event, Theme.shortcutBack)) {
            if (!isTextInput || hasModifier(Theme.shortcutBack)) return "back"
        }
        if (eventMatchesShortcut(event, Theme.shortcutSet)) {
            if (!isTextInput || hasModifier(Theme.shortcutSet)) return "set_binding"
        }
        if (eventMatchesShortcut(event, Theme.shortcutUnset)) {
            if (!isTextInput || hasModifier(Theme.shortcutUnset)) return "unset_binding"
        }
        return ""
    }

    function handleComponentKey(event, context): bool {
        if (windowRoot.isRecording) return windowRoot.handleRecordingKeyPress(event)

        if (event.key === Qt.Key_Escape) {
            windowRoot.goBack()
            event.accepted = true
            return true
        }

        var cmd = resolveSemanticCommand(event, context)
        if (cmd === "add_action") {
            windowRoot.openAddAction()
            event.accepted = true
            return true
        } else if (cmd === "back") {
            windowRoot.goBack()
            event.accepted = true
            return true
        } else if (cmd === "set_binding") {
            if (keybindingsModel.activeView === "bound" || keybindingsModel.activeView === "unbound") {
                var item = keybindingsModel.selectedItem
                if (item) {
                    windowRoot.startCapture(item, event)
                    event.accepted = true
                    return true
                }
            }
            event.accepted = true
            return true
        } else if (cmd === "unset_binding") {
            if (keybindingsModel.activeView === "bound" || keybindingsModel.activeView === "unbound") {
                var itemUnset = keybindingsModel.selectedItem
                if (itemUnset) {
                    if (itemUnset.editable !== true) {
                        keybindingsModel.operationState = "error"
                        keybindingsModel.operationMessage = "Immutable: System binding cannot be modified."
                    } else {
                        keybindingsModel.unsetShortcut(itemUnset.id)
                    }
                    event.accepted = true
                    return true
                }
            }
            event.accepted = true
            return true
        }
        return false
    }

    // Immediate top-level view cycling: Bound -> Unbound -> Add Action ->
    // Settings -> Bound. Reverse traversal is the exact inverse.
    function cycleTopLevelView(forward: bool) {
        if (windowRoot.isRecording) return
        windowRoot.resetPointerGate()

        var current = keybindingsModel.activeView
        var nextView = "bound"
        if (forward) {
            if (current === "bound") nextView = "unbound"
            else if (current === "unbound") nextView = "add_action_type"
            else if (current.indexOf("add_") === 0) nextView = "settings"
        } else {
            if (current === "bound") nextView = "settings"
            else if (current === "settings") nextView = "add_action_type"
            else if (current.indexOf("add_") === 0) nextView = "unbound"
        }

        console.info("[EVENT] keybindings.view.cycle from=" + current + " to=" + nextView + " forward=" + forward)
        keybindingsModel.switchView(nextView)
        focusActiveView(nextView)
    }

    function focusActiveView(view): void {
        if (view === "bound" || view === "unbound" || view === "add_app") focusList()
        else if (view === "add_action_type") addActionPicker.focusPicker()
        else if (view === "add_exec") executableForm.focusFirstField()
        else if (view === "settings") focusSettings()
    }

    function startCapture(item, triggerEvent) {
        if (!item) return
        if (item.editable !== true) {
            keybindingsModel.operationState = "error"
            keybindingsModel.operationMessage = "Immutable: System binding cannot be modified."
            return
        }
        recordingItem = item
        conflictItem = null
        candidateKey = ""
        if (triggerEvent && triggerEvent.key) {
            initiatingKey = triggerEvent.key
            captureState = "entering_capture"
            keybindingsModel.operationState = "capturing"
            keybindingsModel.operationMessage = "Release key to begin shortcut recording..."
        } else {
            initiatingKey = 0
            captureState = "capture_armed"
            keybindingsModel.operationState = "capturing"
            keybindingsModel.operationMessage = "Set " + (item.description || "Shortcut") + " — press a modifier and key combination..."
        }
    }

    function cancelCapture() {
        captureState = "idle"
        initiatingKey = 0
        recordingItem = null
        conflictItem = null
        candidateKey = ""
        if (keybindingsModel.operationState !== "idle") {
            keybindingsModel.operationState = "idle"
            keybindingsModel.operationMessage = ""
        }
    }

    function openAddAction() {
        if (keybindingsModel.activeView.indexOf("add_") === 0) return
        keybindingsModel.switchView("add_action_type")
        focusActiveView("add_action_type")
    }

    function requestClose(reason) {
        if (windowRoot.browseActive) {
            console.warn("[LIFECYCLE] keybindings.window.close.request rejected reason=" + (reason || "unknown") + " (browseActive=true)")
            return
        }
        console.info("[LIFECYCLE] keybindings.window.close.request reason=" + (reason || "unknown") + " view=" + keybindingsModel.activeView)
        windowRoot.visible = false
        if (anchorWindow && typeof anchorWindow.releasePopout === "function") anchorWindow.releasePopout(windowRoot)
    }

    function goBack() {
        windowRoot.resetPointerGate()
        if (windowRoot.isRecording || keybindingsModel.operationState !== "idle") {
            cancelCapture()
            return
        }
        var view = keybindingsModel.activeView
        console.info("[EVENT] keybindings.navigation.back from_view=" + view)
        if (view === "add_app" || view === "add_exec") {
            keybindingsModel.switchView("add_action_type")
            focusActiveView("add_action_type")
        } else if (view === "add_action_type" || view === "settings") {
            var dest = keybindingsModel.previousRootView || "bound"
            keybindingsModel.switchView(dest)
            focusActiveView(dest)
        } else {
            windowRoot.requestClose("escape-from-root")
        }
    }

    // A Return/Enter gesture becomes eligible again only after its matching
    // release. Auto-repeat and a held key cannot cross a view transition.
    function isReturnOrEnter(event): bool {
        return event && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
    }

    function claimActivationKey(event): bool {
        if (!isReturnOrEnter(event)) return true
        if (event.isAutoRepeat === true || activationGestureHeld) return false
        activationGestureHeld = true
        activationGestureKey = event.key
        return true
    }

    function handleActivationKeyRelease(event): bool {
        if (!isReturnOrEnter(event)) return false
        if (activationGestureHeld && activationGestureKey === event.key) {
            activationGestureHeld = false
            activationGestureKey = 0
        }
        event.accepted = true
        return true
    }

    function activateSelected(): bool {
        var source = arguments.length > 0 ? arguments[0] : "keyboard"
        console.info("[EVENT] keybindings.activate.begin source=" + source + " view=" + keybindingsModel.activeView + " selIdx=" + keybindingsModel.selectedIndex + " item=" + (keybindingsModel.selectedItem ? (keybindingsModel.selectedItem.id || keybindingsModel.selectedItem.display_key) : "null"))
        if (keybindingsModel.isMutating) {
            console.warn("[EVENT] keybindings.activate.rejected reason=mutating source=" + source)
            return false
        }
        if (isActivating) {
            console.warn("[EVENT] keybindings.activate.rejected reason=reentrancy_guard")
            return false
        }

        isActivating = true
        try {
            var view = keybindingsModel.activeView
            var item = keybindingsModel.selectedItem
            if (view === "add_action_type") {
                if (!item) {
                    console.warn("[NAV] activateSelected: add_action_type with no selected item")
                    return false
                }
                if (item.action_type_kind === "application") {
                    console.info("[EVENT] keybindings.application_picker.open")
                    keybindingsModel.switchView("add_app")
                    focusActiveView("add_app")
                    return true
                } else if (item.action_type_kind === "executable") {
                    console.info("[EVENT] keybindings.executable_form.open")
                    keybindingsModel.switchView("add_exec")
                    focusActiveView("add_exec")
                    return true
                }
                console.warn("[NAV] activateSelected: unexpected action_type_kind: " + (item.action_type_kind || "undefined"))
                return false
            } else if (view === "add_app") {
                if (item && item.desktop_id) {
                    console.info("[EVENT] keybindings.application.add desktop_id=" + item.desktop_id)
                    keybindingsModel.addApplication(item.desktop_id)
                    return true
                }
                console.warn("[NAV] activateSelected: add_app with no desktop_id")
                return false
            } else if (view === "bound" || view === "unbound") {
                if (item && item.runnable === true) {
                    console.info("[EVENT] keybindings.run.request action_id=" + item.id)
                    if (keybindingsModel.runSelected()) {
                        console.info("[EVENT] keybindings.run.result ok=true")
                        windowRoot.requestClose("action-run-success")
                        return true
                    }
                    console.warn("[EVENT] keybindings.run.result ok=false")
                }
                return false
            } else if (view === "add_exec") {
                executableForm.submitExecForm()
                return true
            }
            console.warn("[NAV] activateSelected: unknown view: " + view)
            return false
        } finally {
            isActivating = false
            console.info("[EVENT] keybindings.activate.end")
        }
    }

    function handleRecordingKeyRelease(event) {
        if (captureState === "entering_capture") {
            if (event.key === initiatingKey || event.modifiers === Qt.NoModifier) {
                initiatingKey = 0
                captureState = "capture_armed"
                keybindingsModel.operationState = "capturing"
                keybindingsModel.operationMessage = "Set " + (recordingItem ? recordingItem.description : "Shortcut") + " — press a modifier and key combination..."
            }
            event.accepted = true
        }
    }

    function handleRecordingKeyPress(event): bool {
        if (!isRecording) return false
        if (event.isAutoRepeat === true) {
            event.accepted = true
            return true
        }
        if (isReturnOrEnter(event) && !claimActivationKey(event)) {
            event.accepted = true
            return true
        }
        if (event.key === Qt.Key_Escape) {
            cancelCapture()
            event.accepted = true
            return true
        }
        if (captureState === "entering_capture") {
            event.accepted = true
            return true
        }
        if (captureState === "conflict") {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                var targetId = recordingItem ? recordingItem.id : ""
                var candidate = candidateKey
                cancelCapture()
                if (targetId && candidate) keybindingsModel.setShortcut(targetId, candidate, true)
                event.accepted = true
                return true
            }
            event.accepted = true
            return true
        }
        if (captureState === "validating") {
            event.accepted = true
            return true
        }

        if (captureState === "capture_armed") {
            if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                var itemToUnset = recordingItem
                cancelCapture()
                if (itemToUnset) keybindingsModel.unsetShortcut(itemToUnset.id)
                event.accepted = true
                return true
            }

            var formatted = formatKeyEvent(event)
            if (!formatted || formatted === "") {
                event.accepted = true
                return true
            }

            candidateKey = formatted
            captureState = "validating"
            keybindingsModel.operationState = "validating"
            keybindingsModel.operationMessage = "Validating " + formatted + "..."
            event.accepted = true

            keybindingsModel.validateShortcut(formatted, recordingItem.id, function(valid, err, normKey) {
                if (!isRecording) return
                if (!valid) {
                    var displayMsg = "Invalid shortcut."
                    if (err.indexOf("printable-key-requires-global-modifier") !== -1) displayMsg = "Error: Letter/number keys require Super, Ctrl, or Alt."
                    else if (err.indexOf("reserved-capture-control") !== -1) displayMsg = "Error: Standalone modifier or Escape cannot be a shortcut."
                    else if (err.indexOf("malformed-combination") !== -1) displayMsg = "Error: Invalid shortcut combination."
                    else displayMsg = "Error: " + err.replace(/^INVALID:\s*/, "")
                    keybindingsModel.operationState = "error"
                    keybindingsModel.operationMessage = displayMsg
                    captureState = "capture_armed"
                } else {
                    var finalKey = normKey || formatted
                    candidateKey = finalKey
                    var conflict = keybindingsModel.findConflict(recordingItem.id, finalKey)
                    if (conflict) {
                        if (conflict.editable === false || conflict.immutable === true) {
                            keybindingsModel.operationState = "error"
                            keybindingsModel.operationMessage = "Error: Conflicts with immutable system binding '" + (conflict.description || conflict.id) + "'. Cannot be reassigned."
                            captureState = "capture_armed"
                        } else {
                            conflictItem = conflict
                            captureState = "conflict"
                            keybindingsModel.operationState = "conflict"
                            keybindingsModel.operationMessage = "Conflicts with: " + (conflict.description || conflict.id) + ". Press Enter to reassign, or Esc to cancel."
                        }
                    } else {
                        var actionId = recordingItem.id
                        cancelCapture()
                        keybindingsModel.setShortcut(actionId, finalKey)
                    }
                }
            })
            return true
        }
        return false
    }

    function formatKeyEvent(event): string {
        var k = event.key
        if (k === Qt.Key_Control || k === Qt.Key_Shift || k === Qt.Key_Alt || k === Qt.Key_Meta) return ""

        var parts = []
        if (event.modifiers & Qt.MetaModifier) parts.push("SUPER")
        if (event.modifiers & Qt.ControlModifier) parts.push("CTRL")
        if (event.modifiers & Qt.AltModifier) parts.push("ALT")
        if (event.modifiers & Qt.ShiftModifier) parts.push("SHIFT")

        var keyName = ""
        if (k >= Qt.Key_A && k <= Qt.Key_Z) keyName = String.fromCharCode(k)
        else if (k >= Qt.Key_0 && k <= Qt.Key_9) keyName = String.fromCharCode(k)
        else if (k >= Qt.Key_F1 && k <= Qt.Key_F24) keyName = "F" + (k - Qt.Key_F1 + 1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) keyName = "RETURN"
        else if (k === Qt.Key_Space) keyName = "SPACE"
        else if (k === Qt.Key_Tab) keyName = "TAB"
        else if (k === Qt.Key_Left) keyName = "LEFT"
        else if (k === Qt.Key_Right) keyName = "RIGHT"
        else if (k === Qt.Key_Up) keyName = "UP"
        else if (k === Qt.Key_Down) keyName = "DOWN"
        else if (k === Qt.Key_Home) keyName = "HOME"
        else if (k === Qt.Key_End) keyName = "END"
        else if (k === Qt.Key_PageUp) keyName = "PAGE_UP"
        else if (k === Qt.Key_PageDown) keyName = "PAGE_DOWN"
        else if (k === Qt.Key_Insert) keyName = "INSERT"
        else if (k === Qt.Key_Minus) keyName = "-"
        else if (k === Qt.Key_Equal) keyName = "="
        else if (k === Qt.Key_BracketLeft) keyName = "["
        else if (k === Qt.Key_BracketRight) keyName = "]"
        else if (k === Qt.Key_BraceLeft) keyName = "{"
        else if (k === Qt.Key_BraceRight) keyName = "}"
        else if (k === Qt.Key_Semicolon) keyName = ";"
        else if (k === Qt.Key_Apostrophe) keyName = "'"
        else if (k === Qt.Key_QuoteDbl) keyName = "\""
        else if (k === Qt.Key_Comma) keyName = ","
        else if (k === Qt.Key_Period) keyName = "."
        else if (k === Qt.Key_Slash) keyName = "/"
        else if (k === Qt.Key_Backslash) keyName = "\\"
        else if (k === Qt.Key_AsciiGrave) keyName = "`"
        else if (k === Qt.Key_AsciiTilde) keyName = "~"
        else if (k === Qt.Key_VolumeUp) keyName = "XF86AudioRaiseVolume"
        else if (k === Qt.Key_VolumeDown) keyName = "XF86AudioLowerVolume"
        else if (k === Qt.Key_VolumeMute) keyName = "XF86AudioMute"
        else if (k === Qt.Key_MicMute) keyName = "XF86AudioMicMute"
        else if (k === Qt.Key_MonBrightnessUp) keyName = "XF86MonBrightnessUp"
        else if (k === Qt.Key_MonBrightnessDown) keyName = "XF86MonBrightnessDown"
        else if (k === Qt.Key_MediaPlay) keyName = "XF86AudioPlay"
        else if (k === Qt.Key_MediaNext) keyName = "XF86AudioNext"
        else if (k === Qt.Key_MediaPrevious) keyName = "XF86AudioPrev"
        else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32) keyName = event.text.toUpperCase()

        if (keyName && keyName !== "") {
            parts.push(keyName)
            return parts.join(" + ")
        }
        return ""
    }

    Component.onCompleted: {
        console.info("[PROVENANCE] keybindings.ui.revision=" + KeybindingsConfig.uiRevision)
    }

    onVisibleChanged: {
        if (visible) {
            pointerGate.reset()
            console.info("[LIFECYCLE] keybindings.window.visible=true")
            keybindingsModel.operationState = "idle"
            keybindingsModel.operationMessage = ""
            recordingItem = null
            keybindingsModel.activeView = "bound"
            keybindingsModel.searchQuery = ""
            keybindingsModel.selectedIndex = 0
            clearSearch()
            if (!keybindingsModel.allItems || keybindingsModel.allItems.length === 0) keybindingsModel.reload()
            else keybindingsModel.filterItems()
            focusActiveView("bound")
        } else {
            console.info("[LIFECYCLE] keybindings.window.hidden")
            keybindingsModel.operationState = "idle"
            keybindingsModel.operationMessage = ""
            recordingItem = null
            activationGestureHeld = false
            activationGestureKey = 0
            console.info("[PERF] KeybindingsWindow: Window hidden")
        }
    }

    ShortcutInhibitor {
        id: shortcutInhibitor
        window: windowRoot
        enabled: !windowRoot.browseActive && windowRoot.isRecording
        onCancelled: windowRoot.cancelCapture()
    }

    KeybindingsModel { id: keybindingsModel }

    PointerMoveGate {
        id: pointerGate
        referenceItem: surfaceCard
    }

    function resetPointerGate() {
        pointerGate.reset()
    }

    function selectFromPointer(row, mouse): bool {
        if (!row || !mouse || !pointerGate.moved(row, mouse)) return false
        keybindingsModel.selectedIndex = row.index
        return true
    }

    Connections {
        target: keybindingsModel
        function onActiveViewChanged() { pointerGate.reset() }
        function onSearchQueryChanged() { pointerGate.reset() }
        function onSelectedIndexChanged() {
            if (keybindingsModel.selectedIndex >= 0 && keybindingsModel.selectedIndex < actionList.listView.count) {
                actionList.listView.positionViewAtIndex(keybindingsModel.selectedIndex, ListView.Contain)
            }
        }
    }

    // These four regions never overlap the card. An inside click therefore
    // cannot become a dismissal click if its delegate is replaced synchronously.
    Item {
        id: outsideDismissArea
        anchors.fill: parent
        z: 0
        enabled: !windowRoot.browseActive

        function dismiss(region, mouse) {
            if (mouse) mouse.accepted = true
            if (windowRoot.browseActive) {
                console.warn("[EVENT] keybindings.input.outside_click ignored region=" + region + " (browseActive=true)")
                return
            }
            console.info("[EVENT] keybindings.input.outside_click region=" + region)
            if (windowRoot.isRecording) windowRoot.cancelCapture()
            else windowRoot.requestClose("outside-click")
        }

        MouseArea {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.max(0, surfaceCard.y)
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.ArrowCursor
            onClicked: function(mouse) { outsideDismissArea.dismiss("top", mouse) }
        }
        MouseArea {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            y: surfaceCard.y + surfaceCard.height
            height: Math.max(0, parent.height - surfaceCard.y - surfaceCard.height)
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.ArrowCursor
            onClicked: function(mouse) { outsideDismissArea.dismiss("bottom", mouse) }
        }
        MouseArea {
            x: 0
            y: surfaceCard.y
            width: Math.max(0, surfaceCard.x)
            height: surfaceCard.height
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.ArrowCursor
            onClicked: function(mouse) { outsideDismissArea.dismiss("left", mouse) }
        }
        MouseArea {
            x: surfaceCard.x + surfaceCard.width
            y: surfaceCard.y
            width: Math.max(0, parent.width - surfaceCard.x - surfaceCard.width)
            height: surfaceCard.height
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.ArrowCursor
            onClicked: function(mouse) { outsideDismissArea.dismiss("right", mouse) }
        }
    }

    Rectangle {
        id: surfaceCard
        anchors.centerIn: parent
        z: 10
        width: KeybindingsConfig.palettePreferredWidth
        height: KeybindingsConfig.palettePreferredHeight
        radius: KeybindingsConfig.surfaceRadius
        color: Theme.bgBase
        border.color: surfaceHover.hovered || header.searchInput.activeFocus ? Theme.borderActive : Theme.border
        border.width: Theme.borderWidthDefault
        clip: true

        MouseArea {
            id: surfaceClickShield
            anchors.fill: parent
            z: 0
            acceptedButtons: Qt.AllButtons
            preventStealing: true
            onClicked: {}
        }

        HoverHandler { id: surfaceHover }

        Behavior on border.color {
            ColorAnimation { duration: Theme.keybindingsDurationFast }
        }

        Keys.onPressed: function(event) {
            if (windowRoot.isRecording) {
                windowRoot.handleRecordingKeyPress(event)
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)) {
                windowRoot.cycleTopLevelView(true)
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                windowRoot.cycleTopLevelView(false)
                event.accepted = true
                return
            }
            if (windowRoot.handleComponentKey(event, "surface")) return
        }

        Keys.onReleased: function(event) {
            if (windowRoot.handleActivationKeyRelease(event)) return
            if (windowRoot.isRecording) {
                windowRoot.handleRecordingKeyRelease(event)
                event.accepted = true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            z: 1
            spacing: 0

            KeybindingsHeader {
                id: header
                modelController: keybindingsModel
                windowController: windowRoot
            }

            Item {
                id: body
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: Theme.spacingMd
                Layout.rightMargin: Theme.spacingMd

                KeybindingsAddActionPicker {
                    id: addActionPicker
                    anchors.fill: parent
                    modelController: keybindingsModel
                    windowController: windowRoot
                }

                KeybindingsActionList {
                    id: actionList
                    anchors.fill: parent
                    modelController: keybindingsModel
                    windowController: windowRoot
                }

                KeybindingsExecutableForm {
                    id: executableForm
                    anchors.fill: parent
                    modelController: keybindingsModel
                    windowController: windowRoot
                }

                KeybindingsSettings {
                    id: settingsView
                    anchors.fill: parent
                    visible: keybindingsModel.activeView === "settings"
                    model: keybindingsModel
                    window: windowRoot
                    onBackRequested: windowRoot.goBack()
                }
            }

            KeybindingsFooter {
                modelController: keybindingsModel
                windowController: windowRoot
            }
        }
    }
}
