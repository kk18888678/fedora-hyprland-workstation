import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
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
    readonly property bool isCompact: settingsContent.width < KeybindingsConfig.settingsBreakpointWidth

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
            settingsFlickable.contentY = 0
            settingsRoot.forceActiveFocus()
        }
    }

    onSelectedIndexChanged: {
        var rowItems = [row0, row1, row2, row3, row4, row5, row6]
        if (selectedIndex >= 0 && selectedIndex < rowItems.length && rowItems[selectedIndex]) {
            settingsFlickable.ensureVisible(rowItems[selectedIndex])
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

        // 2. Tab immediate top-level view cycling (when not capturing)
        if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)) {
            if (window && typeof window.cycleTopLevelView === "function") {
                window.cycleTopLevelView(true)
            }
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
            if (window && typeof window.cycleTopLevelView === "function") {
                window.cycleTopLevelView(false)
            }
            event.accepted = true
            return
        }

        // 3. Navigation and activation in settings view
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

    Flickable {
        id: settingsFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: settingsContent.implicitHeight + (KeybindingsConfig.settingsMarginVertical * 2)
        clip: true
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
            var pos = item.mapToItem(settingsContent, 0, 0)
            var yInContent = pos.y
            var itemH = item.height
            if (yInContent < settingsFlickable.contentY) {
                settingsFlickable.contentY = yInContent
            } else if (yInContent + itemH > settingsFlickable.contentY + settingsFlickable.height) {
                settingsFlickable.contentY = Math.max(0, yInContent + itemH - settingsFlickable.height)
            }
        }

        ColumnLayout {
            id: settingsContent
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: KeybindingsConfig.settingsMarginVertical
            width: Math.min(parent.width - (KeybindingsConfig.settingsMarginHorizontal * 2), KeybindingsConfig.settingsContentMaxWidth)
            spacing: KeybindingsConfig.settingsRowSpacing

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
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    Layout.preferredHeight: KeybindingsConfig.tabHeight
                    Layout.preferredWidth: backSettingsLabel.implicitWidth + (KeybindingsConfig.tabPaddingHorizontal * 2)
                    radius: KeybindingsConfig.tabBorderRadius
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
                spacing: KeybindingsConfig.settingsRowSpacing
                Layout.topMargin: KeybindingsConfig.settingsSectionSpacing / 2

                Text {
                    text: "Interface Shortcuts"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Theme.fontWeightBold
                    color: Theme.accent
                }

                // Row 0: Add Action
                Rectangle {
                    id: row0
                    Layout.fillWidth: true
                    implicitHeight: layout0.implicitHeight + (Theme.spacingMd * 2)
                    Layout.preferredHeight: settingsRoot.isCompact ? -1 : Math.max(KeybindingsConfig.settingsRowMinHeight, implicitHeight)
                    radius: Theme.radiusSm
                    color: (settingsRoot.selectedIndex === 0) ? Theme.selection : (row0Hover.hovered ? Theme.surfaceElevated : Theme.inputBg)
                    border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.add_action") ? Theme.accent : ((settingsRoot.selectedIndex === 0) ? Theme.borderActive : Theme.border)
                    border.width: 1

                    HoverHandler { id: row0Hover }

                    GridLayout {
                        id: layout0
                        columns: settingsRoot.isCompact ? 1 : 2
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingMd
                        anchors.rightMargin: Theme.spacingMd
                        rowSpacing: Theme.spacingSm
                        columnSpacing: Theme.spacingMd

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
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
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }

                        Rectangle {
                            Layout.alignment: settingsRoot.isCompact ? (Qt.AlignLeft | Qt.AlignVCenter) : (Qt.AlignRight | Qt.AlignVCenter)
                            Layout.preferredHeight: KeybindingsConfig.settingsBadgeHeight
                            Layout.preferredWidth: Math.max(KeybindingsConfig.settingsValueColumnPreferredWidth, badgeText0.implicitWidth + KeybindingsConfig.settingsBadgePaddingHorizontal * 2)
                            radius: KeybindingsConfig.settingsBadgeRadius
                            color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.add_action") ? Theme.accent : Theme.surfaceElevated
                            border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.add_action") ? Theme.accent : Theme.border
                            border.width: 1

                            Text {
                                id: badgeText0
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
                    id: row1
                    Layout.fillWidth: true
                    implicitHeight: layout1.implicitHeight + (Theme.spacingMd * 2)
                    Layout.preferredHeight: settingsRoot.isCompact ? -1 : Math.max(KeybindingsConfig.settingsRowMinHeight, implicitHeight)
                    radius: Theme.radiusSm
                    color: (settingsRoot.selectedIndex === 1) ? Theme.selection : (row1Hover.hovered ? Theme.surfaceElevated : Theme.inputBg)
                    border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.back") ? Theme.accent : ((settingsRoot.selectedIndex === 1) ? Theme.borderActive : Theme.border)
                    border.width: 1

                    HoverHandler { id: row1Hover }

                    GridLayout {
                        id: layout1
                        columns: settingsRoot.isCompact ? 1 : 2
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingMd
                        anchors.rightMargin: Theme.spacingMd
                        rowSpacing: Theme.spacingSm
                        columnSpacing: Theme.spacingMd

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
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
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }

                        Rectangle {
                            Layout.alignment: settingsRoot.isCompact ? (Qt.AlignLeft | Qt.AlignVCenter) : (Qt.AlignRight | Qt.AlignVCenter)
                            Layout.preferredHeight: KeybindingsConfig.settingsBadgeHeight
                            Layout.preferredWidth: Math.max(KeybindingsConfig.settingsValueColumnPreferredWidth, badgeText1.implicitWidth + KeybindingsConfig.settingsBadgePaddingHorizontal * 2)
                            radius: KeybindingsConfig.settingsBadgeRadius
                            color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.back") ? Theme.accent : Theme.surfaceElevated
                            border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.back") ? Theme.accent : Theme.border
                            border.width: 1

                            Text {
                                id: badgeText1
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
                    id: row2
                    Layout.fillWidth: true
                    implicitHeight: layout2.implicitHeight + (Theme.spacingMd * 2)
                    Layout.preferredHeight: settingsRoot.isCompact ? -1 : Math.max(KeybindingsConfig.settingsRowMinHeight, implicitHeight)
                    radius: Theme.radiusSm
                    color: (settingsRoot.selectedIndex === 2) ? Theme.selection : (row2Hover.hovered ? Theme.surfaceElevated : Theme.inputBg)
                    border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.set_binding") ? Theme.accent : ((settingsRoot.selectedIndex === 2) ? Theme.borderActive : Theme.border)
                    border.width: 1

                    HoverHandler { id: row2Hover }

                    GridLayout {
                        id: layout2
                        columns: settingsRoot.isCompact ? 1 : 2
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingMd
                        anchors.rightMargin: Theme.spacingMd
                        rowSpacing: Theme.spacingSm
                        columnSpacing: Theme.spacingMd

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
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
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }

                        Rectangle {
                            Layout.alignment: settingsRoot.isCompact ? (Qt.AlignLeft | Qt.AlignVCenter) : (Qt.AlignRight | Qt.AlignVCenter)
                            Layout.preferredHeight: KeybindingsConfig.settingsBadgeHeight
                            Layout.preferredWidth: Math.max(KeybindingsConfig.settingsValueColumnPreferredWidth, badgeText2.implicitWidth + KeybindingsConfig.settingsBadgePaddingHorizontal * 2)
                            radius: KeybindingsConfig.settingsBadgeRadius
                            color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.set_binding") ? Theme.accent : Theme.surfaceElevated
                            border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.set_binding") ? Theme.accent : Theme.border
                            border.width: 1

                            Text {
                                id: badgeText2
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
                    id: row3
                    Layout.fillWidth: true
                    implicitHeight: layout3.implicitHeight + (Theme.spacingMd * 2)
                    Layout.preferredHeight: settingsRoot.isCompact ? -1 : Math.max(KeybindingsConfig.settingsRowMinHeight, implicitHeight)
                    radius: Theme.radiusSm
                    color: (settingsRoot.selectedIndex === 3) ? Theme.selection : (row3Hover.hovered ? Theme.surfaceElevated : Theme.inputBg)
                    border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.unset_binding") ? Theme.accent : ((settingsRoot.selectedIndex === 3) ? Theme.borderActive : Theme.border)
                    border.width: 1

                    HoverHandler { id: row3Hover }

                    GridLayout {
                        id: layout3
                        columns: settingsRoot.isCompact ? 1 : 2
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingMd
                        anchors.rightMargin: Theme.spacingMd
                        rowSpacing: Theme.spacingSm
                        columnSpacing: Theme.spacingMd

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
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
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }

                        Rectangle {
                            Layout.alignment: settingsRoot.isCompact ? (Qt.AlignLeft | Qt.AlignVCenter) : (Qt.AlignRight | Qt.AlignVCenter)
                            Layout.preferredHeight: KeybindingsConfig.settingsBadgeHeight
                            Layout.preferredWidth: Math.max(KeybindingsConfig.settingsValueColumnPreferredWidth, badgeText3.implicitWidth + KeybindingsConfig.settingsBadgePaddingHorizontal * 2)
                            radius: KeybindingsConfig.settingsBadgeRadius
                            color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.unset_binding") ? Theme.accent : Theme.surfaceElevated
                            border.color: (settingsRoot.editingPrefKey === "components.keybindings.shortcuts.unset_binding") ? Theme.accent : Theme.border
                            border.width: 1

                            Text {
                                id: badgeText3
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
                spacing: KeybindingsConfig.settingsRowSpacing
                Layout.topMargin: KeybindingsConfig.settingsSectionSpacing / 2

                Text {
                    text: "Motion"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Theme.fontWeightBold
                    color: Theme.accent
                }

                // Row 4: Animations (On / Off)
                Rectangle {
                    id: row4
                    Layout.fillWidth: true
                    implicitHeight: layout4.implicitHeight + (Theme.spacingMd * 2)
                    Layout.preferredHeight: settingsRoot.isCompact ? -1 : Math.max(KeybindingsConfig.settingsRowMinHeight, implicitHeight)
                    radius: Theme.radiusSm
                    color: (settingsRoot.selectedIndex === 4) ? Theme.selection : (row4Hover.hovered ? Theme.surfaceElevated : Theme.inputBg)
                    border.color: (settingsRoot.selectedIndex === 4) ? Theme.borderActive : Theme.border
                    border.width: 1

                    HoverHandler { id: row4Hover }

                    GridLayout {
                        id: layout4
                        columns: settingsRoot.isCompact ? 1 : 2
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingMd
                        anchors.rightMargin: Theme.spacingMd
                        rowSpacing: Theme.spacingSm
                        columnSpacing: Theme.spacingMd

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
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
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }

                        Rectangle {
                            Layout.alignment: settingsRoot.isCompact ? (Qt.AlignLeft | Qt.AlignVCenter) : (Qt.AlignRight | Qt.AlignVCenter)
                            Layout.preferredHeight: KeybindingsConfig.settingsBadgeHeight
                            Layout.preferredWidth: Math.max(KeybindingsConfig.settingsValueColumnPreferredWidth, badgeText4.implicitWidth + KeybindingsConfig.settingsBadgePaddingHorizontal * 2)
                            radius: KeybindingsConfig.settingsBadgeRadius
                            color: Theme.componentMotionEnabled("keybindings") ? Theme.surfaceElevated : Theme.selection
                            border.color: Theme.componentMotionEnabled("keybindings") ? Theme.accent : Theme.border
                            border.width: 1

                            Text {
                                id: badgeText4
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
                    id: row5
                    Layout.fillWidth: true
                    implicitHeight: layout5.implicitHeight + (Theme.spacingMd * 2)
                    Layout.preferredHeight: settingsRoot.isCompact ? -1 : Math.max(KeybindingsConfig.settingsRowMinHeight, implicitHeight)
                    radius: Theme.radiusSm
                    color: (settingsRoot.selectedIndex === 5) ? Theme.selection : (row5Hover.hovered ? Theme.surfaceElevated : Theme.inputBg)
                    border.color: (settingsRoot.selectedIndex === 5) ? Theme.borderActive : Theme.border
                    border.width: 1

                    HoverHandler { id: row5Hover }

                    GridLayout {
                        id: layout5
                        columns: settingsRoot.isCompact ? 1 : 2
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingMd
                        anchors.rightMargin: Theme.spacingMd
                        rowSpacing: Theme.spacingSm
                        columnSpacing: Theme.spacingMd

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
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
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }

                        Rectangle {
                            Layout.alignment: settingsRoot.isCompact ? (Qt.AlignLeft | Qt.AlignVCenter) : (Qt.AlignRight | Qt.AlignVCenter)
                            Layout.preferredHeight: KeybindingsConfig.settingsBadgeHeight
                            Layout.preferredWidth: Math.max(KeybindingsConfig.settingsValueColumnPreferredWidth, badgeText5.implicitWidth + KeybindingsConfig.settingsBadgePaddingHorizontal * 2)
                            radius: KeybindingsConfig.settingsBadgeRadius
                            color: Theme.surfaceElevated
                            border.color: Theme.border
                            border.width: 1

                            Text {
                                id: badgeText5
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
                id: row6
                Layout.fillWidth: true
                Layout.topMargin: KeybindingsConfig.settingsSectionSpacing / 2
                spacing: Theme.spacingMd

                Rectangle {
                    Layout.preferredHeight: KeybindingsConfig.tabHeight
                    Layout.preferredWidth: resetLabel.implicitWidth + (KeybindingsConfig.tabPaddingHorizontal * 2)
                    radius: KeybindingsConfig.tabBorderRadius
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
}
