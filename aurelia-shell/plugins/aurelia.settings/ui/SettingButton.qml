import QtQuick
import QtQuick.Layouts
import "../../../theme"

// Themed action button (used by action rows and the window header close).
Rectangle {
    id: root

    property string label: ""
    property bool primary: false
    property bool compact: false
    property bool enabled: true

    signal clicked()

    implicitWidth: root.compact ? 64 : (root.label.length > 0 ? root.label.length * 8 + 28 : 120)
    implicitHeight: root.compact ? 30 : 36
    radius: Theme.radiusMd
    opacity: root.enabled ? 1.0 : 0.5
    color: !root.enabled
        ? Theme.surface
        : (root.primary
            ? (btnHover.hovered ? Theme.accentAlt : Theme.accent)
            : (btnHover.hovered ? Theme.controls.hoverFill : Theme.surface))
    border.width: Theme.borderWidthDefault
    border.color: root.primary
        ? Theme.accent
        : (btnHover.hovered ? Theme.controls.hoverBorder : Theme.controls.normalBorder)

    HoverHandler { id: btnHover; enabled: root.enabled }

    Text {
        anchors.centerIn: parent
        text: root.label
        color: root.primary ? Theme.bgBase : Theme.text
        font.family: Theme.fontFamilyResolved
        font.pixelSize: root.compact ? Theme.fontSizeSm : Theme.fontSizeSm
        font.weight: Font.DemiBold
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        onClicked: root.clicked()
    }
}
