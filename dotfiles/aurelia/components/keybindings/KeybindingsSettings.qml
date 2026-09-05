import QtQuick
import QtQuick.Layouts
import "../../theme"

Item {
    id: settingsRoot

    required property var model
    required property var window

    signal backRequested()

    property string editingPrefKey: ""
    property string statusMessage: ""
    property string statusType: "info" // "info", "error", "success"
    property int selectedIndex: 0

    // Row definitions:
    // 0: Add Action
    // 1: Back
    // 2: Set / Change
    // 3: Unset
    // 4: Animations (On/Off)
    // 5: Animation Speed (Normal / Faster / Slower)
    // 6: Reset Keybindings Preferences
    readonly property int totalRows: 7

    function formatSpeedLabel(scale: real): string {
        if (scale <= 0.7) return "Faster"
        if (scale >= 1.3) return "Slower"
        return "Normal"
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
        var current = Theme.componentMotionEnabled("keybindings")
        var next = !current
        statusMessage = "Updating motion preference..."
        statusType = "info"
        model.setComponentPreference("components.keybindings.motion.enabled", next ? "true" : "false", function(ok, err) {
            if (ok) {
                Theme.reloadPreferences()
                statusMessage = "Keybindings animations " + (next ? "enabled." : "disabled (0ms transitions).")
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
            // Faster -> Slower (1.5x)
            nextScale = 1.5
            nextLabel = "Slower"
        } else if (currentScale >= 1.3) {
            // Slower -> Normal (1.0x)
            nextScale = 1.0
            nextLabel = "Normal"
        } else {
            // Normal -> Faster (0.5x)
            nextScale = 0.5
            nextLabel = "Faster"
        }
        statusMessage = "Updating motion speed..."
        statusType = "info"
        model.setComponentPreference("components.keybindings.motion.scale", nextScale.toString(), function(ok, err) {
            if (ok) {
                Theme.reloadPreferences()
                statusMessage = "Keybindings animation speed set to " + nextLabel + " (" + nextScale.toString() + "x)."
                statusType = "success"
            } else {
                statusMessage = "Error: " + err
                statusType = "error"
            }
        })
    }

    function resetToDefaults() {
        cancelEditing()
        statusMessage = "Resetting preferences to defaults..."
        statusType = "info"
        model.resetComponentPreferences(function(ok, err) {
            if (ok) {
                Theme.reloadPreferences()
                statusMessage = "Keybindings preferences reset to shipped defaults."
                statusType = "success"
            } else {
                statusMessage = "Error: " + err
                statusType = "error"
            }
        })
    }

    function applyShortcutEdit(formattedKey: string) {
        var targetKey = editingPrefKey
        var isBackOrAdd = (targetKey === "components.keybindings.shortcuts.add_action" || targetKey === "components.keybindings.shortcuts.back")

        // Invariant: add_action and back require a modifier key (SUPER, CTRL, or ALT)
        if (isBackOrAdd && !window.hasModifier(formattedKey)) {
            statusMessage = "Error: This shortcut requires a modifier key (e.g. ALT) to prevent text conflicts."
            statusType = "error"
            return
        }

        // Conflict check against other 3 shortcuts
        var shortcuts = [
            { key: "components.keybindings.shortcuts.add_action", val: Theme.shortcutAddAction, label: "Add Action" },
            { key: "components.keybindings.shortcuts.back", val: Theme.shortcutBack, label: "Back" },
            { key: "components.keybindings.shortcuts.set_binding", val: Theme.shortcutSet, label: "Set / Change" },
            { key: "components.keybindings.shortcuts.unset_binding", val: Theme.shortcutUnset, label: "Unset" }
        ]
        for (var i = 0; i < shortcuts.length; i++) {
            if (shortcuts[i].key !== targetKey && shortcuts[i].val.toUpperCase() === formattedKey.toUpperCase()) {
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

    onVisibleChanged: {
        if (visible) {
            editingPrefKey = ""
            statusMessage = ""
            statusType = "info"
            selectedIndex = 0
            settingsRoot.forceActiveFocus()
        }
    }

    Keys.onPressed: function(event) {
        // 1. In-flight shortcut capture
        if (editingPrefKey !== "") {
            if (event.key === Qt.Key_Escape) {
                cancelEditing()
                event.accepted = true
                return
            }
            var k = event.key
            if (k === Qt.Key_Control || k === Qt.Key_Shift || k === Qt.Key_Alt || k === Qt.Key_Meta) {
                event.accepted = true
                return
            }
            var formatted = window.formatKeyEvent(event)
            if (!formatted || formatted === "") {
                event.accepted = true
                return
            }
            applyShortcutEdit(formatted)
            event.accepted = true
            return
        }

        // 2. Navigation and activation in settings view
        if (event.key === Qt.Key_Escape || window.eventMatchesShortcut(event, Theme.shortcutBack)) {
            backRequested()
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Down) {
            if (selectedIndex < totalRows - 1) selectedIndex++
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Up) {
            if (selectedIndex > 0) selectedIndex--
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            activateRow(selectedIndex)
            event.accepted = true
            return
        }
    }

    function activateRow(idx: int) {
        if (idx === 0) {
            startEditingShortcut("components.keybindings.shortcuts.add_action", "Add Action")
        } else if (idx === 1) {
            startEditingShortcut("components.keybindings.shortcuts.back", "Back")
        } else if (idx === 2) {
            startEditingShortcut("components.keybindings.shortcuts.set_binding", "Set / Change")
        } else if (idx === 3) {
            startEditingShortcut("components.keybindings.shortcuts.unset_binding", "Unset")
        } else if (idx === 4) {
            toggleAnimations()
        } else if (idx === 5) {
            cycleAnimationSpeed()
        } else if (idx === 6) {
            resetToDefaults()
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 580)
        spacing: Theme.spacingMd

        // Header row
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "⚙ Keybindings Preferences"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLg
                    font.weight: Theme.fontWeightBold
                    color: Theme.accent
                }

                Text {
                    text: "Configure keyboard shortcuts and motion for Keybindings."
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textSecondary
                }
            }

            Rectangle {
                Layout.preferredHeight: 28
                Layout.preferredWidth: backSettingsLabel.implicitWidth + Theme.spacingLg * 2
                radius: Theme.radiusSm
                color: backSettingsHover.hovered ? Theme.selection : "transparent"
                border.color: Theme.border
                border.width: 1

                HoverHandler {
                    id: backSettingsHover
                }

                Text {
                    id: backSettingsLabel
                    anchors.centerIn: parent
                    text: "← Back"
                    color: Theme.gold
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Theme.fontWeightMedium
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: backRequested()
                }
            }
        }

        // Section 1: Interface Shortcuts
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXs
            Layout.topMargin: Theme.spacingSm

            Text {
                text: "Interface Shortcuts"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: Theme.fontWeightBold
                color: Theme.accent
            }

            // Row 0: Add Action
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Theme.radiusSm
                color: (settingsRoot.selectedIndex === 0) ? Theme.selection : (row0Hover.hovered ? Theme.surfaceElevated : Theme.inputBg)
                border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.add_action") ? Theme.accent : ((settingsRoot.selectedIndex === 0) ? Theme.borderActive : Theme.border)
                border.width: 1

                HoverHandler { id: row0Hover }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingMd
                    anchors.rightMargin: Theme.spacingMd
                    spacing: Theme.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Add Action"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                            color: Theme.text
                        }
                        Text {
                            text: "Open action creation dialog (requires modifier)"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.textMuted
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        Layout.preferredHeight: 26
                        Layout.preferredWidth: 100
                        radius: Theme.radiusSm
                        color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.add_action") ? Theme.accent : Theme.surfaceElevated
                        border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.add_action") ? Theme.accent : Theme.border
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.add_action") ? "Press key…" : Theme.shortcutAddAction
                            color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.add_action") ? Theme.bgBase : Theme.foam
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightBold
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        settingsRoot.selectedIndex = 0
                        startEditingShortcut("components.keybindings.shortcuts.add_action", "Add Action")
                    }
                }
            }

            // Row 1: Back
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Theme.radiusSm
                color: (settingsRoot.selectedIndex === 1) ? Theme.selection : (row1Hover.hovered ? Theme.surfaceElevated : Theme.inputBg)
                border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.back") ? Theme.accent : ((settingsRoot.selectedIndex === 1) ? Theme.borderActive : Theme.border)
                border.width: 1

                HoverHandler { id: row1Hover }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingMd
                    anchors.rightMargin: Theme.spacingMd
                    spacing: Theme.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Back"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                            color: Theme.text
                        }
                        Text {
                            text: "Return to previous view / dismiss (requires modifier)"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.textMuted
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        Layout.preferredHeight: 26
                        Layout.preferredWidth: 100
                        radius: Theme.radiusSm
                        color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.back") ? Theme.accent : Theme.surfaceElevated
                        border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.back") ? Theme.accent : Theme.border
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.back") ? "Press key…" : Theme.shortcutBack
                            color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.back") ? Theme.bgBase : Theme.foam
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightBold
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        settingsRoot.selectedIndex = 1
                        startEditingShortcut("components.keybindings.shortcuts.back", "Back")
                    }
                }
            }

            // Row 2: Set / Change
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Theme.radiusSm
                color: (settingsRoot.selectedIndex === 2) ? Theme.selection : (row2Hover.hovered ? Theme.surfaceElevated : Theme.inputBg)
                border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.set_binding") ? Theme.accent : ((settingsRoot.selectedIndex === 2) ? Theme.borderActive : Theme.border)
                border.width: 1

                HoverHandler { id: row2Hover }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingMd
                    anchors.rightMargin: Theme.spacingMd
                    spacing: Theme.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Set / Change"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                            color: Theme.text
                        }
                        Text {
                            text: "Assign or edit shortcut for selected action"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.textMuted
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        Layout.preferredHeight: 26
                        Layout.preferredWidth: 100
                        radius: Theme.radiusSm
                        color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.set_binding") ? Theme.accent : Theme.surfaceElevated
                        border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.set_binding") ? Theme.accent : Theme.border
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.set_binding") ? "Press key…" : Theme.shortcutSet
                            color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.set_binding") ? Theme.bgBase : Theme.gold
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightBold
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        settingsRoot.selectedIndex = 2
                        startEditingShortcut("components.keybindings.shortcuts.set_binding", "Set / Change")
                    }
                }
            }

            // Row 3: Unset
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Theme.radiusSm
                color: (settingsRoot.selectedIndex === 3) ? Theme.selection : (row3Hover.hovered ? Theme.surfaceElevated : Theme.inputBg)
                border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.unset_binding") ? Theme.accent : ((settingsRoot.selectedIndex === 3) ? Theme.borderActive : Theme.border)
                border.width: 1

                HoverHandler { id: row3Hover }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingMd
                    anchors.rightMargin: Theme.spacingMd
                    spacing: Theme.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Unset"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                            color: Theme.text
                        }
                        Text {
                            text: "Clear shortcut for selected action"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.textMuted
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        Layout.preferredHeight: 26
                        Layout.preferredWidth: 100
                        radius: Theme.radiusSm
                        color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.unset_binding") ? Theme.accent : Theme.surfaceElevated
                        border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.unset_binding") ? Theme.accent : Theme.border
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.unset_binding") ? "Press key…" : Theme.shortcutUnset
                            color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.unset_binding") ? Theme.bgBase : Theme.love
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightBold
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        settingsRoot.selectedIndex = 3
                        startEditingShortcut("components.keybindings.shortcuts.unset_binding", "Unset")
                    }
                }
            }
        }

        // Section 2: Motion
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXs
            Layout.topMargin: Theme.spacingSm

            Text {
                text: "Motion"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: Theme.fontWeightBold
                color: Theme.accent
            }

            // Row 4: Animations (On / Off)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Theme.radiusSm
                color: (settingsRoot.selectedIndex === 4) ? Theme.selection : (row4Hover.hovered ? Theme.surfaceElevated : Theme.inputBg)
                border.color: (settingsRoot.selectedIndex === 4) ? Theme.borderActive : Theme.border
                border.width: 1

                HoverHandler { id: row4Hover }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingMd
                    anchors.rightMargin: Theme.spacingMd
                    spacing: Theme.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Animations"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                            color: Theme.text
                        }
                        Text {
                            text: "Enable visual transitions in Keybindings"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.textMuted
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        Layout.preferredHeight: 26
                        Layout.preferredWidth: 100
                        radius: Theme.radiusSm
                        color: Theme.componentMotionEnabled("keybindings") ? Theme.surfaceElevated : Theme.selection
                        border.color: Theme.componentMotionEnabled("keybindings") ? Theme.accent : Theme.border
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: Theme.componentMotionEnabled("keybindings") ? "On" : "Off"
                            color: Theme.componentMotionEnabled("keybindings") ? Theme.accent : Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightBold
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        settingsRoot.selectedIndex = 4
                        toggleAnimations()
                    }
                }
            }

            // Row 5: Animation Speed
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Theme.radiusSm
                color: (settingsRoot.selectedIndex === 5) ? Theme.selection : (row5Hover.hovered ? Theme.surfaceElevated : Theme.inputBg)
                border.color: (settingsRoot.selectedIndex === 5) ? Theme.borderActive : Theme.border
                border.width: 1

                HoverHandler { id: row5Hover }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingMd
                    anchors.rightMargin: Theme.spacingMd
                    spacing: Theme.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Animation Speed"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                            color: Theme.text
                        }
                        Text {
                            text: "Visual transition duration multiplier"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.textMuted
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        Layout.preferredHeight: 26
                        Layout.preferredWidth: 100
                        radius: Theme.radiusSm
                        color: Theme.surfaceElevated
                        border.color: Theme.border
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: formatSpeedLabel(Theme.componentMotionScale("keybindings"))
                            color: Theme.gold
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightBold
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        settingsRoot.selectedIndex = 5
                        cycleAnimationSpeed()
                    }
                }
            }
        }

        // Status message text
        Text {
            Layout.fillWidth: true
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            color: (settingsRoot.statusType === "error") ? Theme.error : ((settingsRoot.statusType === "success") ? Theme.success : Theme.accent)
            font.bold: true
            wrapMode: Text.Wrap
            visible: settingsRoot.statusMessage !== ""
            text: settingsRoot.statusMessage
        }

        // Row 6: Reset to Defaults
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingSm
            spacing: Theme.spacingMd

            Rectangle {
                Layout.preferredHeight: 32
                Layout.preferredWidth: resetLabel.implicitWidth + Theme.spacingLg * 2
                radius: Theme.radiusSm
                color: (settingsRoot.selectedIndex === 6) ? Theme.selectionActive : (resetHover.hovered ? Theme.selection : "transparent")
                border.color: (settingsRoot.selectedIndex === 6) ? Theme.borderActive : Theme.border
                border.width: 1

                HoverHandler { id: resetHover }

                Text {
                    id: resetLabel
                    anchors.centerIn: parent
                    text: "↺ Reset Keybindings Preferences"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        settingsRoot.selectedIndex = 6
                        resetToDefaults()
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}
