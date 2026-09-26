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
    // The focus ring is a keyboard affordance, never a pointer one. By default
    // it follows Qt's active focus, which is how the tab-focusable panels keep
    // their ring. A panel that owns its own keyboard cursor (for example a
    // dashboard that moves focus itself) can bind this to that cursor so the
    // ring follows genuine keyboard navigation and can never be created or
    // moved by a mouse click.
    property bool keyboardFocus: activeFocus

    signal triggered()

    implicitWidth: Theme.scaleGeometry(22)
    implicitHeight: Theme.scaleGeometry(22)

    // Keyboard parity with the pointer path: the button joins the tab chain
    // and activates on Return/Enter/Space while focused.
    activeFocusOnTab: true

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter ||
            event.key === Qt.Key_Space) {
            if (root.enabled) root.triggered()
            event.accepted = true
        }
    }

    HoverHandler { id: iconHover }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: root.active || iconHover.hovered || root.keyboardFocus
            ? Theme.controls.hoverFill
            : "transparent"
        border.color: root.destructive && (iconHover.hovered || root.keyboardFocus)
            ? Theme.error
            : (root.keyboardFocus
                ? Theme.accent
                : (root.active || iconHover.hovered ? Theme.controls.hoverBorder : "transparent"))
        border.width: root.active || iconHover.hovered || root.keyboardFocus
            ? Theme.borderWidthDefault
            : 0
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
