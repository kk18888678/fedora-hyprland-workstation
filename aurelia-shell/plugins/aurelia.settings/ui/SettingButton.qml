import QtQuick
import QtQuick.Layouts
import "../../../theme"

// Themed action button (used by action rows and the window header close).
Rectangle {
    id: root

    property string label: ""
    property bool primary: false
    property bool compact: false

    signal clicked()

    implicitWidth: root.compact ? 64 : (root.label.length > 0 ? root.label.length * 8 + 28 : 120)
    implicitHeight: root.compact ? 30 : 36
    radius: Theme.radiusMd
    color: root.primary
        ? (btnHover.hovered ? Theme.accentAlt : Theme.accent)
        : (btnHover.hovered ? Theme.controls.hoverFill : Theme.surfaceElevated)
    border.width: Theme.borderWidthDefault
    border.color: root.primary
        ? Theme.accent
        : (btnHover.hovered ? Theme.controls.hoverBorder : Theme.controls.normalBorder)

    HoverHandler { id: btnHover }

    Text {
        anchors.centerIn: parent
        text: root.label
        color: root.primary ? Theme.bgBase : Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: root.compact ? Theme.fontSizeSm : Theme.fontSizeSm
        font.weight: Font.DemiBold
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
