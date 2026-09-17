import QtQuick
import QtQuick.Controls
import "../../../theme"

// Themed switch following the Aurelia design language (accent track,
// rounded knob, theme border tokens).
Switch {
    id: control

    

    indicator: Rectangle {
        implicitWidth: 42
        implicitHeight: 24
        x: control.leftPadding
        y: control.topPadding + (control.availableHeight - height) / 2
        radius: Math.round(height / 2)
        color: control.checked ? Theme.accent : Theme.surfaceElevated
        border.width: 1
        border.color: control.checked ? Theme.accent : Theme.controls.normalBorder

        Rectangle {
            x: control.checked ? parent.width - width - 3 : 3
            y: 3
            width: parent.height - 6
            height: parent.height - 6
            radius: Math.round(height / 2)
            color: control.checked ? Theme.bgBase : Theme.text
            Behavior on x {
                NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
            }
        }
    }

    // The row owns the labels; keep the default switch text invisible.
    contentItem: Text {
        text: ""
        visible: false
    }
}
