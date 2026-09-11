import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../../theme"
import "../../../ui"
import "."

// Raycast-style command surface. The panel owns presentation and keyboard
// routing; CommandCenterModel owns rows and delegates all external work.
PanelWindow {
    id: panelRoot

    property string backendBin: ""
    property string updatesBin: ""
    property string aboutBin: ""
    property string packagesBin: ""
    property string shellClientBin: ""
    property string shellRestartBin: ""
    property var processEnvironment: ({})
    property var appLibrary: null
    property var moduleRegistry: null
    property var anchorWindow: null

    readonly property int calculatedCardHeight: {
        var visibleRows = Math.max(1, Math.min(centerModel.results.length, 6))
        var resultHeight = centerModel.results.length > 0
            ? visibleRows * Theme.rowHeight + Math.max(0, visibleRows - 1) * Theme.spacingXs
            : Math.max(Theme.rowHeight * 2, 72)
        var hasStatus = centerModel.statusMessage.length > 0 || centerModel.errorMessage.length > 0
        var statusHeight = hasStatus ? Theme.fontSizeXs + Theme.spacingSm : 0
        var contentHeight = Theme.popupPadding * 2 + headerRow.implicitHeight
            + Theme.spacingSm + Theme.searchHeight
            + Theme.spacingSm + resultHeight + statusHeight
        var screenLimit = Math.max(220, height - Theme.spacingXxl * 2)
        return Math.min(screenLimit, Math.max(220, contentHeight))
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aurelia-command-center"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false

    CommandCenterModel {
        id: centerModel
        backendBin: panelRoot.backendBin
        updatesBin: panelRoot.updatesBin
        aboutBin: panelRoot.aboutBin
        packagesBin: panelRoot.packagesBin
        shellClientBin: panelRoot.shellClientBin
        shellRestartBin: panelRoot.shellRestartBin
        processEnvironment: panelRoot.processEnvironment
        appLibrary: panelRoot.appLibrary
        moduleRegistry: panelRoot.moduleRegistry
        onLaunchFinished: function(success, message) {
            if (success) panelRoot.close()
        }
    }

    PointerMoveGate {
        id: pointerGate
        referenceItem: card
    }

    Connections {
        target: centerModel
        function onQueryChanged() { pointerGate.reset() }
        function onActiveModuleChanged() { pointerGate.reset() }
    }

    function open(payloadJson) {
        if (anchorWindow && typeof anchorWindow.requestPopout === "function") anchorWindow.requestPopout(panelRoot, "aurelia.launcher")
        pointerGate.reset()
        centerModel.open()
        visible = true
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }

    function close() {
        centerModel.close()
        visible = false
        searchInput.focus = false
        if (anchorWindow && typeof anchorWindow.releasePopout === "function") anchorWindow.releasePopout(panelRoot)
    }

    function closeForPopoutSwitch() { close() }

    function safeIconSource(iconName) {
        var name = String(iconName || "application-x-executable")
        if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(name)) name = "application-x-executable"
        return Quickshell.iconPath(name, "application-x-executable")
    }

    function selectRowFromPointer(row, rowIndex, mouse) {
        if (pointerGate.moved(row, mouse)) centerModel.selectIndex(rowIndex)
    }

    readonly property var iconGlyphs: ({
        "applications-system": "󰀻",
        "system-run": "",
        "utilities-terminal": "",
        "system-software-update": "",
        "help-about": "",
        "system-software-install": "󰉉",
        "system-file-manager": "󰉋",
        "accessories-calculator": "",
        "view-refresh": "󰑐",
        "system-reboot": "󰜉",
        "folder": "",
        "text-x-generic": ""
    })

    function iconGlyphForRow(row) {
        if (!row) return "󰘦"
        var icon = String(row.icon || "")
        if (icon.length > 0 && !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(icon)) return icon
        if (iconGlyphs[icon]) return iconGlyphs[icon]
        if (row.kind === "file") return row.subtitle === "Folder" ? "" : ""
        if (row.kind === "action") return ""
        if (row.kind === "shell-action") return ""
        if (row.kind === "calculator") return ""
        return "󰘦"
    }

    MouseArea {
        anchors.fill: parent
        z: 0
        onClicked: function(mouse) {
            mouse.accepted = true
            panelRoot.close()
        }
    }

    Rectangle {
        id: card
        z: 1
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.spacingXxl * 2, Theme.paletteWidth)
        height: panelRoot.calculatedCardHeight
        radius: Theme.radiusMd
        color: Theme.launcher.background
        border.color: Theme.launcher.border
        border.width: Theme.borderWidthDefault

        MouseArea {
            anchors.fill: parent
            z: 0
            acceptedButtons: Qt.AllButtons
            onClicked: function(mouse) { mouse.accepted = true }
        }

        FocusScope {
            id: keyCatcher
            anchors.fill: parent
            // Keep the card's click-swallowing surface behind the interactive
            // search field and result delegates. Without an explicit z order,
            // row clicks can be consumed by the sibling MouseArea above.
            z: 1
            focus: panelRoot.visible
            Keys.priority: Keys.BeforeItem

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    panelRoot.close()
                    event.accepted = true
                    return
                }

                if (event.key === Qt.Key_Space && !searchInput.activeFocus && centerModel.activeModule === "updates") {
                    centerModel.activateSelected()
                    event.accepted = true
                    return
                }

                if (event.key === Qt.Key_Down) {
                    pointerGate.reset()
                    centerModel.moveSelection(1)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Up) {
                    pointerGate.reset()
                    centerModel.moveSelection(-1)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_PageDown) {
                    pointerGate.reset()
                    centerModel.moveSelection(6)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_PageUp) {
                    pointerGate.reset()
                    centerModel.moveSelection(-6)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter ||
                    (event.key === Qt.Key_Right && !searchInput.activeFocus)) {
                    centerModel.activateSelected()
                    event.accepted = true
                    return
                }
                if ((event.key === Qt.Key_Left || event.key === Qt.Key_Backspace) &&
                    centerModel.query === "" && centerModel.activeModule !== "") {
                    centerModel.resetModule()
                    event.accepted = true
                    return
                }

                // The first printable key is captured by the panel so opening
                // the surface never focuses the search field. After this key,
                // the real TextInput owns normal editing/cursor behavior.
                var printable = event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                var plainTextKey = event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier
                if (!searchInput.activeFocus && printable && plainTextKey) {
                    centerModel.appendQueryText(event.text)
                    searchInput.forceActiveFocus()
                    event.accepted = true
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.popupPadding
                spacing: Theme.spacingSm

                RowLayout {
                    id: headerRow
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: centerModel.activeModuleName
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                        font.weight: Theme.fontWeightBold
                    }
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.searchHeight
                    text: centerModel.query
                    focus: false
                    activeFocusOnTab: false
                    selectByMouse: true
                    leftPadding: Theme.spacingSm
                    rightPadding: Theme.spacingSm
                    topPadding: Theme.spacingXs
                    bottomPadding: Theme.spacingXs
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.inputText
                    selectionColor: Theme.inputSelection
                    selectedTextColor: Theme.inputSelectionText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    clip: true
                    cursorVisible: activeFocus && text.length > 0
                    onTextChanged: {
                        pointerGate.reset()
                        if (centerModel.query !== text) centerModel.setQuery(text)
                        if (text.length === 0 && activeFocus) {
                            focus = false
                            keyCatcher.forceActiveFocus()
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        z: -1
                        radius: Theme.radiusMd
                        color: Theme.inputBg
                        border.color: searchInput.activeFocus ? Theme.inputBorderFocused : Theme.inputBorder
                        border.width: Theme.borderWidthDefault
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingSm
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search apps, packages, actions, files, updates, or calculate"
                        color: Theme.inputPlaceholder
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        visible: searchInput.text.length === 0 && !searchInput.activeFocus
                    }
                }

                ListView {
                    id: resultList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Theme.popupRowGap
                    boundsBehavior: Flickable.StopAtBounds
                    model: centerModel.results
                    currentIndex: centerModel.selectedIndex

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0 && currentIndex < count) positionViewAtIndex(currentIndex, ListView.Contain)
                    }

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool selected: ListView.isCurrentItem
                        width: resultList.width
                        height: Theme.rowHeight
                        radius: Theme.radiusSm
                        color: selected ? Theme.launcher.selectedBackground : "transparent"
                        border.color: selected ? Theme.launcher.selectedBorder : Theme.border
                        border.width: selected ? Theme.borderWidthDefault : 0

                        Rectangle {
                            visible: selected
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingXs
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: Math.max(14, parent.height - Theme.spacingSm)
                            radius: width / 2
                            color: Theme.accent
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingSm
                            anchors.rightMargin: Theme.spacingSm
                            spacing: Theme.spacingSm

                            Text {
                                visible: modelData.kind !== "app"
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                text: panelRoot.iconGlyphForRow(modelData)
                                color: selected ? Theme.launcher.selectedText : Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeMd
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            Image {
                                visible: modelData.kind === "app"
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                source: panelRoot.appLibrary
                                    ? panelRoot.appLibrary.iconSource(modelData.appIcon)
                                    : panelRoot.safeIconSource(modelData.appIcon)
                                sourceSize: Qt.size(24, 24)
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                asynchronous: true
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.label || modelData.id
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeMd
                                    font.weight: Theme.fontWeightMedium
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.subtitle || modelData.detail || ""
                                    color: selected ? Theme.text : Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                Layout.maximumWidth: 220
                                text: modelData.detail || ""
                                color: selected ? Theme.text : Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                                elide: Text.ElideLeft
                                horizontalAlignment: Text.AlignRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            z: 1
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onEntered: panelRoot.selectRowFromPointer(parent, index, { x: mouseX, y: mouseY })
                            onPositionChanged: function(mouse) {
                                panelRoot.selectRowFromPointer(parent, index, mouse)
                            }
                            onClicked: function(mouse) {
                                mouse.accepted = true
                                centerModel.selectIndex(index)
                                centerModel.activateSelected()
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.spacingSm
                        visible: resultList.count === 0

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: centerModel.loading ? "…" : "⌕"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXl
                        }
                        Text {
                            width: resultList.width - Theme.spacingXl * 2
                            text: centerModel.errorMessage || (centerModel.loading
                                ? "Checking update sources..."
                                : (centerModel.query === "" && centerModel.activeModule === "" ? "Choose a module" : "No matching commands"))
                            color: centerModel.errorMessage ? Theme.error : Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: centerModel.statusMessage || centerModel.errorMessage
                    color: centerModel.errorMessage ? Theme.error : Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    visible: text.length > 0
                    elide: Text.ElideRight
                }
            }
        }
    }
}
