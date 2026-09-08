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

    implicitWidth: 30
    implicitHeight: 30

    HoverHandler { id: iconHover }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: root.active || iconHover.hovered ? Theme.selection : "transparent"
        border.color: root.destructive && iconHover.hovered
            ? Theme.error
            : (root.active || iconHover.hovered ? Theme.borderActive : "transparent")
        border.width: root.active || iconHover.hovered ? Theme.borderWidthDefault : 0
        opacity: root.enabled ? 1.0 : 0.45

        AureliaIcon {
            anchors.centerIn: parent
            width: 17
            height: 17
            name: root.icon
            iconSize: 17
            tint: root.destructive && iconHover.hovered
                ? Theme.error
                : (root.active ? Theme.accent : Theme.textSecondary)
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
