import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../../ui"
import "../../../theme"

// Compact screenshot popup. The two capture actions stay visually primary;
// delay and pointer behavior remain customization controls rather than extra
// capture modes.
AureliaKeyboardPanel {
    id: popup

    property var controller: null
    property bool forceHidden: controller ? controller.menuSuppressed : false

    bar: controller ? controller.bar : null
    anchorItem: controller ? controller.anchorItem : null
    ownerId: "aurelia.screenshot"
    popupWidth: 280
    popupHeight: controller ? controller.popupHeight : 228
    shown: controller ? controller.menuOpen && !forceHidden : false
    dismissHandler: function() { popup.close() }

    function close() {
        if (controller && typeof controller.close === "function") controller.close()
        else shown = false
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingSm
        focus: popup.shown

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: "Screenshots"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.weight: Theme.fontWeightBold
            }

        }

        Text {
            Layout.fillWidth: true
            text: "Capture your screen or select a region."
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            AureliaActionButton {
                Layout.fillWidth: true
                label: "Full Screen"
                detail: "Entire display"
                icon: "view-fullscreen"
                primary: true
                onTriggered: {
                    if (popup.controller) popup.controller.capture("full", popup.controller.delaySeconds, "")
                }
            }

            AureliaActionButton {
                Layout.fillWidth: true
                label: "Selection"
                detail: "Choose region"
                icon: "edit-select"
                onTriggered: {
                    if (popup.controller) popup.controller.startRegionSelection()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.border
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXs

            Text {
                text: "Delay"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
            }

            TextInput {
                id: delayInput
                Layout.preferredWidth: 38
                Layout.preferredHeight: 28
                text: popup.controller ? String(popup.controller.delaySeconds) : "0"
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.inputText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                selectByMouse: true
                activeFocusOnTab: false
                validator: IntValidator { bottom: 0; top: 30 }

                Rectangle {
                    anchors.fill: parent
                    z: -1
                    radius: Theme.radiusSm
                    color: Theme.inputBg
                    border.color: delayInput.activeFocus ? Theme.inputBorderFocused : Theme.inputBorder
                    border.width: Theme.borderWidthDefault
                }

                onEditingFinished: {
                    var next = Number(text)
                    if (!Number.isFinite(next)) next = 0
                    if (popup.controller) popup.controller.delaySeconds = Math.max(0, Math.min(30, Math.floor(next)))
                    text = popup.controller ? String(popup.controller.delaySeconds) : "0"
                }
            }

            Text {
                text: "sec"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "Pointer"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
            }

            Rectangle {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 22
                radius: height / 2
                color: popup.controller && popup.controller.showPointer ? Theme.accent : Theme.surface
                border.color: popup.controller && popup.controller.showPointer ? Theme.accent : Theme.border
                border.width: Theme.borderWidthDefault

                Rectangle {
                    width: 16
                    height: 16
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    x: popup.controller && popup.controller.showPointer ? parent.width - width - 3 : 3
                    color: popup.controller && popup.controller.showPointer ? Theme.bgBase : Theme.textMuted
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: function(mouse) {
                        mouse.accepted = true
                        if (popup.controller) popup.controller.showPointer = !popup.controller.showPointer
                    }
                }
            }

            Text {
                text: popup.controller && popup.controller.showPointer ? "On" : "Off"
                color: popup.controller && popup.controller.showPointer ? Theme.accent : Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
            }
        }

        Text {
            Layout.fillWidth: true
            text: popup.controller ? popup.controller.statusMessage : ""
            color: popup.controller && popup.controller.statusKind === "error"
                ? Theme.error
                : (popup.controller && popup.controller.statusKind === "success" ? Theme.success : Theme.textMuted)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            wrapMode: Text.WordWrap
            visible: text.length > 0
        }
    }
}
