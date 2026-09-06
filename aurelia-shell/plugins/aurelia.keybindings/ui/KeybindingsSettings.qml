import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../../theme"

// Keyboard-first preferences surface. Navigation state and mutations remain
// here; KeybindingsPreferenceRow is presentation-only.
Item {
    id: settingsRoot

    required property var model
    required property var window

    signal backRequested()

    property string editingPrefKey: ""
    property string statusMessage: ""
    property string statusType: "info"
    property int selectedIndex: 0

    readonly property int totalRows: 7
    readonly property bool isCompact: settingsContent.width < KeybindingsConfig.settingsBreakpointWidth
    readonly property var interfaceRows: [
        {
            title: "Add Action",
            description: "Open action creation",
            key: "components.keybindings.shortcuts.add_action"
        },
        {
            title: "Back",
            description: "Return or dismiss",
            key: "components.keybindings.shortcuts.back"
        },
        {
            title: "Set / Change",
            description: "Assign a shortcut",
            key: "components.keybindings.shortcuts.set_binding"
        },
        {
            title: "Unset",
            description: "Clear a shortcut",
            key: "components.keybindings.shortcuts.unset_binding"
        }
    ]
    readonly property var motionRows: [
        {
            title: "Animations",
            description: "Visual transitions",
            key: "motion.enabled"
        },
        {
            title: "Animation Speed",
            description: "Transition duration",
            key: "motion.scale"
        }
    ]

    function formatSpeedLabel(scale: real): string {
        if (scale <= 0.7) return "Faster"
        if (scale >= 1.3) return "Slower"
        return "Normal"
    }

    function selectRow(index: int) {
        selectedIndex = Math.max(0, Math.min(totalRows - 1, index))
        settingsRoot.forceActiveFocus()
    }

    function selectedItem() {
        if (selectedIndex < interfaceRows.length) return interfaceRepeater.itemAt(selectedIndex)
        if (selectedIndex < interfaceRows.length + motionRows.length) {
            return motionRepeater.itemAt(selectedIndex - interfaceRows.length)
        }
        return resetAction
    }

    function ensureSelectedVisible() {
        if (selectedIndex === 0) {
            settingsFlickable.contentY = 0
            return
        }
        var item = selectedItem()
        if (item) settingsFlickable.ensureVisible(item)
    }

    function moveSelection(delta: int) {
        selectRow(selectedIndex + delta)
        Qt.callLater(ensureSelectedVisible)
    }

    function startEditingShortcut(key: string, label: string) {
        editingPrefKey = key
        statusMessage = "Press key combination for " + label + " (Esc to cancel)..."
        statusType = "info"
        settingsRoot.forceActiveFocus()
    }

    function cancelEditing() {
        editingPrefKey = ""
        statusMessage = ""
        statusType = "info"
    }

    function toggleAnimations() {
        cancelEditing()
        var next = !Theme.componentMotionEnabled("keybindings")
        statusMessage = "Updating motion preference..."
        statusType = "info"
        model.setComponentPreference("components.keybindings.motion.enabled", next ? "true" : "false", function(ok, err) {
            if (ok) {
                Theme.reloadPreferences()
                statusMessage = "Keybindings animations " + (next ? "enabled." : "disabled.")
                statusType = "success"
            } else {
                statusMessage = "Error: " + err
                statusType = "error"
            }
        })
    }

    function cycleAnimationSpeed() {
        cancelEditing()
        var currentScale = Theme.componentMotionScale("keybindings")
        var nextScale = 1.0
        var nextLabel = "Normal"
        if (currentScale <= 0.7) {
            nextScale = 1.5
            nextLabel = "Slower"
        } else if (currentScale >= 1.3) {
            nextScale = 1.0
            nextLabel = "Normal"
        } else {
            nextScale = 0.5
            nextLabel = "Faster"
        }
        statusMessage = "Updating motion speed..."
        statusType = "info"
        model.setComponentPreference("components.keybindings.motion.scale", nextScale.toString(), function(ok, err) {
            if (ok) {
                Theme.reloadPreferences()
                statusMessage = "Animation speed set to " + nextLabel + "."
                statusType = "success"
            } else {
                statusMessage = "Error: " + err
                statusType = "error"
            }
        })
    }

    function resetToDefaults() {
        cancelEditing()
        statusMessage = "Resetting preferences..."
        statusType = "info"
        model.resetComponentPreferences(function(ok, err) {
            if (ok) {
                Theme.reloadPreferences()
                statusMessage = "Keybindings preferences reset."
                statusType = "success"
            } else {
                statusMessage = "Error: " + err
                statusType = "error"
            }
        })
    }

    function applyShortcutEdit(formattedKey: string) {
        var targetKey = editingPrefKey
        var isBackOrAdd = targetKey === "components.keybindings.shortcuts.add_action" ||
                          targetKey === "components.keybindings.shortcuts.back"

        if (isBackOrAdd && !window.hasModifier(formattedKey)) {
            statusMessage = "Error: This shortcut requires a modifier key (e.g. ALT)."
            statusType = "error"
            return
        }

        var shortcuts = [
            { key: "components.keybindings.shortcuts.add_action", val: Theme.shortcutAddAction, label: "Add Action" },
            { key: "components.keybindings.shortcuts.back", val: Theme.shortcutBack, label: "Back" },
            { key: "components.keybindings.shortcuts.set_binding", val: Theme.shortcutSet, label: "Set / Change" },
            { key: "components.keybindings.shortcuts.unset_binding", val: Theme.shortcutUnset, label: "Unset" }
        ]
        for (var i = 0; i < shortcuts.length; i++) {
            if (shortcuts[i].key !== targetKey &&
                shortcuts[i].val.toUpperCase() === formattedKey.toUpperCase()) {
                statusMessage = "Error: Conflict: Shortcut '" + formattedKey + "' is already assigned to " + shortcuts[i].label + "."
                statusType = "error"
                return
            }
        }

        editingPrefKey = ""
        statusMessage = "Updating preference..."
        statusType = "info"
        model.setComponentPreference(targetKey, formattedKey, function(ok, err) {
            if (ok) {
                Theme.reloadPreferences()
                statusMessage = "Updated shortcut to " + formattedKey + "."
                statusType = "success"
            } else {
                statusMessage = "Error: " + err
                statusType = "error"
            }
        })
    }

    function rowValue(rowIndex: int, rowData): string {
        if (rowIndex < interfaceRows.length) {
            if (editingPrefKey === rowData.key) return "Press key…"
            if (rowIndex === 0) return Theme.shortcutAddAction
            if (rowIndex === 1) return Theme.shortcutBack
            if (rowIndex === 2) return Theme.shortcutSet
            return Theme.shortcutUnset
        }
        if (rowData.key === "motion.enabled") {
            return Theme.componentMotionEnabled("keybindings") ? "On" : "Off"
        }
        return formatSpeedLabel(Theme.componentMotionScale("keybindings"))
    }

    function activateRow(index: int) {
        selectRow(index)
        if (index < interfaceRows.length) {
            var shortcut = interfaceRows[index]
            startEditingShortcut(shortcut.key, shortcut.title)
        } else if (index === interfaceRows.length) {
            toggleAnimations()
        } else if (index === interfaceRows.length + 1) {
            cycleAnimationSpeed()
        } else {
            resetToDefaults()
        }
    }

    onVisibleChanged: {
        if (visible) {
            editingPrefKey = ""
            statusMessage = ""
            statusType = "info"
            selectedIndex = 0
            settingsFlickable.contentY = 0
            Qt.callLater(function() {
                if (settingsRoot.visible) settingsRoot.forceActiveFocus()
            })
        } else {
            cancelEditing()
        }
    }

    onSelectedIndexChanged: {
        Qt.callLater(ensureSelectedVisible)
    }

    Keys.onPressed: function(event) {
        if (editingPrefKey !== "") {
            if (event.isAutoRepeat === true) {
                event.accepted = true
                return
            }
            if (window.isReturnOrEnter(event) && !window.claimActivationKey(event)) {
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_Escape) {
                cancelEditing()
                event.accepted = true
                return
            }
            var key = event.key
            if (key === Qt.Key_Control || key === Qt.Key_Shift || key === Qt.Key_Alt || key === Qt.Key_Meta) {
                event.accepted = true
                return
            }
            var formatted = window.formatKeyEvent(event)
            if (formatted) applyShortcutEdit(formatted)
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)) {
            window.cycleTopLevelView(true)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
            window.cycleTopLevelView(false)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Escape || window.eventMatchesShortcut(event, Theme.shortcutBack)) {
            backRequested()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Down) {
            moveSelection(1)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Up) {
            moveSelection(-1)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Home) {
            selectRow(0)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_End) {
            selectRow(totalRows - 1)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_PageDown) {
            moveSelection(3)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_PageUp) {
            moveSelection(-3)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            event.accepted = true
            if (window.claimActivationKey(event)) activateRow(selectedIndex)
            return
        }
        if (event.key === Qt.Key_Space) {
            if (event.isAutoRepeat !== true) activateRow(selectedIndex)
            event.accepted = true
        }
    }

    Keys.onReleased: function(event) {
        if (window && window.handleActivationKeyRelease(event)) return
    }

    Flickable {
        id: settingsFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: settingsContent.implicitHeight + (KeybindingsConfig.settingsMarginVertical * 2)
        clip: true
        focus: false
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            width: KeybindingsConfig.scrollBarWidth
            contentItem: Rectangle {
                color: Theme.selection
                radius: KeybindingsConfig.scrollBarWidth / 2
            }
        }

        function ensureVisible(item) {
            if (!item) return
            var pos = item.mapToItem(settingsFlickable.contentItem, 0, 0)
            var top = pos.y
            var bottom = top + item.height
            var maxY = Math.max(0, settingsFlickable.contentHeight - settingsFlickable.height)
            var nextY = settingsFlickable.contentY
            if (top < settingsFlickable.contentY + Theme.spacingXs) {
                nextY = top - Theme.spacingXs
            } else if (bottom > settingsFlickable.contentY + settingsFlickable.height - Theme.spacingXs) {
                nextY = bottom - settingsFlickable.height + Theme.spacingXs
            }
            settingsFlickable.contentY = Math.max(0, Math.min(maxY, nextY))
        }

        ColumnLayout {
            id: settingsContent
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: KeybindingsConfig.settingsMarginVertical
            width: Math.min(parent.width - (KeybindingsConfig.settingsMarginHorizontal * 2), KeybindingsConfig.settingsContentMaxWidth)
            spacing: KeybindingsConfig.settingsRowSpacing

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 58
                spacing: Theme.spacingMd

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "Keybindings"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXl
                        font.weight: Theme.fontWeightBold
                    }
                    Text {
                        text: "Keyboard-first controls"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                    }
                }

                Text {
                    text: "← Back"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Theme.fontWeightMedium
                    Layout.alignment: Qt.AlignTop
                    Layout.rightMargin: Theme.spacingXs

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Theme.spacingSm
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(mouse) {
                            mouse.accepted = true
                            backRequested()
                        }
                    }
                }
            }

            Text {
                text: "Interface"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: Theme.fontWeightMedium
                Layout.topMargin: Theme.spacingMd
            }

            Repeater {
                id: interfaceRepeater
                model: settingsRoot.interfaceRows
                delegate: KeybindingsPreferenceRow {
                    required property int index
                    required property var modelData
                    selected: settingsRoot.selectedIndex === index
                    editing: settingsRoot.editingPrefKey === modelData.key
                    title: modelData.title
                    description: modelData.description
                    value: settingsRoot.rowValue(index, modelData)
                    valueHeight: KeybindingsConfig.settingsBadgeHeight
                    valueMinWidth: KeybindingsConfig.settingsValueColumnPreferredWidth
                    onActivated: settingsRoot.activateRow(index)
                }
            }

            Text {
                text: "Motion"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                font.weight: Theme.fontWeightMedium
                Layout.topMargin: Theme.spacingSm
            }

            Repeater {
                id: motionRepeater
                model: settingsRoot.motionRows
                delegate: KeybindingsPreferenceRow {
                    required property int index
                    required property var modelData
                    readonly property int rowIndex: settingsRoot.interfaceRows.length + index
                    selected: settingsRoot.selectedIndex === rowIndex
                    editing: false
                    title: modelData.title
                    description: modelData.description
                    value: settingsRoot.rowValue(rowIndex, modelData)
                    valueHeight: KeybindingsConfig.settingsBadgeHeight
                    valueMinWidth: KeybindingsConfig.settingsValueColumnPreferredWidth
                    onActivated: settingsRoot.activateRow(rowIndex)
                }
            }

            Text {
                Layout.fillWidth: true
                text: settingsRoot.statusMessage
                color: settingsRoot.statusType === "error" ? Theme.error : (settingsRoot.statusType === "success" ? Theme.success : Theme.accent)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                wrapMode: Text.Wrap
                visible: settingsRoot.statusMessage !== ""
            }

            Item {
                id: resetAction
                Layout.fillWidth: true
                implicitHeight: 34

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Reset preferences"
                    color: settingsRoot.selectedIndex === settingsRoot.totalRows - 1 ? Theme.accent : Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        mouse.accepted = true
                        settingsRoot.selectRow(settingsRoot.totalRows - 1)
                        settingsRoot.resetToDefaults()
                    }
                }
            }

            Item {
                Layout.preferredHeight: KeybindingsConfig.settingsMarginVertical
            }
        }
    }
}
