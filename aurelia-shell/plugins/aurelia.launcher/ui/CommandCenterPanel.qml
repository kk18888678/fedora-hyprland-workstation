import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../../theme"
import "."

// Raycast-style command surface. The panel owns presentation and keyboard
// routing; CommandCenterModel owns rows and delegates all external work.
PanelWindow {
    id: panelRoot

    property string backendBin: ""
    property var processEnvironment: ({})
    property var appLibrary: null
    property var moduleRegistry: null
    property var anchorWindow: null

    readonly property int calculatedCardHeight: Math.max(360, Math.min(height - Theme.spacingXxl * 2, 560))

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
        processEnvironment: panelRoot.processEnvironment
        appLibrary: panelRoot.appLibrary
        moduleRegistry: panelRoot.moduleRegistry
        onLaunchFinished: function(success, message) {
            if (success) panelRoot.close()
        }
    }

    function open(payloadJson) {
        if (anchorWindow && typeof anchorWindow.requestPopout === "function") anchorWindow.requestPopout(panelRoot, "aurelia.launcher")
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
        width: Math.min(parent.width - Theme.spacingXxl * 2, 640)
        height: panelRoot.calculatedCardHeight
        radius: Theme.radiusLg
        color: Theme.bgBase
        border.color: Theme.border
        border.width: Theme.borderWidthDefault

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: function(mouse) { mouse.accepted = true }
        }

        FocusScope {
            id: keyCatcher
            anchors.fill: parent
            focus: panelRoot.visible
            Keys.priority: Keys.BeforeItem

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    if (centerModel.query !== "") centerModel.setQuery("")
                    else if (centerModel.activeModule !== "") centerModel.resetModule()
                    else panelRoot.close()
                    event.accepted = true
                    return
                }

                if (event.key === Qt.Key_Down) {
                    centerModel.moveSelection(1)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Up) {
                    centerModel.moveSelection(-1)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_PageDown) {
                    centerModel.moveSelection(6)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_PageUp) {
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
                anchors.margins: Theme.spacingXl
                spacing: Theme.spacingMd

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: centerModel.activeModuleName
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXl
                        font.weight: Theme.fontWeightBold
                    }
                    Text {
                        text: "ESC"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                    }
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    text: centerModel.query
                    focus: false
                    activeFocusOnTab: false
                    selectByMouse: true
                    leftPadding: Theme.spacingMd
                    rightPadding: Theme.spacingMd
                    topPadding: Theme.spacingXs
                    bottomPadding: Theme.spacingXs
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.inputText
                    selectionColor: Theme.inputSelection
                    selectedTextColor: Theme.inputSelectionText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    clip: true
                    onTextChanged: if (centerModel.query !== text) centerModel.setQuery(text)

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
                        anchors.leftMargin: Theme.spacingMd
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search apps, files, actions, or calculate"
                        color: Theme.inputPlaceholder
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMd
                        visible: searchInput.text.length === 0 && !searchInput.activeFocus
                    }
                }

                ListView {
                    id: resultList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Theme.spacingXs
                    boundsBehavior: Flickable.StopAtBounds
                    model: centerModel.results
                    currentIndex: centerModel.selectedIndex

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0 && currentIndex < count) positionViewAtIndex(currentIndex, ListView.Contain)
                    }

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool selected: ListView.isCurrentItem
                        width: resultList.width
                        height: 58
                        radius: Theme.radiusMd
                        color: selected ? Theme.selection : Theme.surface
                        border.color: selected ? Theme.accent : Theme.border
                        border.width: selected ? Theme.borderWidthDefault : 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingMd
                            anchors.rightMargin: Theme.spacingMd
                            spacing: Theme.spacingMd

                            Image {
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                source: modelData.kind === "app" && panelRoot.appLibrary
                                    ? panelRoot.appLibrary.iconSource(modelData.appIcon)
                                    : panelRoot.safeIconSource(modelData.icon)
                                sourceSize: Qt.size(30, 30)
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
                            hoverEnabled: true
                            onEntered: centerModel.selectIndex(index)
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
                            text: centerModel.errorMessage || (centerModel.query === "" && centerModel.activeModule === "" ? "Choose a module" : "No matching commands")
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
