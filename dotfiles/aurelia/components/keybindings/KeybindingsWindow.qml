import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"

PanelWindow {
    id: windowRoot

    // Layer-shell Wayland configuration: full-screen transparent overlay surface with exclusive focus during capture
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: windowRoot.browseActive ? WlrKeyboardFocus.None : (windowRoot.isRecording ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore

    // Window dimensions: restrained command palette proportions from design system (800x480)
    implicitWidth: Theme.paletteWidth // 800
    implicitHeight: Theme.paletteHeight // 480
    color: "transparent"

    // Browse modal/dialog state: when active, layer-shell keyboard focus is released (WlrKeyboardFocus.None)
    property bool browseActive: false

    // 3-State Capture Machine: "idle", "entering_capture", "capture_armed", "validating", "conflict"
    property string captureState: "idle"
    property int initiatingKey: 0
    property string candidateKey: ""
    property var conflictItem: null
    property var recordingItem: null

    property bool isRecording: (captureState === "entering_capture" || captureState === "capture_armed" || captureState === "validating" || captureState === "conflict" || keybindingsModel.operationState === "capturing" || keybindingsModel.operationState === "conflict")

    property alias keybindingsModel: keybindingsModel
    property alias hotkeysModel: keybindingsModel

    // Wayland shortcut inhibitor: prevents compositor global bindings from hijacking keypresses during capture
    ShortcutInhibitor {
        id: shortcutInhibitor
        window: windowRoot
        enabled: !windowRoot.browseActive && windowRoot.isRecording
        onCancelled: windowRoot.cancelCapture()
    }

    function startCapture(item, triggerEvent) {
        if (!item) return
        if (item.editable !== true) {
            keybindingsModel.operationState = "error"
            keybindingsModel.operationMessage = "Immutable: System binding cannot be modified."
            return
        }
        windowRoot.recordingItem = item
        windowRoot.conflictItem = null
        windowRoot.candidateKey = ""
        if (triggerEvent && triggerEvent.key) {
            windowRoot.initiatingKey = triggerEvent.key
            windowRoot.captureState = "entering_capture"
            keybindingsModel.operationState = "capturing"
            keybindingsModel.operationMessage = "Release key to begin shortcut recording..."
        } else {
            windowRoot.initiatingKey = 0
            windowRoot.captureState = "capture_armed"
            keybindingsModel.operationState = "capturing"
            keybindingsModel.operationMessage = "Set " + (item.description || "Shortcut") + " — press key combination (e.g. SUPER + SHIFT + T)..."
        }
    }

    function cancelCapture() {
        windowRoot.captureState = "idle"
        windowRoot.initiatingKey = 0
        windowRoot.recordingItem = null
        windowRoot.conflictItem = null
        windowRoot.candidateKey = ""
        if (keybindingsModel.operationState !== "idle") {
            keybindingsModel.operationState = "idle"
            keybindingsModel.operationMessage = ""
        }
    }

    // Authoritative activation & navigation operations:
    // Guarantees one physical event results in at most one semantic activation.
    // Structural event ownership with synchronous re-entrancy protection (isActivating).
    // Navigation events (e.g. Add Action type selection) NEVER fall through to action execution.
    property bool isActivating: false

    function openAddAction() {
        if (keybindingsModel.activeView.indexOf("add_") === 0) {
            return
        }
        keybindingsModel.switchView("add_action_type")
        Qt.callLater(function() { listView.forceActiveFocus() })
    }

    function requestClose(reason) {
        console.info("[LIFECYCLE] keybindings.window.close.request reason=" + (reason || "unknown") + " view=" + keybindingsModel.activeView + " stack=" + new Error().stack)
        windowRoot.visible = false
    }

    function goBack() {
        if (windowRoot.isRecording) {
            cancelCapture()
            return
        }
        if (keybindingsModel.operationState !== "idle") {
            cancelCapture()
            return
        }
        var view = keybindingsModel.activeView
        console.info("[EVENT] keybindings.navigation.back from_view=" + view)
        if (view === "add_app" || view === "add_exec") {
            keybindingsModel.switchView("add_action_type")
            Qt.callLater(function() { listView.forceActiveFocus() })
        } else if (view === "add_action_type") {
            var dest = keybindingsModel.previousRootView || "unbound"
            keybindingsModel.switchView(dest)
            Qt.callLater(function() { searchInput.forceActiveFocus() })
        } else {
            windowRoot.requestClose("escape-from-root")
        }
    }

    function activateSelected(): bool {
        var source = arguments.length > 0 ? arguments[0] : "keyboard"
        console.info("[EVENT] keybindings.activate.begin source=" + source + " view=" + keybindingsModel.activeView + " selIdx=" + keybindingsModel.selectedIndex + " item=" + (keybindingsModel.selectedItem ? (keybindingsModel.selectedItem.id || keybindingsModel.selectedItem.display_key) : "null") + " stack=" + new Error().stack)
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
                    Qt.callLater(function() { searchInput.forceActiveFocus() })
                    return true
                } else if (item.action_type_kind === "executable") {
                    console.info("[EVENT] keybindings.executable_form.open")
                    keybindingsModel.switchView("add_exec")
                    Qt.callLater(function() {
                        if (typeof addExecForm !== "undefined" && typeof addExecForm.focusFirstField === "function") {
                            addExecForm.focusFirstField()
                        } else if (typeof execNameInput !== "undefined") {
                            execNameInput.forceActiveFocus()
                        }
                    })
                    return true
                } else {
                    console.warn("[NAV] activateSelected: unexpected action_type_kind: " + (item.action_type_kind || "undefined"))
                    return false
                }
            } else if (view === "add_app") {
                if (item && item.desktop_id) {
                    console.info("[EVENT] keybindings.application.add desktop_id=" + item.desktop_id)
                    keybindingsModel.addApplication(item.desktop_id)
                    return true
                } else {
                    console.warn("[NAV] activateSelected: add_app with no desktop_id")
                    return false
                }
            } else if (view === "bound" || view === "unbound") {
                if (item && item.runnable === true) {
                    console.info("[EVENT] keybindings.run.request action_id=" + item.id)
                    if (keybindingsModel.runSelected()) {
                        console.info("[EVENT] keybindings.run.result ok=true")
                        windowRoot.requestClose("action-run-success")
                        return true
                    }
                    console.warn("[EVENT] keybindings.run.result ok=false")
                    return false
                }
                // Non-runnable actions in bound/unbound view: fail-closed, do not execute, do not close palette
                return false
            } else if (view === "add_exec") {
                if (typeof addExecForm !== "undefined" && typeof addExecForm.submitExecForm === "function") {
                    addExecForm.submitExecForm()
                }
                return true
            } else {
                console.warn("[NAV] activateSelected: unknown view: " + view)
                return false
            }
        } finally {
            isActivating = false
            console.info("[EVENT] keybindings.activate.end")
        }
    }

    function handleRecordingKeyRelease(event) {
        if (windowRoot.captureState === "entering_capture") {
            if (event.key === windowRoot.initiatingKey || event.modifiers === Qt.NoModifier) {
                windowRoot.initiatingKey = 0
                windowRoot.captureState = "capture_armed"
                keybindingsModel.operationState = "capturing"
                keybindingsModel.operationMessage = "Set " + (windowRoot.recordingItem ? windowRoot.recordingItem.description : "Shortcut") + " — press key combination (e.g. SUPER + SHIFT + T)..."
            }
            event.accepted = true
            return
        }
    }

    function handleRecordingKeyPress(event): bool {
        if (!windowRoot.isRecording) return false

        // Escape cancels capture unconditionally
        if (event.key === Qt.Key_Escape) {
            cancelCapture()
            event.accepted = true
            return true
        }

        // While waiting for initiating trigger key release, swallow all keypresses
        if (windowRoot.captureState === "entering_capture") {
            event.accepted = true
            return true
        }

        // While in conflict confirmation state, Enter confirms reassign
        if (windowRoot.captureState === "conflict") {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                var targetId = windowRoot.recordingItem ? windowRoot.recordingItem.id : ""
                var cand = windowRoot.candidateKey
                cancelCapture()
                if (targetId && cand) {
                    keybindingsModel.setShortcut(targetId, cand, true)
                }
                event.accepted = true
                return true
            }
            event.accepted = true
            return true
        }

        // While in validating state, swallow keys until asynchronous backend returns
        if (windowRoot.captureState === "validating") {
            event.accepted = true
            return true
        }

        // In capture_armed state:
        if (windowRoot.captureState === "capture_armed") {
            // Standalone Backspace or Delete to clear/unset shortcut
            if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                var itemToUnset = windowRoot.recordingItem
                cancelCapture()
                if (itemToUnset) {
                    keybindingsModel.unsetShortcut(itemToUnset.id)
                }
                event.accepted = true
                return true
            }

            var formatted = formatKeyEvent(event)
            if (!formatted || formatted === "") {
                // Standalone modifier (Ctrl, Shift, Alt, Super) pressed; wait for main key
                event.accepted = true
                return true
            }

            // Transition to validating
            windowRoot.candidateKey = formatted
            windowRoot.captureState = "validating"
            keybindingsModel.operationState = "validating"
            keybindingsModel.operationMessage = "Validating " + formatted + "..."
            event.accepted = true

            keybindingsModel.validateShortcut(formatted, windowRoot.recordingItem.id, function(valid, err, normKey) {
                if (!windowRoot.isRecording) return
                if (!valid) {
                    var displayMsg = "Invalid shortcut."
                    if (err.indexOf("printable-key-requires-global-modifier") !== -1) {
                        displayMsg = "Error: Letter/number keys require Super, Ctrl, or Alt."
                    } else if (err.indexOf("reserved-capture-control") !== -1) {
                        displayMsg = "Error: Standalone modifier or Escape cannot be a shortcut."
                    } else if (err.indexOf("malformed-combination") !== -1) {
                        displayMsg = "Error: Invalid shortcut combination."
                    } else {
                        displayMsg = "Error: " + err.replace(/^INVALID:\s*/, "")
                    }
                    keybindingsModel.operationState = "error"
                    keybindingsModel.operationMessage = displayMsg
                    windowRoot.captureState = "capture_armed"
                } else {
                    var finalKey = normKey || formatted
                    windowRoot.candidateKey = finalKey
                    var conflict = keybindingsModel.findConflict(windowRoot.recordingItem.id, finalKey)
                    if (conflict) {
                        if (conflict.editable === false || conflict.immutable === true) {
                            keybindingsModel.operationState = "error"
                            keybindingsModel.operationMessage = "Error: Conflicts with immutable system binding '" + (conflict.description || conflict.id) + "'. Cannot be reassigned."
                            windowRoot.captureState = "capture_armed"
                        } else {
                            windowRoot.conflictItem = conflict
                            windowRoot.captureState = "conflict"
                            keybindingsModel.operationState = "conflict"
                            keybindingsModel.operationMessage = "Conflicts with: " + (conflict.description || conflict.id) + ". Press Enter to reassign, or Esc to cancel."
                        }
                    } else {
                        var actId = windowRoot.recordingItem.id
                        cancelCapture()
                        keybindingsModel.setShortcut(actId, finalKey)
                    }
                }
            })
            return true
        }

        return false
    }

    // Comprehensive key event normalization mapping Qt key events to Hyprland binding syntax
    function formatKeyEvent(event): string {
        var k = event.key
        // Standalone modifier keys alone do not form a complete shortcut
        if (k === Qt.Key_Control || k === Qt.Key_Shift || k === Qt.Key_Alt || k === Qt.Key_Meta) {
            return ""
        }

        var parts = []
        if (event.modifiers & Qt.MetaModifier) parts.push("SUPER")
        if (event.modifiers & Qt.ControlModifier) parts.push("CTRL")
        if (event.modifiers & Qt.AltModifier) parts.push("ALT")
        if (event.modifiers & Qt.ShiftModifier) parts.push("SHIFT")

        var keyName = ""
        if (k >= Qt.Key_A && k <= Qt.Key_Z) {
            keyName = String.fromCharCode(k)
        } else if (k >= Qt.Key_0 && k <= Qt.Key_9) {
            keyName = String.fromCharCode(k)
        } else if (k >= Qt.Key_F1 && k <= Qt.Key_F24) {
            keyName = "F" + (k - Qt.Key_F1 + 1)
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            keyName = "RETURN"
        } else if (k === Qt.Key_Space) {
            keyName = "SPACE"
        } else if (k === Qt.Key_Tab) {
            keyName = "TAB"
        } else if (k === Qt.Key_Left) {
            keyName = "LEFT"
        } else if (k === Qt.Key_Right) {
            keyName = "RIGHT"
        } else if (k === Qt.Key_Up) {
            keyName = "UP"
        } else if (k === Qt.Key_Down) {
            keyName = "DOWN"
        } else if (k === Qt.Key_Home) {
            keyName = "HOME"
        } else if (k === Qt.Key_End) {
            keyName = "END"
        } else if (k === Qt.Key_PageUp) {
            keyName = "PAGE_UP"
        } else if (k === Qt.Key_PageDown) {
            keyName = "PAGE_DOWN"
        } else if (k === Qt.Key_Insert) {
            keyName = "INSERT"
        } else if (k === Qt.Key_Minus) {
            keyName = "-"
        } else if (k === Qt.Key_Equal) {
            keyName = "="
        } else if (k === Qt.Key_BracketLeft) {
            keyName = "["
        } else if (k === Qt.Key_BracketRight) {
            keyName = "]"
        } else if (k === Qt.Key_BraceLeft) {
            keyName = "{"
        } else if (k === Qt.Key_BraceRight) {
            keyName = "}"
        } else if (k === Qt.Key_Semicolon) {
            keyName = ";"
        } else if (k === Qt.Key_Apostrophe) {
            keyName = "'"
        } else if (k === Qt.Key_QuoteDbl) {
            keyName = "\""
        } else if (k === Qt.Key_Comma) {
            keyName = ","
        } else if (k === Qt.Key_Period) {
            keyName = "."
        } else if (k === Qt.Key_Slash) {
            keyName = "/"
        } else if (k === Qt.Key_Backslash) {
            keyName = "\\"
        } else if (k === Qt.Key_AsciiGrave) {
            keyName = "`"
        } else if (k === Qt.Key_AsciiTilde) {
            keyName = "~"
        } else if (k === Qt.Key_VolumeUp) {
            keyName = "XF86AudioRaiseVolume"
        } else if (k === Qt.Key_VolumeDown) {
            keyName = "XF86AudioLowerVolume"
        } else if (k === Qt.Key_VolumeMute) {
            keyName = "XF86AudioMute"
        } else if (k === Qt.Key_MicMute) {
            keyName = "XF86AudioMicMute"
        } else if (k === Qt.Key_MonBrightnessUp) {
            keyName = "XF86MonBrightnessUp"
        } else if (k === Qt.Key_MonBrightnessDown) {
            keyName = "XF86MonBrightnessDown"
        } else if (k === Qt.Key_MediaPlay) {
            keyName = "XF86AudioPlay"
        } else if (k === Qt.Key_MediaNext) {
            keyName = "XF86AudioNext"
        } else if (k === Qt.Key_MediaPrevious) {
            keyName = "XF86AudioPrev"
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32) {
            keyName = event.text.toUpperCase()
        }

        if (keyName && keyName !== "") {
            parts.push(keyName)
            return parts.join(" + ")
        }
        return ""
    }

    onVisibleChanged: {
        if (visible) {
            console.info("[LIFECYCLE] keybindings.window.visible=true")
            var openT0 = Date.now()
            keybindingsModel.operationState = "idle"
            keybindingsModel.operationMessage = ""
            recordingItem = null
            keybindingsModel.activeView = "bound"
            keybindingsModel.searchQuery = ""
            keybindingsModel.selectedIndex = 0
            if (!keybindingsModel.allItems || keybindingsModel.allItems.length === 0) {
                keybindingsModel.reload()
            } else {
                keybindingsModel.filterItems()
            }
            searchInput.forceActiveFocus()
            console.info("[PERF] KeybindingsWindow: Window displayed and input focused in " + (Date.now() - openT0) + "ms")
        } else {
            console.info("[LIFECYCLE] keybindings.window.hidden")
            keybindingsModel.operationState = "idle"
            keybindingsModel.operationMessage = ""
            recordingItem = null
            console.info("[PERF] KeybindingsWindow: Window hidden")
        }
    }

    KeybindingsModel {
        id: keybindingsModel
    }

    Connections {
        target: keybindingsModel
        function onSelectedIndexChanged() {
            if (keybindingsModel.selectedIndex >= 0 && keybindingsModel.selectedIndex < listView.count) {
                listView.positionViewAtIndex(keybindingsModel.selectedIndex, ListView.Contain)
            }
        }
        function onOperationStateChanged() {
            if (keybindingsModel.operationState === "success") {
                successResetTimer.restart()
            }
        }
    }

    Timer {
        id: successResetTimer
        interval: 2500
        repeat: false
        onTriggered: {
            if (keybindingsModel.operationState === "success") {
                keybindingsModel.operationState = "idle"
                keybindingsModel.operationMessage = ""
                windowRoot.recordingItem = null
            }
        }
    }

    // Fullscreen transparent backdrop for outside-click dismissal
    MouseArea {
        id: outsideDismissArea
        anchors.fill: parent
        cursorShape: Qt.ArrowCursor
        onClicked: {
            console.info("[EVENT] keybindings.input.outside_click")
            if (windowRoot.isRecording) {
                windowRoot.cancelCapture()
            } else {
                windowRoot.requestClose("outside-click")
            }
        }
    }

    // Modal surface card with dynamic theme-aware active border highlight on focus/hover
    Rectangle {
        id: surfaceCard
        anchors.centerIn: parent
        width: Theme.paletteWidth
        height: Theme.paletteHeight
        radius: Theme.radiusMd
        color: Theme.bgBase
        border.color: (surfaceHover.hovered || searchInput.activeFocus) ? Theme.borderActive : Theme.border
        border.width: Theme.borderWidthFocus
        clip: true

        // Inner mouse area absorbs clicks inside surfaceCard bounds so they do not fall through to outsideDismissArea
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        HoverHandler {
            id: surfaceHover
        }

        Behavior on border.color {
            ColorAnimation { duration: Theme.effectiveDurationFast }
        }

        Keys.onPressed: function(event) {
            if (windowRoot.isRecording) {
                windowRoot.handleRecordingKeyPress(event)
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_Escape) {
                windowRoot.goBack()
                event.accepted = true
                return
            }
            if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_A) {
                windowRoot.openAddAction()
                event.accepted = true
                return
            }
        }

        Keys.onReleased: function(event) {
            if (windowRoot.isRecording) {
                windowRoot.handleRecordingKeyRelease(event)
                event.accepted = true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header: Minimal search input area (keybindings_ prompt style, no box/border)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.searchHeight
                Layout.leftMargin: Theme.spacingXl
                Layout.rightMargin: Theme.spacingXl
                Layout.topMargin: Theme.spacingLg
                Layout.bottomMargin: Theme.spacingSm
                visible: keybindingsModel.activeView !== "add_exec"

                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    color: Theme.text
                    selectByMouse: true
                    selectionColor: Theme.selection
                    selectedTextColor: Theme.text
                    readOnly: (windowRoot.isRecording || keybindingsModel.operationState === "applying")

                    // Idle placeholders
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "keybindings_"
                        color: Theme.textSubtle
                        font: parent.font
                        visible: !searchInput.text && (keybindingsModel.operationState === "idle") && (keybindingsModel.activeView === "bound")
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "keybindings_ (unbound)"
                        color: Theme.textSubtle
                        font: parent.font
                        visible: !searchInput.text && (keybindingsModel.operationState === "idle") && (keybindingsModel.activeView === "unbound")
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "choose action type_"
                        color: Theme.textSubtle
                        font: parent.font
                        visible: !searchInput.text && (keybindingsModel.operationState === "idle") && (keybindingsModel.activeView === "add_action_type")
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "add application_"
                        color: Theme.textSubtle
                        font: parent.font
                        visible: !searchInput.text && (keybindingsModel.operationState === "idle") && (keybindingsModel.activeView === "add_app")
                    }

                    // Capturing active prompt
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: (windowRoot.captureState === "entering_capture") ? "Release key to begin shortcut recording..." : ((windowRoot.captureState === "capture_armed") ? ("Set " + (windowRoot.recordingItem ? windowRoot.recordingItem.description : "Shortcut") + " — press key combination...") : "")
                        color: Theme.accent
                        font: parent.font
                        visible: (windowRoot.captureState === "entering_capture" || windowRoot.captureState === "capture_armed")
                    }

                    // Validating prompt
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Validating " + windowRoot.candidateKey + "..."
                        color: Theme.gold
                        font: parent.font
                        visible: (windowRoot.captureState === "validating")
                    }

                    // Applying prompt
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Applying changes..."
                        color: Theme.gold
                        font: parent.font
                        visible: (keybindingsModel.operationState === "applying")
                    }

                    // Inline Result / Conflict / Error feedback
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: keybindingsModel.operationMessage
                        color: (keybindingsModel.operationState === "success") ? Theme.success : ((keybindingsModel.operationState === "conflict") ? Theme.warning : Theme.error)
                        font.family: parent.font.family
                        font.pixelSize: parent.font.pixelSize
                        font.bold: true
                        visible: (keybindingsModel.operationState === "success" || keybindingsModel.operationState === "conflict" || (keybindingsModel.operationState === "error" && windowRoot.captureState !== "capture_armed"))
                    }

                    // Error feedback while remaining armed for retry
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: keybindingsModel.operationMessage + " (press key combination again or Esc to cancel)"
                        color: Theme.error
                        font.family: parent.font.family
                        font.pixelSize: parent.font.pixelSize
                        font.bold: true
                        visible: (keybindingsModel.operationState === "error" && windowRoot.captureState === "capture_armed")
                    }

                    onTextChanged: {
                        if (!windowRoot.isRecording && keybindingsModel.operationState !== "idle") {
                            keybindingsModel.operationState = "idle"
                            keybindingsModel.operationMessage = ""
                            windowRoot.recordingItem = null
                        }
                        keybindingsModel.searchQuery = text
                    }

                    Keys.onReleased: function(event) {
                        if (windowRoot.isRecording) {
                            windowRoot.handleRecordingKeyRelease(event)
                            event.accepted = true
                        }
                    }

                    Keys.onPressed: function(event) {
                        // 1. Handling during inline capture mode
                        if (windowRoot.isRecording) {
                            windowRoot.handleRecordingKeyPress(event)
                            event.accepted = true
                            return
                        }

                        // 2. Handling during conflict/error/success state
                        if (keybindingsModel.operationState === "conflict" || keybindingsModel.operationState === "error" || keybindingsModel.operationState === "success") {
                            if (event.key === Qt.Key_Escape) {
                                cancelCapture()
                                event.accepted = true
                                return
                            }
                        }

                        // 3. Tab toggles Bound vs Unbound view
                        if (event.key === Qt.Key_Tab) {
                            if (keybindingsModel.activeView.indexOf("add_") === 0) {
                                keybindingsModel.switchView("unbound")
                            } else {
                                keybindingsModel.toggleView()
                            }
                            event.accepted = true
                            return
                        }

                        // 4. Normal idle navigation, view switching, and execution
                        if (event.key === Qt.Key_Escape) {
                            windowRoot.goBack()
                            event.accepted = true
                            return
                        } else if (event.key === Qt.Key_Down) {
                            keybindingsModel.selectNext()
                            listView.positionViewAtIndex(keybindingsModel.selectedIndex, ListView.Contain)
                            listView.forceActiveFocus()
                            event.accepted = true
                            return
                        } else if (event.key === Qt.Key_Up) {
                            keybindingsModel.selectPrevious()
                            listView.positionViewAtIndex(keybindingsModel.selectedIndex, ListView.Contain)
                            listView.forceActiveFocus()
                            event.accepted = true
                            return
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            console.info("[EVENT] keybindings.input.enter target=searchInput activeView=" + keybindingsModel.activeView)
                            event.accepted = true
                            windowRoot.activateSelected()
                            return
                        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_A) {
                            windowRoot.openAddAction()
                            event.accepted = true
                            return
                        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_S) {
                            if (keybindingsModel.activeView === "bound" || keybindingsModel.activeView === "unbound") {
                                var item = keybindingsModel.selectedItem
                                if (item) {
                                    windowRoot.startCapture(item, event)
                                }
                            }
                            event.accepted = true
                            return
                        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_U) {
                            if (keybindingsModel.activeView === "bound" || keybindingsModel.activeView === "unbound") {
                                var itemUnset = keybindingsModel.selectedItem
                                if (itemUnset) {
                                    if (itemUnset.editable !== true) {
                                        keybindingsModel.operationState = "error"
                                        keybindingsModel.operationMessage = "Immutable: System binding cannot be modified."
                                    } else {
                                        keybindingsModel.unsetShortcut(itemUnset.id)
                                    }
                                }
                            }
                            event.accepted = true
                            return
                        }
                        // Note: plain letters 'a', 'b', 's', 'u' fall through to standard TextInput processing
                    }
                }
            }

            // View Selector Tabs: Minimal command-palette tabs [ Bound (N) ] [ Unbound (M) ] [ + Add Application ]
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                Layout.leftMargin: Theme.spacingXl
                Layout.rightMargin: Theme.spacingXl
                Layout.bottomMargin: Theme.spacingSm
                spacing: Theme.spacingMd

                // Bound tab
                Rectangle {
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: boundText.implicitWidth + Theme.spacingMd * 2
                    radius: Theme.radiusSm
                    color: (keybindingsModel.activeView === "bound") ? Theme.selection : "transparent"

                    Text {
                        id: boundText
                        anchors.centerIn: parent
                        text: "Bound (" + keybindingsModel.boundCount + ")"
                        color: (keybindingsModel.activeView === "bound") ? Theme.accent : Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: (keybindingsModel.activeView === "bound") ? Theme.fontWeightMedium : Theme.fontWeightNormal
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            keybindingsModel.switchView("bound")
                        }
                    }
                }

                // Unbound tab
                Rectangle {
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: unboundText.implicitWidth + Theme.spacingMd * 2
                    radius: Theme.radiusSm
                    color: (keybindingsModel.activeView === "unbound") ? Theme.selection : "transparent"

                    Text {
                        id: unboundText
                        anchors.centerIn: parent
                        text: "Unbound (" + keybindingsModel.unboundCount + ")"
                        color: (keybindingsModel.activeView === "unbound") ? Theme.accent : Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: (keybindingsModel.activeView === "unbound") ? Theme.fontWeightMedium : Theme.fontWeightNormal
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            keybindingsModel.switchView("unbound")
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // Add Action / Back tab
                Rectangle {
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: addActionText.implicitWidth + Theme.spacingMd * 2
                    radius: Theme.radiusSm
                    color: (keybindingsModel.activeView.indexOf("add_") === 0) ? Theme.selection : "transparent"

                    Text {
                        id: addActionText
                        anchors.centerIn: parent
                        text: (keybindingsModel.activeView.indexOf("add_") === 0) ? "← Back to Shortcuts" : "+ Add Action"
                        color: (keybindingsModel.activeView.indexOf("add_") === 0) ? Theme.gold : Theme.foam
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Theme.fontWeightMedium
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (keybindingsModel.activeView.indexOf("add_") === 0) {
                                windowRoot.goBack()
                            } else {
                                windowRoot.openAddAction()
                            }
                        }
                    }
                }
            }

            // Body: Shortcut List or Restrained Empty State or Add Exec Form
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: Theme.spacingMd
                Layout.rightMargin: Theme.spacingMd

                // Normal / Add-App / Add-Type List
                ListView {
                    id: listView
                    anchors.fill: parent
                    spacing: Theme.rowSpacing
                    clip: true
                    model: keybindingsModel.filteredItems
                    currentIndex: keybindingsModel.selectedIndex
                    focus: true
                    visible: keybindingsModel.activeView !== "add_exec"

                    delegate: KeybindingRow {
                        isSelected: index === keybindingsModel.selectedIndex
                    }

                    Keys.onReleased: function(event) {
                        if (windowRoot.isRecording) {
                            windowRoot.handleRecordingKeyRelease(event)
                            event.accepted = true
                        }
                    }

                    Keys.onPressed: function(event) {
                        // 1. Handling during inline capture mode
                        if (windowRoot.isRecording) {
                            windowRoot.handleRecordingKeyPress(event)
                            event.accepted = true
                            return
                        }

                        // 2. Handling during conflict/error/success state
                        if (keybindingsModel.operationState === "conflict" || keybindingsModel.operationState === "error" || keybindingsModel.operationState === "success") {
                            if (event.key === Qt.Key_Escape) {
                                cancelCapture()
                                event.accepted = true
                                return
                            }
                        }

                        // 3. Tab toggles Bound vs Unbound view
                        if (event.key === Qt.Key_Tab) {
                            if (keybindingsModel.activeView.indexOf("add_") === 0) {
                                keybindingsModel.switchView("unbound")
                            } else {
                                keybindingsModel.toggleView()
                            }
                            event.accepted = true
                            return
                        }

                        // 4. Escape: go back or dismiss
                        if (event.key === Qt.Key_Escape) {
                            windowRoot.goBack()
                            event.accepted = true
                            return
                        }

                        // 5. Down/Up Navigation
                        if (event.key === Qt.Key_Down) {
                            keybindingsModel.selectNext()
                            listView.positionViewAtIndex(keybindingsModel.selectedIndex, ListView.Contain)
                            event.accepted = true
                            return
                        }
                        if (event.key === Qt.Key_Up) {
                            if (keybindingsModel.selectedIndex === 0) {
                                searchInput.forceActiveFocus()
                            } else {
                                keybindingsModel.selectPrevious()
                                listView.positionViewAtIndex(keybindingsModel.selectedIndex, ListView.Contain)
                            }
                            event.accepted = true
                            return
                        }

                        // 6. Return / Enter: Authoritative activation
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            console.info("[EVENT] keybindings.input.enter target=listView activeView=" + keybindingsModel.activeView)
                            event.accepted = true
                            windowRoot.activateSelected()
                            return
                        }

                        // 7. Alt+A -> Open Add Action view (never toggles back)
                        if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_A) {
                            windowRoot.openAddAction()
                            event.accepted = true
                            return
                        }

                        // 8. B / b -> Go Back (in list/navigation context)
                        if ((event.key === Qt.Key_B && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) || ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_B)) {
                            windowRoot.goBack()
                            event.accepted = true
                            return
                        }

                        // 9. S / s -> Set / Edit hotkey (or Alt+S) - restricted to bound/unbound view
                        if ((event.key === Qt.Key_S && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) || ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_S)) {
                            if (keybindingsModel.activeView !== "bound" && keybindingsModel.activeView !== "unbound") {
                                event.accepted = true
                                return
                            }
                            var item = keybindingsModel.selectedItem
                            if (!item) {
                                event.accepted = true
                                return
                            }
                            windowRoot.startCapture(item, event)
                            event.accepted = true
                            return
                        }

                        // 10. U / u -> Unset / Clear hotkey (or Alt+U) - restricted to bound/unbound view
                        if ((event.key === Qt.Key_U && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) || ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_U)) {
                            if (keybindingsModel.activeView !== "bound" && keybindingsModel.activeView !== "unbound") {
                                event.accepted = true
                                return
                            }
                            var itemUnset = keybindingsModel.selectedItem
                            if (!itemUnset) {
                                event.accepted = true
                                return
                            }
                            if (itemUnset.editable !== true) {
                                keybindingsModel.operationState = "error"
                                keybindingsModel.operationMessage = "Immutable: System binding cannot be modified."
                            } else {
                                keybindingsModel.unsetShortcut(itemUnset.id)
                            }
                            event.accepted = true
                            return
                        }

                        // 11. Slash, Backspace, or printable text redirects to searchInput
                        if (event.key === Qt.Key_Slash || event.key === Qt.Key_Backspace || (event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32)) {
                            searchInput.forceActiveFocus()
                            if (event.key !== Qt.Key_Slash) {
                                searchInput.text = searchInput.text + event.text
                            }
                            event.accepted = true
                            return
                        }
                    }

                    // Subtle scrollbar indicator
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        width: Theme.scrollBarWidth
                        contentItem: Rectangle {
                            color: Theme.selection
                            radius: Theme.radiusSm / 2
                        }
                    }
                }

                // Minimal empty state message
                Text {
                    anchors.centerIn: parent
                    text: (keybindingsModel.activeView === "add_app") ? (keybindingsModel.isLoadingApps ? "Discovering installed applications..." : "No matching applications found") : ((keybindingsModel.activeView === "add_action_type") ? "No action types available" : (keybindingsModel.activeView === "unbound" ? "No unbound shortcuts (press a to add an action)" : "No matching shortcuts"))
                    color: Theme.textSubtle
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    visible: keybindingsModel.filteredItems.length === 0 && keybindingsModel.activeView !== "add_exec"
                }

                // Add Custom Executable / Script Form
                Item {
                    id: addExecForm
                    anchors.fill: parent
                    visible: keybindingsModel.activeView === "add_exec"

                    property string internalFormError: ""

                    function focusFirstField() {
                        execNameInput.forceActiveFocus()
                    }

                    function submitExecForm() {
                        var name = execNameInput.text.trim()
                        var path = execPathInput.text.trim()
                        var args = execArgsInput.text.trim()

                        if (!name) {
                            addExecForm.internalFormError = "Error: Action Name cannot be empty."
                            execNameInput.forceActiveFocus()
                            return
                        }
                        if (!path) {
                            addExecForm.internalFormError = "Error: Executable Path cannot be empty."
                            execPathInput.forceActiveFocus()
                            return
                        }

                        var idPart = name.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "")
                        if (!idPart) {
                            idPart = "custom_exec_" + Date.now()
                        }
                        var actionId = "exec:" + idPart

                        var argv = []
                        if (args) {
                            argv = args.split(/\s+/).filter(function(a) { return a.length > 0; })
                        }

                        addExecForm.internalFormError = ""
                        keybindingsModel.addExecutable(actionId, name, path, argv)
                    }

                    property Process browseProcess: Process {
                        id: browseProcess
                        command: [keybindingsModel.backendBin, "choose-file"]
                        environment: keybindingsModel.procEnv
                        property string chosenPath: ""
                        property string errorMsg: ""

                        stdout: StdioCollector {
                            onStreamFinished: {
                                browseProcess.chosenPath = this.text ? this.text.trim() : ""
                            }
                        }
                        stderr: StdioCollector {
                            onStreamFinished: {
                                browseProcess.errorMsg = this.text ? this.text.trim() : ""
                            }
                        }
                        onExited: function(code) {
                            console.info("[LIFECYCLE] keybindings.browse.focus_restore")
                            windowRoot.browseActive = false
                            if (code === 0 && browseProcess.chosenPath.length > 0) {
                                console.info("[LIFECYCLE] keybindings.browse.accept has_selection=true")
                                execPathInput.text = browseProcess.chosenPath
                                addExecForm.internalFormError = ""
                                execPathInput.forceActiveFocus()
                            } else if (code === 1 || (code === 0 && browseProcess.chosenPath.length === 0)) {
                                console.info("[LIFECYCLE] keybindings.browse.cancel")
                                browseButton.forceActiveFocus()
                            } else {
                                console.warn("[LIFECYCLE] keybindings.browse.error exit_code=" + code)
                                addExecForm.internalFormError = "File chooser failed: " + (browseProcess.errorMsg || "Process exited with code " + code)
                                browseButton.forceActiveFocus()
                            }
                        }
                    }

                    function triggerBrowse() {
                        if (windowRoot.isRecording || windowRoot.captureState !== "idle" || keybindingsModel.operationState === "capturing" || keybindingsModel.operationState === "conflict") {
                            console.warn("[LIFECYCLE] keybindings.browse.rejected reason=capture_active")
                            return
                        }
                        if (browseProcess.running) {
                            console.warn("[LIFECYCLE] keybindings.browse.rejected reason=already_running")
                            return
                        }
                        console.info("[LIFECYCLE] keybindings.browse.request")
                        console.info("[LIFECYCLE] keybindings.browse.focus_release")
                        windowRoot.browseActive = true
                        addExecForm.internalFormError = ""
                        browseProcess.chosenPath = ""
                        browseProcess.errorMsg = ""
                        browseProcess.command = [keybindingsModel.backendBin, "choose-file"]
                        browseProcess.running = true
                        console.info("[LIFECYCLE] keybindings.browse.open")
                    }

                    onVisibleChanged: {
                        if (visible) {
                            execNameInput.text = ""
                            execPathInput.text = ""
                            execArgsInput.text = ""
                            execPathInput.showSuggestions = false
                            execPathInput.suggestionIndex = -1
                            internalFormError = ""
                            focusFirstField()
                        } else {
                            execPathInput.showSuggestions = false
                            execPathInput.suggestionIndex = -1
                            windowRoot.browseActive = false
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 64, 560)
                        spacing: Theme.spacingMd

                        Text {
                            text: "Add Custom Executable / Script"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLg
                            font.weight: Theme.fontWeightBold
                            color: Theme.accent
                        }

                        Text {
                            text: "Specify an action name, executable binary path, and optional arguments."
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.textSecondary
                            Layout.bottomMargin: Theme.spacingSm
                        }

                        // Field 1: Action Name
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXs
                            Text {
                                text: "Action Name:"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                                font.weight: Theme.fontWeightMedium
                                color: Theme.textMuted
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                radius: Theme.radiusSm
                                color: Theme.inputBg
                                border.color: execNameInput.activeFocus ? Theme.inputBorderFocused : Theme.inputBorder
                                border.width: 1
                                TextInput {
                                    id: execNameInput
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingSm
                                    anchors.rightMargin: Theme.spacingSm
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    color: Theme.inputText
                                    selectByMouse: true
                                    selectionColor: Theme.inputSelection
                                    selectedTextColor: Theme.inputSelectionText
                                    Text {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        text: "e.g. My Workspace Script"
                                        font: parent.font
                                        color: Theme.inputPlaceholder
                                        visible: !execNameInput.text
                                    }
                                    Keys.onPressed: function(event) {
                                        if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                                            execPathInput.forceActiveFocus()
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            addExecForm.submitExecForm()
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Escape) {
                                            windowRoot.goBack()
                                            event.accepted = true
                                        }
                                    }
                                }
                            }
                        }

                        // Field 2: Executable Path
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXs
                            Text {
                                text: "Executable Path:"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                                font.weight: Theme.fontWeightMedium
                                color: Theme.textMuted
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingSm

                                Rectangle {
                                    id: pathInputContainer
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36
                                    radius: Theme.radiusSm
                                    color: Theme.inputBg
                                    border.color: execPathInput.activeFocus ? Theme.inputBorderFocused : Theme.inputBorder
                                    border.width: 1
                                    z: 10

                                    TextInput {
                                        id: execPathInput
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.spacingSm
                                        anchors.rightMargin: Theme.spacingSm
                                        verticalAlignment: TextInput.AlignVCenter
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        color: Theme.inputText
                                        selectByMouse: true
                                        selectionColor: Theme.inputSelection
                                        selectedTextColor: Theme.inputSelectionText

                                        property int suggestionIndex: -1
                                        property bool showSuggestions: false
                                        property var suggestions: keybindingsModel.pathCompletions

                                        function acceptSuggestion(val) {
                                            if (!val) return
                                            execPathInput.text = val
                                            execPathInput.cursorPosition = val.length
                                            if (val.endsWith("/")) {
                                                execPathInput.suggestionIndex = -1
                                                keybindingsModel.fetchPathCompletions(val)
                                                execPathInput.showSuggestions = true
                                            } else {
                                                execPathInput.showSuggestions = false
                                                execPathInput.suggestionIndex = -1
                                            }
                                            execPathInput.forceActiveFocus()
                                        }

                                        onTextChanged: {
                                            if (text && text.trim().length > 0) {
                                                showSuggestions = true
                                                suggestionIndex = -1
                                                keybindingsModel.fetchPathCompletions(text)
                                            } else {
                                                showSuggestions = false
                                                suggestionIndex = -1
                                            }
                                        }

                                        Text {
                                            anchors.fill: parent
                                            verticalAlignment: Text.AlignVCenter
                                            text: "e.g. /usr/local/bin/my-script"
                                            font: parent.font
                                            color: Theme.inputPlaceholder
                                            visible: !execPathInput.text
                                        }

                                        Keys.onPressed: function(event) {
                                            var hasSuggestions = execPathInput.showSuggestions && execPathInput.suggestions && execPathInput.suggestions.length > 0

                                            if (hasSuggestions && event.key === Qt.Key_Down) {
                                                if (execPathInput.suggestionIndex < execPathInput.suggestions.length - 1) {
                                                    execPathInput.suggestionIndex++
                                                } else {
                                                    execPathInput.suggestionIndex = 0
                                                }
                                                event.accepted = true
                                            } else if (hasSuggestions && event.key === Qt.Key_Up) {
                                                if (execPathInput.suggestionIndex > 0) {
                                                    execPathInput.suggestionIndex--
                                                } else {
                                                    execPathInput.suggestionIndex = -1
                                                }
                                                event.accepted = true
                                            } else if (hasSuggestions && event.key === Qt.Key_Tab) {
                                                var targetVal = ""
                                                if (execPathInput.suggestionIndex >= 0 && execPathInput.suggestionIndex < execPathInput.suggestions.length) {
                                                    targetVal = execPathInput.suggestions[execPathInput.suggestionIndex]
                                                } else if (execPathInput.suggestions.length > 0) {
                                                    targetVal = execPathInput.suggestions[0]
                                                }
                                                if (targetVal !== "") {
                                                    execPathInput.acceptSuggestion(targetVal)
                                                }
                                                event.accepted = true
                                            } else if (hasSuggestions && execPathInput.suggestionIndex >= 0 && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                                var chosenVal = execPathInput.suggestions[execPathInput.suggestionIndex]
                                                execPathInput.acceptSuggestion(chosenVal)
                                                event.accepted = true
                                            } else if (hasSuggestions && event.key === Qt.Key_Escape) {
                                                execPathInput.showSuggestions = false
                                                execPathInput.suggestionIndex = -1
                                                event.accepted = true
                                            } else if (!hasSuggestions && (event.key === Qt.Key_Tab || event.key === Qt.Key_Right)) {
                                                browseButton.forceActiveFocus()
                                                event.accepted = true
                                            } else if (!hasSuggestions && event.key === Qt.Key_Down) {
                                                execArgsInput.forceActiveFocus()
                                                event.accepted = true
                                            } else if (event.key === Qt.Key_Up) {
                                                execNameInput.forceActiveFocus()
                                                event.accepted = true
                                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                                addExecForm.submitExecForm()
                                                event.accepted = true
                                            } else if (event.key === Qt.Key_Escape) {
                                                windowRoot.goBack()
                                                event.accepted = true
                                            }
                                        }
                                    }

                                    // Autocomplete suggestions dropdown
                                    Rectangle {
                                        id: suggestionPopup
                                        z: 100
                                        visible: execPathInput.showSuggestions && execPathInput.suggestions && execPathInput.suggestions.length > 0 && execPathInput.activeFocus
                                        anchors.top: pathInputContainer.bottom
                                        anchors.topMargin: 4
                                        anchors.left: pathInputContainer.left
                                        anchors.right: pathInputContainer.right
                                        height: Math.min(execPathInput.suggestions.length * 30 + 8, 160)
                                        color: Theme.surfaceElevated
                                        border.color: Theme.border
                                        border.width: 1
                                        radius: Theme.radiusSm
                                        clip: true

                                        ListView {
                                            id: suggestionListView
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            model: execPathInput.suggestions
                                            currentIndex: execPathInput.suggestionIndex
                                            clip: true
                                            boundsBehavior: Flickable.StopAtBounds

                                            delegate: Rectangle {
                                                id: suggestionDelegate
                                                required property string modelData
                                                required property int index

                                                width: ListView.view.width
                                                height: 28
                                                radius: Theme.radiusSm
                                                color: (execPathInput.suggestionIndex === index) ? Theme.selection : "transparent"

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: Theme.spacingSm
                                                    anchors.rightMargin: Theme.spacingSm
                                                    spacing: Theme.spacingSm

                                                    Text {
                                                        text: modelData.endsWith("/") ? "📁" : "📄"
                                                        font.pixelSize: Theme.fontSizeXs
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }

                                                    Text {
                                                        text: modelData
                                                        color: (execPathInput.suggestionIndex === index) ? Theme.accent : Theme.text
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: Theme.fontSizeSm
                                                        font.weight: (execPathInput.suggestionIndex === index) ? Theme.fontWeightMedium : Theme.fontWeightNormal
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideMiddle
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onEntered: {
                                                        execPathInput.suggestionIndex = index
                                                    }
                                                    onClicked: {
                                                        execPathInput.acceptSuggestion(modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    id: browseButton
                                    Layout.preferredHeight: 36
                                    Layout.preferredWidth: browseLabel.implicitWidth + Theme.spacingLg * 2
                                    radius: Theme.radiusSm
                                    color: browseButton.activeFocus ? Theme.accent : Theme.surfaceElevated
                                    border.color: browseButton.activeFocus ? Theme.accent : Theme.border
                                    border.width: 1
                                    focus: true
                                    activeFocusOnTab: true

                                    Text {
                                        id: browseLabel
                                        anchors.centerIn: parent
                                        text: "Browse…"
                                        color: browseButton.activeFocus ? Theme.bgBase : Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        font.weight: Theme.fontWeightMedium
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: addExecForm.triggerBrowse()
                                    }

                                    Keys.onPressed: function(event) {
                                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                                            addExecForm.triggerBrowse()
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Escape) {
                                            windowRoot.goBack()
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down) {
                                            execArgsInput.forceActiveFocus()
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left) {
                                            execPathInput.forceActiveFocus()
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Up) {
                                            execNameInput.forceActiveFocus()
                                            event.accepted = true
                                        }
                                    }
                                }
                            }
                        }

                        // Field 3: Arguments (optional)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXs
                            Text {
                                text: "Arguments (optional):"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                                font.weight: Theme.fontWeightMedium
                                color: Theme.textMuted
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                radius: Theme.radiusSm
                                color: Theme.inputBg
                                border.color: execArgsInput.activeFocus ? Theme.inputBorderFocused : Theme.inputBorder
                                border.width: 1
                                TextInput {
                                    id: execArgsInput
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingSm
                                    anchors.rightMargin: Theme.spacingSm
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    color: Theme.inputText
                                    selectByMouse: true
                                    selectionColor: Theme.inputSelection
                                    selectedTextColor: Theme.inputSelectionText
                                    Text {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        text: "e.g. --profile work"
                                        font: parent.font
                                        color: Theme.inputPlaceholder
                                        visible: !execArgsInput.text
                                    }
                                    Keys.onPressed: function(event) {
                                        if (event.key === Qt.Key_Up) {
                                            execPathInput.forceActiveFocus()
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            addExecForm.submitExecForm()
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Escape) {
                                            windowRoot.goBack()
                                            event.accepted = true
                                        }
                                    }
                                }
                            }
                        }

                        // Inline Form Error Text
                        Text {
                            id: execFormErrorText
                            Layout.fillWidth: true
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.error
                            font.bold: true
                            wrapMode: Text.Wrap
                            visible: text !== ""
                            text: addExecForm.internalFormError !== "" ? addExecForm.internalFormError : ((keybindingsModel.operationState === "error" && keybindingsModel.activeView === "add_exec") ? keybindingsModel.operationMessage : "")
                        }

                        // Buttons
                        RowLayout {
                            Layout.topMargin: Theme.spacingSm
                            spacing: Theme.spacingMd

                            Rectangle {
                                Layout.preferredHeight: 32
                                Layout.preferredWidth: submitLabel.implicitWidth + Theme.spacingLg * 2
                                radius: Theme.radiusSm
                                color: Theme.accent

                                Text {
                                    id: submitLabel
                                    anchors.centerIn: parent
                                    text: "Add Action"
                                    color: Theme.bgBase
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: addExecForm.submitExecForm()
                                }
                            }

                            Rectangle {
                                Layout.preferredHeight: 32
                                Layout.preferredWidth: cancelLabel.implicitWidth + Theme.spacingLg * 2
                                radius: Theme.radiusSm
                                color: "transparent"
                                border.color: Theme.border
                                border.width: 1

                                Text {
                                    id: cancelLabel
                                    anchors.centerIn: parent
                                    text: "Cancel"
                                    color: Theme.textSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: windowRoot.goBack()
                                }
                            }
                        }
                    }
                }
            }

            // Footer: High-contrast keyboard hint text and contextual actions
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.footerHeight
                Layout.leftMargin: Theme.spacingXl
                Layout.rightMargin: Theme.spacingXl
                Layout.bottomMargin: Theme.spacingSm

                RowLayout {
                    anchors.fill: parent
                    spacing: Theme.spacingLg

                    // 1. Conflict resolution mode
                    RowLayout {
                        spacing: Theme.spacingSm
                        visible: windowRoot.captureState === "conflict"

                        Text {
                            text: "↵"
                            color: Theme.warning
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Reassign Shortcut"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    // 2. Inline capture mode hints
                    RowLayout {
                        spacing: Theme.spacingSm
                        visible: (windowRoot.captureState === "capture_armed" || windowRoot.captureState === "entering_capture" || windowRoot.captureState === "validating")

                        Text {
                            text: "ESC"
                            color: Theme.rose
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Cancel"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                        Text {
                            text: "BACKSPACE"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Unset"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    // 3. Add Exec Form hints
                    RowLayout {
                        spacing: Theme.spacingSm
                        visible: !windowRoot.isRecording && keybindingsModel.activeView === "add_exec"

                        Text {
                            text: "↵"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Add Action"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                        Text {
                            text: "TAB"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Next Field"
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    // 4. Add Action Type Selection hints
                    RowLayout {
                        spacing: Theme.spacingSm
                        visible: !windowRoot.isRecording && keybindingsModel.activeView === "add_action_type"

                        Text {
                            text: "↵"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Select Type"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    // 5. ↵ Run / Add (active when runnable or in add_app, and not capturing)
                    RowLayout {
                        spacing: Theme.spacingXs
                        visible: !windowRoot.isRecording && keybindingsModel.operationState === "idle" && (keybindingsModel.activeView === "add_app" || (keybindingsModel.selectedItem && keybindingsModel.selectedItem.runnable === true))

                        Text {
                            text: "↵"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: (keybindingsModel.activeView === "add_app") ? "Add to Unbound" : "Run"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    // 6. S Set / Assign (active when editable, in bound or unbound view, and not capturing)
                    RowLayout {
                        spacing: Theme.spacingXs
                        visible: !windowRoot.isRecording && keybindingsModel.operationState === "idle" && (keybindingsModel.activeView === "bound" || keybindingsModel.activeView === "unbound") && keybindingsModel.selectedItem && keybindingsModel.selectedItem.editable === true

                        Text {
                            text: "S"
                            color: Theme.gold
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: (keybindingsModel.activeView === "unbound") ? "Assign" : "Set"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    // 7. U Unset (active in bound view when editable, bound, and not capturing)
                    RowLayout {
                        spacing: Theme.spacingXs
                        visible: !windowRoot.isRecording && keybindingsModel.operationState === "idle" && keybindingsModel.activeView === "bound" && keybindingsModel.selectedItem && keybindingsModel.selectedItem.editable === true &&
                                  keybindingsModel.selectedItem.display_key &&
                                  keybindingsModel.selectedItem.display_key !== "None (Unbound)"

                        Text {
                            text: "U"
                            color: Theme.love
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Unset"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    // 8. ALT + A Add Action / B Back
                    RowLayout {
                        spacing: Theme.spacingXs
                        visible: !windowRoot.isRecording && keybindingsModel.operationState === "idle" && keybindingsModel.activeView.indexOf("add_") !== 0

                        Text {
                            text: "ALT + A"
                            color: Theme.foam
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Add Action"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    RowLayout {
                        spacing: Theme.spacingXs
                        visible: !windowRoot.isRecording && keybindingsModel.operationState === "idle" && keybindingsModel.activeView.indexOf("add_") === 0

                        Text {
                            text: "B"
                            color: Theme.foam
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Back"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    // 9. TAB Switch View hint
                    RowLayout {
                        spacing: Theme.spacingXs
                        visible: !windowRoot.isRecording && keybindingsModel.operationState === "idle" && (keybindingsModel.activeView === "bound" || keybindingsModel.activeView === "unbound")

                        Text {
                            text: "TAB"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: (keybindingsModel.activeView === "bound") ? "Unbound" : "Bound"
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    // 10. Mouse Action Info
                    RowLayout {
                        spacing: Theme.spacingSm
                        visible: !windowRoot.isRecording && keybindingsModel.activeView === "bound" && keybindingsModel.selectedItem && (keybindingsModel.selectedItem.category === "Mouse Controls" || keybindingsModel.selectedItem.mouse === true)

                        Text {
                            text: "🖱 Mouse Action"
                            color: Theme.foam
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Compositor window gesture"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    // 11. System Binding Info
                    RowLayout {
                        spacing: Theme.spacingSm
                        visible: !windowRoot.isRecording && keybindingsModel.activeView === "bound" && keybindingsModel.selectedItem && keybindingsModel.selectedItem.editable === false && keybindingsModel.selectedItem.category !== "Mouse Controls" && !keybindingsModel.selectedItem.mouse

                        Text {
                            text: "• System Binding"
                            color: Theme.foam
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Compositor managed"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // ESC Close / Cancel / Back hint
                    RowLayout {
                        spacing: Theme.spacingSm
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                        Text {
                            text: "ESC"
                            color: Theme.rose
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: windowRoot.isRecording ? "Cancel" : ((keybindingsModel.activeView.indexOf("add_") === 0) ? "Back" : "Close")
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                    }
                }
            }
        }
    }
}
