import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../../theme"

PanelWindow {
    id: windowRoot

    // Layer-shell Wayland configuration: centered overlay surface with on-demand focus
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // Window dimensions: restrained command palette proportions from design system (800x480)
    implicitWidth: Theme.paletteWidth // 800
    implicitHeight: Theme.paletteHeight // 480
    color: "transparent"

    property bool isRecording: (keybindingsModel.operationState === "capturing")
    property var recordingItem: null
    property alias keybindingsModel: keybindingsModel
    property alias hotkeysModel: keybindingsModel

    function cancelCapture() {
        if (keybindingsModel.operationState !== "idle") {
            keybindingsModel.operationState = "idle"
            keybindingsModel.operationMessage = ""
            windowRoot.recordingItem = null
        }
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

    // Modal surface card with dynamic theme-aware active border highlight on focus/hover
    Rectangle {
        id: surfaceCard
        anchors.fill: parent
        radius: Theme.radiusMd
        color: Theme.bgBase
        border.color: (surfaceHover.hovered || searchInput.activeFocus) ? Theme.borderActive : Theme.border
        border.width: Theme.borderWidthFocus
        clip: true

        HoverHandler {
            id: surfaceHover
        }

        Behavior on border.color {
            ColorAnimation { duration: Theme.durationFast }
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (keybindingsModel.operationState !== "idle") {
                    windowRoot.cancelCapture()
                } else if (keybindingsModel.activeView === "add_app") {
                    keybindingsModel.switchView("unbound")
                } else {
                    windowRoot.visible = false
                }
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
                    readOnly: (keybindingsModel.operationState === "capturing" || keybindingsModel.operationState === "applying")

                    // Idle placeholder
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
                        text: "add application_"
                        color: Theme.textSubtle
                        font: parent.font
                        visible: !searchInput.text && (keybindingsModel.operationState === "idle") && (keybindingsModel.activeView === "add_app")
                    }

                    // Capturing active prompt
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: (keybindingsModel.operationState === "capturing") ? ("Set " + (windowRoot.recordingItem ? windowRoot.recordingItem.description : "Shortcut") + " — press key combination...") : ""
                        color: Theme.accent
                        font: parent.font
                        visible: (keybindingsModel.operationState === "capturing")
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
                        visible: (keybindingsModel.operationState === "success" || keybindingsModel.operationState === "conflict" || keybindingsModel.operationState === "error")
                    }

                    onTextChanged: {
                        if (keybindingsModel.operationState !== "idle") {
                            keybindingsModel.operationState = "idle"
                            keybindingsModel.operationMessage = ""
                            windowRoot.recordingItem = null
                        }
                        keybindingsModel.searchQuery = text
                    }

                    Keys.onPressed: function(event) {
                        // 1. Handling during inline capture mode
                        if (keybindingsModel.operationState === "capturing") {
                            if (event.key === Qt.Key_Escape) {
                                cancelCapture()
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
                                if (windowRoot.recordingItem) {
                                    keybindingsModel.unsetShortcut(windowRoot.recordingItem.id)
                                }
                                event.accepted = true
                                return
                            }
                            var formatted = windowRoot.formatKeyEvent(event)
                            if (formatted && formatted !== "") {
                                if (windowRoot.recordingItem) {
                                    keybindingsModel.setShortcut(windowRoot.recordingItem.id, formatted)
                                }
                            }
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
                            if (keybindingsModel.activeView === "add_app") {
                                keybindingsModel.switchView("unbound")
                            } else {
                                keybindingsModel.toggleView()
                            }
                            event.accepted = true
                            return
                        }

                        // 4. Normal idle navigation, view switching, and execution
                        if (event.key === Qt.Key_Escape) {
                            if (keybindingsModel.activeView === "add_app") {
                                keybindingsModel.switchView("unbound")
                            } else {
                                windowRoot.visible = false
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down) {
                            keybindingsModel.selectNext()
                            listView.positionViewAtIndex(keybindingsModel.selectedIndex, ListView.Contain)
                            listView.forceActiveFocus()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            keybindingsModel.selectPrevious()
                            listView.positionViewAtIndex(keybindingsModel.selectedIndex, ListView.Contain)
                            listView.forceActiveFocus()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (keybindingsModel.activeView === "add_app") {
                                var appItem = keybindingsModel.selectedItem
                                if (appItem && appItem.desktop_id) {
                                    keybindingsModel.addApplication(appItem.desktop_id)
                                }
                            } else if (keybindingsModel.runSelected()) {
                                windowRoot.visible = false
                            }
                            event.accepted = true
                        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_A) {
                            if (keybindingsModel.activeView === "add_app") {
                                keybindingsModel.switchView("unbound")
                            } else {
                                keybindingsModel.switchView("add_app")
                            }
                            event.accepted = true
                        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_S) {
                            if (keybindingsModel.activeView === "add_app") {
                                var appToAdd = keybindingsModel.selectedItem
                                if (appToAdd && appToAdd.desktop_id) {
                                    keybindingsModel.addApplication(appToAdd.desktop_id)
                                }
                            } else {
                                var item = keybindingsModel.selectedItem
                                if (!item) {
                                    event.accepted = true
                                    return
                                }
                                if (item.editable !== true) {
                                    keybindingsModel.operationState = "error"
                                    keybindingsModel.operationMessage = "Immutable: System binding cannot be modified."
                                } else {
                                    windowRoot.recordingItem = item
                                    keybindingsModel.operationState = "capturing"
                                    keybindingsModel.operationMessage = ""
                                }
                            }
                            event.accepted = true
                        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_U) {
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
                        }
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

                // Add Application / Back tab
                Rectangle {
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: addAppText.implicitWidth + Theme.spacingMd * 2
                    radius: Theme.radiusSm
                    color: (keybindingsModel.activeView === "add_app") ? Theme.selection : "transparent"

                    Text {
                        id: addAppText
                        anchors.centerIn: parent
                        text: (keybindingsModel.activeView === "add_app") ? "← Back to Shortcuts" : "+ Add Application"
                        color: (keybindingsModel.activeView === "add_app") ? Theme.gold : Theme.foam
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Theme.fontWeightMedium
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (keybindingsModel.activeView === "add_app") {
                                keybindingsModel.switchView("unbound")
                            } else {
                                keybindingsModel.switchView("add_app")
                            }
                        }
                    }
                }
            }

            // Body: Shortcut List or Restrained Empty State
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: Theme.spacingMd
                Layout.rightMargin: Theme.spacingMd

                ListView {
                    id: listView
                    anchors.fill: parent
                    spacing: Theme.rowSpacing
                    clip: true
                    model: keybindingsModel.filteredItems
                    currentIndex: keybindingsModel.selectedIndex
                    focus: true

                    delegate: KeybindingRow {
                        isSelected: index === keybindingsModel.selectedIndex
                    }

                    Keys.onPressed: function(event) {
                        // 1. Handling during inline capture mode
                        if (keybindingsModel.operationState === "capturing") {
                            if (event.key === Qt.Key_Escape) {
                                cancelCapture()
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
                                if (windowRoot.recordingItem) {
                                    keybindingsModel.unsetShortcut(windowRoot.recordingItem.id)
                                }
                                event.accepted = true
                                return
                            }
                            var formatted = windowRoot.formatKeyEvent(event)
                            if (formatted && formatted !== "") {
                                if (windowRoot.recordingItem) {
                                    keybindingsModel.setShortcut(windowRoot.recordingItem.id, formatted)
                                }
                            }
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
                            if (keybindingsModel.activeView === "add_app") {
                                keybindingsModel.switchView("unbound")
                            } else {
                                keybindingsModel.toggleView()
                            }
                            event.accepted = true
                            return
                        }

                        // 4. Escape: back or close
                        if (event.key === Qt.Key_Escape) {
                            if (keybindingsModel.activeView === "add_app") {
                                keybindingsModel.switchView("unbound")
                            } else {
                                windowRoot.visible = false
                            }
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

                        // 6. Return / Enter: Run or Add
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (keybindingsModel.activeView === "add_app") {
                                var appItem = keybindingsModel.selectedItem
                                if (appItem && appItem.desktop_id) {
                                    keybindingsModel.addApplication(appItem.desktop_id)
                                }
                            } else if (keybindingsModel.runSelected()) {
                                windowRoot.visible = false
                            }
                            event.accepted = true
                            return
                        }

                        // 7. S -> Set / Edit hotkey (or Alt+S)
                        if ((event.key === Qt.Key_S && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) || ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_S)) {
                            if (keybindingsModel.activeView === "add_app") {
                                event.accepted = true
                                return
                            }
                            var item = keybindingsModel.selectedItem
                            if (!item) {
                                event.accepted = true
                                return
                            }
                            if (item.editable !== true) {
                                keybindingsModel.operationState = "error"
                                keybindingsModel.operationMessage = "Immutable: System binding cannot be modified."
                            } else {
                                windowRoot.recordingItem = item
                                keybindingsModel.operationState = "capturing"
                                keybindingsModel.operationMessage = ""
                            }
                            event.accepted = true
                            return
                        }

                        // 8. U -> Unset / Clear hotkey (or Alt+U)
                        if ((event.key === Qt.Key_U && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) || ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_U)) {
                            if (keybindingsModel.activeView === "add_app") {
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

                        // 9. Alt+A -> Add Application
                        if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_A) {
                            if (keybindingsModel.activeView === "add_app") {
                                keybindingsModel.switchView("unbound")
                            } else {
                                keybindingsModel.switchView("add_app")
                            }
                            event.accepted = true
                            return
                        }

                        // 10. Slash, Backspace, or printable text redirects to searchInput
                        if (event.key === Qt.Key_Slash || event.key === Qt.Key_Backspace || (event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32)) {
                            searchInput.forceActiveFocus()
                            if (event.key !== Qt.Key_Slash) {
                                searchInput.text = searchInput.text + event.text
                            }
                            event.accepted = true
                            return
                        }
                    }

                    // Extremely subtle scrollbar indicator
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
                    text: (keybindingsModel.activeView === "add_app") ? (keybindingsModel.isLoadingApps ? "Discovering installed applications..." : "No matching applications found") : (keybindingsModel.activeView === "unbound" ? "No unbound shortcuts (press Alt+A to add an application)" : "No matching shortcuts")
                    color: Theme.textSubtle
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    visible: keybindingsModel.filteredItems.length === 0
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

                    // ↵ Run / Add (active when runnable or in add_app, and not capturing)
                    RowLayout {
                        spacing: Theme.spacingXs
                        visible: (keybindingsModel.operationState === "idle" && (keybindingsModel.activeView === "add_app" || (keybindingsModel.selectedItem && keybindingsModel.selectedItem.runnable === true)))

                        Text {
                            text: "↵"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: (keybindingsModel.activeView === "add_app") ? "Add" : "Run"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    // S Set / Assign (active when editable, not add_app, and not capturing)
                    RowLayout {
                        spacing: Theme.spacingXs
                        visible: (keybindingsModel.operationState === "idle" && keybindingsModel.activeView !== "add_app" && keybindingsModel.selectedItem && keybindingsModel.selectedItem.editable === true)

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

                    // U Unset (active in bound view when editable, bound, and not capturing)
                    RowLayout {
                        spacing: Theme.spacingXs
                        visible: (keybindingsModel.operationState === "idle" && keybindingsModel.activeView === "bound" && keybindingsModel.selectedItem && keybindingsModel.selectedItem.editable === true &&
                                  keybindingsModel.selectedItem.display_key &&
                                  keybindingsModel.selectedItem.display_key !== "None (Unbound)")

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

                    // Alt+A Add Application (in unbound view)
                    RowLayout {
                        spacing: Theme.spacingXs
                        visible: (keybindingsModel.operationState === "idle" && keybindingsModel.activeView === "unbound")

                        Text {
                            text: "Alt+A"
                            color: Theme.foam
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Add App"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    // Tab Switch View hint
                    RowLayout {
                        spacing: Theme.spacingXs
                        visible: (keybindingsModel.operationState === "idle" && keybindingsModel.activeView !== "add_app")

                        Text {
                            text: "Tab"
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

                    // Mouse Action Info
                    RowLayout {
                        spacing: Theme.spacingSm
                        visible: (keybindingsModel.activeView === "bound" && keybindingsModel.selectedItem && (keybindingsModel.selectedItem.category === "Mouse Controls" || keybindingsModel.selectedItem.mouse === true))

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

                    // System Binding Info
                    RowLayout {
                        spacing: Theme.spacingSm
                        visible: (keybindingsModel.activeView === "bound" && keybindingsModel.selectedItem && keybindingsModel.selectedItem.editable === false && keybindingsModel.selectedItem.category !== "Mouse Controls" && !keybindingsModel.selectedItem.mouse)

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

                    // Inline state hints
                    RowLayout {
                        spacing: Theme.spacingXs
                        visible: (keybindingsModel.operationState === "capturing")

                        Text {
                            text: "Esc Cancel    Backspace Unset"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // Esc Close / Cancel / Back hint
                    RowLayout {
                        spacing: Theme.spacingSm
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                        Text {
                            text: "Esc"
                            color: Theme.rose
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: (keybindingsModel.operationState !== "idle") ? "Cancel" : ((keybindingsModel.activeView === "add_app") ? "Back" : "Close")
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
