import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "."
import "../../theme"

// The custom executable form owns only its form state, validation hand-off,
// and external chooser lifecycle. The Window controller remains responsible
// for navigation and capture ownership.
Item {
    id: formRoot

    required property var modelController
    required property var windowController
    property string internalFormError: ""

    visible: modelController.activeView === "add_exec"

    function focusFirstField() {
        execNameInput.forceActiveFocus()
    }

    function stableActionSuffix(value): string {
        var hash = 7
        for (var i = 0; i < value.length; i++) {
            hash = (hash * 31 + value.charCodeAt(i)) % 2147483647
        }
        return Math.abs(hash).toString(16)
    }

    function submitExecForm() {
        var name = execNameInput.text.trim()
        var path = execPathInput.text.trim()
        var args = execArgsInput.text.trim()

        if (!name) {
            formRoot.internalFormError = "Error: Action Name cannot be empty."
            execNameInput.forceActiveFocus()
            return
        }
        if (!path) {
            formRoot.internalFormError = "Error: Executable Path cannot be empty."
            execPathInput.forceActiveFocus()
            return
        }

        var idPart = name.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "")
        if (!idPart) {
            idPart = "custom_exec_" + formRoot.stableActionSuffix(name + "\n" + path + "\n" + args)
        }
        var actionId = "exec:" + idPart

        var argv = []
        if (args) {
            argv = args.split(/\s+/).filter(function(a) { return a.length > 0 })
        }

        formRoot.internalFormError = ""
        modelController.addExecutable(actionId, name, path, argv)
    }

    property Process browseProcess: Process {
        id: browseProcess
        command: [formRoot.modelController.backendBin, "choose-file"]
        environment: formRoot.modelController.procEnv
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
            formRoot.windowController.browseActive = false
            if (code === 0 && browseProcess.chosenPath.length > 0) {
                console.info("[LIFECYCLE] keybindings.browse.accept has_selection=true")
                execPathInput.text = browseProcess.chosenPath
                formRoot.internalFormError = ""
                execPathInput.forceActiveFocus()
            } else if (code === 1 || (code === 0 && browseProcess.chosenPath.length === 0)) {
                console.info("[LIFECYCLE] keybindings.browse.cancel")
                browseButton.forceActiveFocus()
            } else {
                console.warn("[LIFECYCLE] keybindings.browse.error exit_code=" + code)
                formRoot.internalFormError = "File chooser failed: " + (browseProcess.errorMsg || "Process exited with code " + code)
                browseButton.forceActiveFocus()
            }
        }
    }

    function triggerBrowse() {
        if (windowController.isRecording || windowController.captureState !== "idle" || modelController.operationState === "capturing" || modelController.operationState === "conflict") {
            console.warn("[LIFECYCLE] keybindings.browse.rejected reason=capture_active")
            return
        }
        if (browseProcess.running) {
            console.warn("[LIFECYCLE] keybindings.browse.rejected reason=already_running")
            return
        }
        console.info("[LIFECYCLE] keybindings.browse.request")
        console.info("[LIFECYCLE] keybindings.browse.focus_release")
        windowController.browseActive = true
        formRoot.internalFormError = ""
        browseProcess.chosenPath = ""
        browseProcess.errorMsg = ""
        browseProcess.command = [modelController.backendBin, "choose-file"]
        browseProcess.running = true
        console.info("[LIFECYCLE] keybindings.browse.open")
    }

    onVisibleChanged: {
        if (visible) {
            if (!windowController.browseActive) {
                execNameInput.text = ""
                execPathInput.text = ""
                execArgsInput.text = ""
                formRoot.internalFormError = ""
            }
            execPathInput.showSuggestions = false
            execPathInput.suggestionIndex = -1
            formRoot.focusFirstField()
        } else {
            execPathInput.showSuggestions = false
            execPathInput.suggestionIndex = -1
            windowController.browseActive = false
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 560)
        spacing: Theme.spacingMd

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            Text {
                text: "Add Custom Executable / Script"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.weight: Theme.fontWeightBold
                color: Theme.accent
                Layout.fillWidth: true
            }

            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: backExecLabel.implicitWidth + Theme.spacingMd * 2
                radius: Theme.radiusSm
                color: backExecHover.hovered ? Theme.selection : "transparent"

                HoverHandler { id: backExecHover }

                Text {
                    id: backExecLabel
                    anchors.centerIn: parent
                    text: "← Back"
                    color: Theme.gold
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
                        windowController.goBack()
                    }
                }
            }
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
                        if (event.isAutoRepeat === true) {
                            event.accepted = true
                            return
                        }
                        if (windowController.isReturnOrEnter(event)) {
                            event.accepted = true
                            if (!windowController.claimActivationKey(event)) return
                        }
                        if (windowController.eventMatchesShortcut(event, Theme.shortcutBack)) {
                            windowController.goBack()
                            event.accepted = true
                            return
                        }
                        if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                            execPathInput.forceActiveFocus()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            formRoot.submitExecForm()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            windowController.goBack()
                            event.accepted = true
                        }
                    }
                    Keys.onReleased: function(event) { windowController.handleActivationKeyRelease(event) }
                }
            }
        }

        // Field 2: Executable Path and bounded completion chooser
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
                        property var suggestions: formRoot.modelController.pathCompletions

                        function acceptSuggestion(val) {
                            if (!val) return
                            execPathInput.text = val
                            execPathInput.cursorPosition = val.length
                            if (val.endsWith("/")) {
                                execPathInput.suggestionIndex = -1
                                formRoot.modelController.fetchPathCompletions(val)
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
                                formRoot.modelController.fetchPathCompletions(text)
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
                            if (event.isAutoRepeat === true) {
                                event.accepted = true
                                return
                            }
                            if (windowController.isReturnOrEnter(event)) {
                                event.accepted = true
                                if (!windowController.claimActivationKey(event)) return
                            }
                            if (windowController.eventMatchesShortcut(event, Theme.shortcutBack)) {
                                windowController.goBack()
                                event.accepted = true
                                return
                            }

                            var hasSuggestions = execPathInput.showSuggestions && execPathInput.suggestions && execPathInput.suggestions.length > 0
                            if (hasSuggestions && event.key === Qt.Key_Down) {
                                execPathInput.suggestionIndex = execPathInput.suggestionIndex < execPathInput.suggestions.length - 1 ? execPathInput.suggestionIndex + 1 : 0
                                event.accepted = true
                            } else if (hasSuggestions && event.key === Qt.Key_Up) {
                                execPathInput.suggestionIndex = execPathInput.suggestionIndex > 0 ? execPathInput.suggestionIndex - 1 : -1
                                event.accepted = true
                            } else if (hasSuggestions && event.key === Qt.Key_Tab) {
                                var targetVal = ""
                                if (execPathInput.suggestionIndex >= 0 && execPathInput.suggestionIndex < execPathInput.suggestions.length) {
                                    targetVal = execPathInput.suggestions[execPathInput.suggestionIndex]
                                } else if (execPathInput.suggestions.length > 0) {
                                    targetVal = execPathInput.suggestions[0]
                                }
                                if (targetVal !== "") execPathInput.acceptSuggestion(targetVal)
                                event.accepted = true
                            } else if (hasSuggestions && execPathInput.suggestionIndex >= 0 && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                execPathInput.acceptSuggestion(execPathInput.suggestions[execPathInput.suggestionIndex])
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
                                formRoot.submitExecForm()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Escape) {
                                windowController.goBack()
                                event.accepted = true
                            }
                        }
                        Keys.onReleased: function(event) { windowController.handleActivationKeyRelease(event) }

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
                                    color: execPathInput.suggestionIndex === index ? Theme.selection : "transparent"

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
                                            color: execPathInput.suggestionIndex === index ? Theme.accent : Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSm
                                            font.weight: execPathInput.suggestionIndex === index ? Theme.fontWeightMedium : Theme.fontWeightNormal
                                            Layout.fillWidth: true
                                            elide: Text.ElideMiddle
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton
                                        preventStealing: true
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: execPathInput.suggestionIndex = index
                                        onClicked: function(mouse) {
                                            mouse.accepted = true
                                            execPathInput.acceptSuggestion(modelData)
                                        }
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
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(mouse) {
                            mouse.accepted = true
                            formRoot.triggerBrowse()
                        }
                    }

                    Keys.onPressed: function(event) {
                        if (event.isAutoRepeat === true) {
                            event.accepted = true
                            return
                        }
                        if (windowController.isReturnOrEnter(event)) {
                            event.accepted = true
                            if (!windowController.claimActivationKey(event)) return
                        }
                        if (windowController.eventMatchesShortcut(event, Theme.shortcutBack)) {
                            windowController.goBack()
                            event.accepted = true
                            return
                        }
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            formRoot.triggerBrowse()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            windowController.goBack()
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
                    Keys.onReleased: function(event) { windowController.handleActivationKeyRelease(event) }
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
                        if (event.isAutoRepeat === true) {
                            event.accepted = true
                            return
                        }
                        if (windowController.isReturnOrEnter(event)) {
                            event.accepted = true
                            if (!windowController.claimActivationKey(event)) return
                        }
                        if (windowController.eventMatchesShortcut(event, Theme.shortcutBack)) {
                            windowController.goBack()
                            event.accepted = true
                            return
                        }
                        if (event.key === Qt.Key_Up) {
                            execPathInput.forceActiveFocus()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            formRoot.submitExecForm()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            windowController.goBack()
                            event.accepted = true
                        }
                    }
                    Keys.onReleased: function(event) { windowController.handleActivationKeyRelease(event) }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            color: Theme.error
            font.bold: true
            wrapMode: Text.Wrap
            visible: text !== ""
            text: formRoot.internalFormError !== "" ? formRoot.internalFormError : ((modelController.operationState === "error" && modelController.activeView === "add_exec") ? modelController.operationMessage : "")
        }

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
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        mouse.accepted = true
                        formRoot.submitExecForm()
                    }
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
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        mouse.accepted = true
                        windowController.goBack()
                    }
                }
            }
        }
    }
}
