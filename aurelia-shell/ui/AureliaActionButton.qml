import QtQuick
import QtQuick.Layouts
import "../theme"

// Small shared action primitive for Aurelia popups. It encodes the design
// language used by the Screenshot popup: restrained radius, one semantic
// accent, clear hover state, and compact two-line hierarchy.
Rectangle {
    id: root

    property string label: ""
    property string detail: ""
    property string icon: ""
    property bool primary: false
    property bool compact: false
    property bool centerLabel: false

    signal triggered()

    implicitWidth: compact ? 92 : 120
    implicitHeight: compact ? 36 : 54
    radius: Theme.radiusMd
    color: root.primary
        ? (actionHover.hovered ? Theme.accentAlt : Theme.accent)
        : (actionHover.hovered ? Theme.controls.hoverFill : Theme.controls.normalFill)
    border.color: root.primary
        ? Theme.accent
        : (actionHover.hovered ? Theme.controls.hoverBorder : Theme.controls.normalBorder)
    border.width: Theme.borderWidthDefault
    opacity: root.enabled ? 1.0 : 0.5

    HoverHandler { id: actionHover }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingSm
        anchors.rightMargin: Theme.spacingSm
        spacing: Theme.spacingXs

        AureliaIcon {
            Layout.preferredWidth: root.compact ? 16 : 18
            Layout.preferredHeight: root.compact ? 16 : 18
            name: root.icon
            iconSize: root.compact ? 16 : 18
            tint: root.primary ? Theme.bgBase : Theme.text
            visible: root.icon !== ""
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: root.label
                color: root.primary ? Theme.bgBase : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: root.compact ? Theme.fontSizeXs : Theme.fontSizeSm
                font.weight: Theme.fontWeightMedium
                horizontalAlignment: root.centerLabel ? Text.AlignHCenter : Text.AlignLeft
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.detail
                color: root.primary ? Theme.bgBase : Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                horizontalAlignment: root.centerLabel ? Text.AlignHCenter : Text.AlignLeft
                elide: Text.ElideRight
                visible: root.detail !== ""
            }
        }
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
