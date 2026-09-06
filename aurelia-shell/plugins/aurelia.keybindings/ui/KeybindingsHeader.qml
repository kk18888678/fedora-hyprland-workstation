import QtQuick
import QtQuick.Layouts
import "."
import "../../../theme"

// Presentation and input surface for the search field and top-level tabs.
// Navigation remains owned by the Window controller; this component only
// translates input into controller calls.
ColumnLayout {
    id: headerRoot

    required property var modelController
    required property var windowController
    property alias searchInput: searchInput

    readonly property bool headerVisible: modelController.activeView !== "add_exec" && modelController.activeView !== "settings"
    Layout.fillWidth: true
    Layout.preferredHeight: headerVisible ? (Theme.searchHeight + Theme.spacingLg + Theme.spacingSm + KeybindingsConfig.headerHeight + Theme.spacingSm) : 0
    spacing: 0
    visible: headerVisible

    function focusSearch() {
        searchInput.forceActiveFocus()
    }

    // Search input: intentionally the only text-editing surface in the
    // header. Plain s/u/b/a remain ordinary text when no configured modifier
    // is present.
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
            readOnly: (windowController.isRecording || modelController.operationState === "applying")

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: "keybindings_"
                color: Theme.textSubtle
                font: parent.font
                visible: !searchInput.text && modelController.operationState === "idle" && modelController.activeView === "bound"
            }

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: "keybindings_ (unbound)"
                color: Theme.textSubtle
                font: parent.font
                visible: !searchInput.text && modelController.operationState === "idle" && modelController.activeView === "unbound"
            }

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: "choose action type_"
                color: Theme.textSubtle
                font: parent.font
                visible: !searchInput.text && modelController.operationState === "idle" && modelController.activeView === "add_action_type"
            }

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: "add application_"
                color: Theme.textSubtle
                font: parent.font
                visible: !searchInput.text && modelController.operationState === "idle" && modelController.activeView === "add_app"
            }

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: (windowController.captureState === "entering_capture") ? "Release key to begin shortcut recording..." : ((windowController.captureState === "capture_armed") ? ("Set " + (windowController.recordingItem ? windowController.recordingItem.description : "Shortcut") + " — press key combination...") : "")
                color: Theme.accent
                font: parent.font
                visible: windowController.captureState === "entering_capture" || windowController.captureState === "capture_armed"
            }

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: "Validating " + windowController.candidateKey + "..."
                color: Theme.gold
                font: parent.font
                visible: windowController.captureState === "validating"
            }

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: "Applying changes..."
                color: Theme.gold
                font: parent.font
                visible: modelController.operationState === "applying"
            }

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: modelController.operationMessage
                color: modelController.operationState === "success" ? Theme.success : (modelController.operationState === "conflict" ? Theme.warning : Theme.error)
                font.family: parent.font.family
                font.pixelSize: parent.font.pixelSize
                font.bold: true
                visible: modelController.operationState === "success" || modelController.operationState === "conflict" || (modelController.operationState === "error" && windowController.captureState !== "capture_armed")
            }

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: modelController.operationMessage + " (press key combination again or Esc to cancel)"
                color: Theme.error
                font.family: parent.font.family
                font.pixelSize: parent.font.pixelSize
                font.bold: true
                visible: modelController.operationState === "error" && windowController.captureState === "capture_armed"
            }

            onTextChanged: {
                if (!windowController.isRecording && modelController.operationState !== "idle") {
                    modelController.operationState = "idle"
                    modelController.operationMessage = ""
                    windowController.recordingItem = null
                }
                modelController.searchQuery = text
            }

            Keys.onReleased: function(event) {
                if (windowController.handleActivationKeyRelease(event)) {
                    return
                }
                if (windowController.isRecording) {
                    windowController.handleRecordingKeyRelease(event)
                    event.accepted = true
                }
            }

            Keys.onPressed: function(event) {
                if (windowController.isRecording) {
                    windowController.handleRecordingKeyPress(event)
                    event.accepted = true
                    return
                }

                if (modelController.operationState === "conflict" || modelController.operationState === "error" || modelController.operationState === "success") {
                    if (event.key === Qt.Key_Escape) {
                        windowController.cancelCapture()
                        event.accepted = true
                        return
                    }
                }

                if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)) {
                    windowController.cycleTopLevelView(true)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                    windowController.cycleTopLevelView(false)
                    event.accepted = true
                    return
                }

                if (event.key === Qt.Key_Down) {
                    windowController.focusList()
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    event.accepted = true
                    if (!windowController.claimActivationKey(event)) {
                        return
                    }
                    console.info("[EVENT] keybindings.input.enter target=searchInput activeView=" + modelController.activeView)
                    windowController.activateSelected("keyboard")
                    return
                }

                if (windowController.handleComponentKey(event, "text_input")) {
                    return
                }
            }
        }
    }

    // View selector tabs. A click is accepted before changing the model so
    // the transition cannot leak into another sibling surface.
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: KeybindingsConfig.headerHeight
        Layout.leftMargin: Theme.spacingXl
        Layout.rightMargin: Theme.spacingXl
        Layout.bottomMargin: Theme.spacingSm
        spacing: KeybindingsConfig.headerSpacing

        Rectangle {
            Layout.preferredHeight: KeybindingsConfig.tabHeight
            Layout.preferredWidth: boundText.implicitWidth + KeybindingsConfig.tabPaddingHorizontal * 2
            radius: KeybindingsConfig.tabBorderRadius
            color: modelController.activeView === "bound" ? Theme.selection : "transparent"
            border.color: "transparent"
            border.width: 0

            Behavior on color { ColorAnimation { duration: Theme.keybindingsDurationFast } }

            Text {
                id: boundText
                anchors.centerIn: parent
                text: "Bound (" + modelController.boundCount + ")"
                color: modelController.activeView === "bound" ? Theme.accent : Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: modelController.activeView === "bound" ? Theme.fontWeightMedium : Theme.fontWeightNormal
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                    mouse.accepted = true
                    modelController.switchView("bound")
                    headerRoot.focusSearch()
                }
            }
        }

        Rectangle {
            Layout.preferredHeight: KeybindingsConfig.tabHeight
            Layout.preferredWidth: unboundText.implicitWidth + KeybindingsConfig.tabPaddingHorizontal * 2
            radius: KeybindingsConfig.tabBorderRadius
            color: modelController.activeView === "unbound" ? Theme.selection : "transparent"
            border.color: "transparent"
            border.width: 0

            Behavior on color { ColorAnimation { duration: Theme.keybindingsDurationFast } }

            Text {
                id: unboundText
                anchors.centerIn: parent
                text: "Unbound (" + modelController.unboundCount + ")"
                color: modelController.activeView === "unbound" ? Theme.accent : Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: modelController.activeView === "unbound" ? Theme.fontWeightMedium : Theme.fontWeightNormal
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                    mouse.accepted = true
                    modelController.switchView("unbound")
                    headerRoot.focusSearch()
                }
            }
        }

        Item { Layout.fillWidth: true }

        Rectangle {
            Layout.preferredHeight: KeybindingsConfig.tabHeight
            Layout.preferredWidth: addActionText.implicitWidth + KeybindingsConfig.tabPaddingHorizontal * 2
            radius: KeybindingsConfig.tabBorderRadius
            color: modelController.activeView.indexOf("add_") === 0 ? Theme.selection : "transparent"
            border.color: "transparent"
            border.width: 0

            Behavior on color { ColorAnimation { duration: Theme.keybindingsDurationFast } }

            Text {
                id: addActionText
                anchors.centerIn: parent
                text: modelController.activeView.indexOf("add_") === 0 ? "← Back to Shortcuts" : "+ Add Action"
                color: modelController.activeView.indexOf("add_") === 0 ? Theme.gold : Theme.foam
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: Theme.fontWeightMedium
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                    mouse.accepted = true
                    if (modelController.activeView.indexOf("add_") === 0) {
                        windowController.goBack()
                    } else {
                        windowController.openAddAction()
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: KeybindingsConfig.cogHitTargetWidth
            Layout.preferredHeight: KeybindingsConfig.cogHitTargetHeight
            radius: KeybindingsConfig.tabBorderRadius
            color: modelController.activeView === "settings" || cogHover.hovered ? Theme.selection : "transparent"
            border.color: "transparent"
            border.width: 0

            Behavior on color { ColorAnimation { duration: Theme.keybindingsDurationFast } }

            HoverHandler { id: cogHover }

            Text {
                anchors.centerIn: parent
                text: "⚙"
                color: modelController.activeView === "settings" ? Theme.accent : Theme.textSecondary
                font.pixelSize: KeybindingsConfig.cogIconSize
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                    mouse.accepted = true
                    if (modelController.activeView === "settings") {
                        windowController.goBack()
                    } else {
                        modelController.switchView("settings")
                        windowController.focusSettings()
                    }
                }
            }
        }
    }
}
