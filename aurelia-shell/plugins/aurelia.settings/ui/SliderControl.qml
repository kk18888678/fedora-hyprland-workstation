import QtQuick
import QtQuick.Controls
import "../../../theme"

// Themed slider: thin accent progress groove with a round handle.
Slider {
    id: control

    

    background: Rectangle {
        x: control.leftPadding
        y: control.topPadding + control.availableHeight / 2 - 4
        width: control.availableWidth - control.rightPadding
        height: 8
        radius: Math.round(height / 2)
        color: Theme.surfaceElevated
        border.width: 1
        border.color: Theme.controls.normalBorder

        Rectangle {
            width: control.visualPosition * parent.width
            height: parent.height
            radius: Math.round(height / 2)
            color: Theme.accent
        }
    }

    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + control.availableHeight / 2 - height / 2
        implicitWidth: 20
        implicitHeight: 20
        radius: Math.round(height / 2)
        color: control.pressed ? Theme.accentAlt : Theme.text
        border.width: 1
        border.color: control.visualFocus ? Theme.controls.focusBorder : Theme.controls.normalBorder
        Behavior on x {
            NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
        }
    }
}
