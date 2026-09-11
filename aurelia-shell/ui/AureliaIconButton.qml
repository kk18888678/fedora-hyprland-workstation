import QtQuick
import "../theme"

// Compact icon-only action for dense Aurelia surfaces. Labels remain
// discoverable through the anchored tooltip, while the hit target stays large
// enough for pointer use and the glyph remains theme-aware.
Item {
    id: root

    property string icon: ""
    property string tooltip: ""
    property bool active: false
    property bool destructive: false

    signal triggered()

    implicitWidth: Theme.scaleGeometry(22)
    implicitHeight: Theme.scaleGeometry(22)

    HoverHandler { id: iconHover }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: root.active || iconHover.hovered ? Theme.controls.hoverFill : "transparent"
        border.color: root.destructive && iconHover.hovered
            ? Theme.error
            : (root.active || iconHover.hovered ? Theme.controls.hoverBorder : "transparent")
        border.width: root.active || iconHover.hovered ? Theme.borderWidthDefault : 0
        opacity: root.enabled ? 1.0 : 0.45

        AureliaIcon {
            anchors.centerIn: parent
            width: Theme.bar.iconCanvas
            height: Theme.bar.iconCanvas
            name: root.icon
            iconSize: Theme.bar.iconCanvas
            tint: root.destructive && iconHover.hovered
                ? Theme.error
                : (root.active ? Theme.controls.selectedColor : Theme.textSecondary)
        }

        AureliaToolTip {
            triggerItem: root
            hovered: iconHover.hovered
            text: root.tooltip
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                mouse.accepted = true
                root.triggered()
            }
        }
    }
}
