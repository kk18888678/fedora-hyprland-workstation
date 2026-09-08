import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../../theme"

// The selection surface is deliberately separate from the bar-owned menu.
// It is a short-lived compositor overlay used only while the user drags a
// capture rectangle; it never owns bar popout placement.
PanelWindow {
    id: root

    property var controller: null
    property real selectionStartX: 0
    property real selectionStartY: 0
    property real selectionEndX: 0
    property real selectionEndY: 0
    property bool selectionDragging: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aurelia-screenshot-selection"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    implicitWidth: 0
    implicitHeight: 0
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.controller !== null && root.controller.captureStage === "region-selecting"

    function resetSelection() {
        selectionStartX = 0
        selectionStartY = 0
        selectionEndX = 0
        selectionEndY = 0
        selectionDragging = false
    }

    function finishSelection() {
        var left = Math.floor(Math.min(selectionStartX, selectionEndX))
        var top = Math.floor(Math.min(selectionStartY, selectionEndY))
        var width = Math.floor(Math.abs(selectionEndX - selectionStartX))
        var height = Math.floor(Math.abs(selectionEndY - selectionStartY))
        if (width < 4 || height < 4) {
            if (root.controller) root.controller.regionSelectionTooSmall()
            return
        }

        var originX = 0
        var originY = 0
        if (root.screen) {
            var screenX = Number(root.screen.virtualX)
            var screenY = Number(root.screen.virtualY)
            if (Number.isFinite(screenX)) originX = Math.floor(screenX)
            if (Number.isFinite(screenY)) originY = Math.floor(screenY)
        }
        var geometry = String(originX + left) + "," + String(originY + top) + " " + String(width) + "x" + String(height)
        console.info("[SCREENSHOT] native region geometry=" + geometry)
        if (root.controller) root.controller.regionSelectionFinished(geometry)
    }

    onVisibleChanged: {
        if (visible) {
            resetSelection()
            Qt.callLater(function() { selectionKeyboardScope.forceActiveFocus() })
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#33ffffff"

        Text {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: Theme.spacingXl
            text: "Drag to select a region"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.weight: Theme.fontWeightMedium
        }

        Rectangle {
            x: Math.min(root.selectionStartX, root.selectionEndX)
            y: Math.min(root.selectionStartY, root.selectionEndY)
            width: Math.abs(root.selectionEndX - root.selectionStartX)
            height: Math.abs(root.selectionEndY - root.selectionStartY)
            color: "#22ffffff"
            border.color: "#ffffffff"
            border.width: Theme.borderWidthFocus
            visible: root.selectionDragging
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.CrossCursor

            onPressed: function(mouse) {
                mouse.accepted = true
                root.selectionStartX = mouse.x
                root.selectionStartY = mouse.y
                root.selectionEndX = mouse.x
                root.selectionEndY = mouse.y
                root.selectionDragging = true
            }

            onPositionChanged: function(mouse) {
                if (!root.selectionDragging) return
                mouse.accepted = true
                root.selectionEndX = mouse.x
                root.selectionEndY = mouse.y
            }

            onReleased: function(mouse) {
                mouse.accepted = true
                if (!root.selectionDragging) return
                root.selectionEndX = mouse.x
                root.selectionEndY = mouse.y
                root.selectionDragging = false
                root.finishSelection()
            }
        }
    }

    FocusScope {
        id: selectionKeyboardScope
        anchors.fill: parent
        z: -1
        focus: root.visible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape && root.controller) {
                root.controller.cancelRegionSelection()
                event.accepted = true
            }
        }
    }
}
