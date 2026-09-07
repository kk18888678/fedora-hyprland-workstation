import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import "../../../ui"
import "../../../theme"

// Screenshot controls are a normal bar-owned popup. The capture selector is
// the only separate fullscreen surface and is created by ScreenshotPanel.
AureliaKeyboardPanel {
    id: popup

    property var controller: null
    property bool forceHidden: controller ? controller.menuSuppressed : false

    bar: controller ? controller.bar : null
    anchorItem: controller ? controller.anchorItem : null
    ownerId: "aurelia.screenshot"
    popupWidth: 420
    popupHeight: controller ? controller.popupHeight() : 480
    shown: controller ? controller.menuOpen && !forceHidden : false
    dismissHandler: function() { popup.close() }

    function close() {
        if (controller && typeof controller.close === "function") controller.close()
        else shown = false
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingMd
        focus: popup.shown

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: popup.controller && popup.controller.captureStage === "window-list"
                    ? "Select window"
                    : (popup.controller && popup.controller.captureStage === "region-ready" ? "Region selected" : "Screenshots")
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.weight: Theme.fontWeightBold
            }
        }

        Text {
            Layout.fillWidth: true
            text: popup.controller && popup.controller.captureStage === "window-list"
                ? "Choose an open application window to capture."
                : (popup.controller && popup.controller.captureStage === "region-ready"
                    ? "The selection is ready. Capture it using the current delay and pointer settings."
                    : "Choose a capture area. Screenshots are saved to Pictures and copied to the clipboard.")
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            wrapMode: Text.WordWrap
        }

        GridLayout {
            visible: popup.controller && popup.controller.captureStage === "menu"
            Layout.fillWidth: true
            columns: 2
            rowSpacing: Theme.spacingSm
            columnSpacing: Theme.spacingSm

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                radius: Theme.radiusMd
                color: screenHover.hovered ? Theme.selection : Theme.surface
                Text { anchors.centerIn: parent; text: "Screen"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                HoverHandler { id: screenHover }
                MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true; popup.controller.capture("full", 0, "") } }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                radius: Theme.radiusMd
                color: windowHover.hovered ? Theme.selection : Theme.surface
                Text { anchors.centerIn: parent; text: "Window"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                HoverHandler { id: windowHover }
                MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true; popup.controller.startWindowSelection() } }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                radius: Theme.radiusMd
                color: regionHover.hovered ? Theme.selection : Theme.surface
                Text { anchors.centerIn: parent; text: "Selection (Region)"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                HoverHandler { id: regionHover }
                MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true; popup.controller.startRegionSelection() } }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                radius: Theme.radiusMd
                color: delayHover.hovered ? Theme.selection : Theme.surface
                Text { anchors.centerIn: parent; text: "Full screen + delay"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                HoverHandler { id: delayHover }
                MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true; popup.controller.capture("full", popup.controller.delaySeconds, "") } }
            }
        }

        ListView {
            visible: popup.controller && popup.controller.captureStage === "window-list"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.spacingSm
            model: popup.controller ? popup.controller.windows : []

            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: 52
                radius: Theme.radiusMd
                color: windowItemHover.hovered ? Theme.selection : Theme.surface
                HoverHandler { id: windowItemHover }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingMd
                    anchors.rightMargin: Theme.spacingMd
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: modelData.title || modelData.class || "Window"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modelData.class || ""
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                        elide: Text.ElideRight
                    }
                }

                MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true; popup.controller.captureWindow(modelData) } }
            }
        }

        RowLayout {
            visible: popup.controller && (popup.controller.captureStage === "region-ready" || popup.controller.captureStage === "window-list")
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: popup.controller && popup.controller.captureStage === "region-ready"
                    ? "Delay and pointer settings apply on capture."
                    : "Click a window to capture it."
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
            }
            Text {
                text: "← Back"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Theme.spacingSm
                    onClicked: function(mouse) {
                        mouse.accepted = true
                        popup.controller.captureStage = "menu"
                        popup.controller.statusMessage = ""
                    }
                }
            }
        }

        RowLayout {
            visible: popup.controller && popup.controller.captureStage === "region-ready"
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: Theme.radiusMd
                color: Theme.accent
                Text { anchors.centerIn: parent; text: "Take Screenshot"; color: Theme.bgBase; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
                MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true; popup.controller.capturePendingRegion(0) } }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: Theme.radiusMd
                color: Theme.selection
                Text { anchors.centerIn: parent; text: "Take Screenshot with Delay"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
                MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true; popup.controller.capturePendingRegion(popup.controller.delaySeconds) } }
            }
        }

        RowLayout {
            visible: popup.controller && (popup.controller.captureStage === "menu" || popup.controller.captureStage === "region-ready")
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            Text { text: "Delay (seconds)"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }

            TextInput {
                id: delayInput
                Layout.preferredWidth: 62
                Layout.preferredHeight: 32
                text: popup.controller ? String(popup.controller.delaySeconds) : "3"
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                selectByMouse: true
                validator: IntValidator { bottom: 0; top: 30 }

                Rectangle {
                    anchors.fill: parent
                    z: -1
                    radius: Theme.radiusSm
                    color: Theme.surface
                    border.color: delayInput.activeFocus ? Theme.borderActive : Theme.border
                    border.width: Theme.borderWidthDefault
                }

                onEditingFinished: {
                    var next = Number(text)
                    if (!Number.isFinite(next)) next = 3
                    if (popup.controller) popup.controller.delaySeconds = Math.max(0, Math.min(30, Math.floor(next)))
                    text = popup.controller ? String(popup.controller.delaySeconds) : "3"
                }
            }

            Item { Layout.fillWidth: true }
            Text { text: "Show pointer"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }

            Rectangle {
                Layout.preferredWidth: 54
                Layout.preferredHeight: 28
                radius: 14
                color: popup.controller && popup.controller.showPointer ? Theme.accent : Theme.surface
                border.color: popup.controller && popup.controller.showPointer ? Theme.accent : Theme.border
                border.width: Theme.borderWidthDefault

                Rectangle {
                    width: 20
                    height: 20
                    radius: 10
                    anchors.verticalCenter: parent.verticalCenter
                    x: popup.controller && popup.controller.showPointer ? parent.width - width - 4 : 4
                    color: popup.controller && popup.controller.showPointer ? Theme.bgBase : Theme.textMuted
                }

                MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true; if (popup.controller) popup.controller.showPointer = !popup.controller.showPointer } }
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
            wrapMode: Text.Wrap
            visible: text.length > 0
        }

    }
}
