import QtQuick
import QtQuick.Controls
import "../../../theme"

// Themed text input: inset surface fill with focus border accent.
TextField {
    id: control

    property int controlHeight: 32

    

    implicitWidth: 180
    implicitHeight: controlHeight

    color: Theme.controls.normalColor
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSm
    selectByMouse: true

    background: Rectangle {
        implicitWidth: control.implicitWidth
        implicitHeight: control.implicitHeight
        radius: Theme.radiusMd
        color: control.activeFocus ? Theme.controls.focusFill : Theme.surfaceElevated
        border.width: 1
        border.color: control.activeFocus ? Theme.controls.focusBorder : Theme.controls.normalBorder
    }
}
