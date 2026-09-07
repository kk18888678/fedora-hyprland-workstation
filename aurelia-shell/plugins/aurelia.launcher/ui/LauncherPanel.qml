import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../../theme"
import "."

PanelWindow {
    id: panelRoot

    property string backendBin: ""
    property var processEnvironment: ({})
    property var anchorWindow: null

    readonly property int calculatedCardHeight: {
        // Keep the viewport stable while the query filters results. The list
        // scrolls inside this fixed card instead of resizing on every keystroke.
        return Math.max(300, Math.min(height - Theme.spacingXxl * 2, 420))
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aurelia-launcher"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false

    LauncherModel {
        id: launcherModel
        backendBin: panelRoot.backendBin
        processEnvironment: panelRoot.processEnvironment
        onLaunchStarted: panelRoot.close()
    }

    function open(payloadJson) {
        if (anchorWindow && typeof anchorWindow.requestPopout === "function") anchorWindow.requestPopout(panelRoot, "aurelia.launcher")
        visible = true
        launcherModel.query = ""
        launcherModel.selectedIndex = 0
        launcherModel.reload()
        Qt.callLater(function() { searchInput.forceActiveFocus() })
    }

    function close() {
        visible = false
        searchInput.text = ""
        if (anchorWindow && typeof anchorWindow.releasePopout === "function") anchorWindow.releasePopout(panelRoot)
    }

    function closeForPopoutSwitch() { close() }

    function iconSource(iconName) {
        var name = String(iconName || "")
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
        width: Math.min(parent.width - Theme.spacingXxl * 2, 532)
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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingXl
            spacing: Theme.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "Applications"
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
                z: 2
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                text: launcherModel.query
                focus: true
                activeFocusOnTab: true
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
                onTextChanged: if (launcherModel.query !== text) launcherModel.query = text

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
                    text: "Search applications"
                    color: Theme.inputPlaceholder
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    visible: searchInput.text.length === 0 && !searchInput.activeFocus
                }

                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Down) {
                        launcherModel.moveSelection(1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Up) {
                        launcherModel.moveSelection(-1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        launcherModel.launchSelected()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                        panelRoot.close()
                        event.accepted = true
                    }
                }
            }

            ListView {
                id: appList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.spacingXs
                model: launcherModel.filteredApplications
                currentIndex: launcherModel.selectedIndex

                delegate: Rectangle {
                    required property var modelData
                    width: appList.width
                    height: 54
                    radius: Theme.radiusMd
                    color: index === launcherModel.selectedIndex ? Theme.selection : Theme.surface

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingMd
                        anchors.rightMargin: Theme.spacingMd
                        spacing: Theme.spacingMd

                        Image {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            source: panelRoot.iconSource(modelData.icon)
                            sourceSize: Qt.size(28, 28)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            asynchronous: true
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name || modelData.desktop_id
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeMd
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.generic_name || modelData.comment || modelData.desktop_id
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: function(mouse) {
                            mouse.accepted = true
                            launcherModel.selectedIndex = index
                            launcherModel.launchSelected()
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: launcherModel.loading ? "Loading applications…" : (launcherModel.errorMessage || "No applications found")
                    color: launcherModel.errorMessage ? Theme.error : Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    visible: appList.count === 0
                }
            }
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                panelRoot.close()
                event.accepted = true
            }
        }
    }
}
