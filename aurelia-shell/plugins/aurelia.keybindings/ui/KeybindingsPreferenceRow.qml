import QtQuick
import QtQuick.Layouts
import "../../../theme"

// One quiet, keyboard-addressable preference row. The settings surface owns
// behavior; this component owns only row geometry, state styling, and pointer
// activation.
Item {
    id: rowRoot

    required property string title
    required property string description
    required property string value
    required property bool selected
    required property bool editing
    required property int valueHeight
    required property int valueMinWidth

    signal activated()

    width: parent ? parent.width : 0
    implicitHeight: Math.max(valueHeight, 60)

    HoverHandler {
        id: rowHover
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: rowRoot.selected ? Theme.selection : (rowHover.hovered ? Theme.surfaceElevated : "transparent")
        border.width: rowRoot.selected || rowRoot.editing ? Theme.borderWidthDefault : 0
        border.color: rowRoot.editing ? Theme.accent : Theme.borderActive

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingLg
            anchors.rightMargin: Theme.spacingLg
            spacing: Theme.spacingLg

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: rowRoot.title
                    color: rowRoot.selected ? Theme.text : Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    font.weight: rowRoot.selected ? Theme.fontWeightMedium : Theme.fontWeightNormal
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: rowRoot.description
                    color: rowRoot.selected ? Theme.textMuted : Theme.textSubtle
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.preferredHeight: rowRoot.valueHeight
                Layout.preferredWidth: Math.max(rowRoot.valueMinWidth, valueLabel.implicitWidth + Theme.spacingMd)
                radius: Theme.radiusSm
                color: rowRoot.editing ? Theme.accent : Theme.surfaceElevated
                border.width: 0

                Text {
                    id: valueLabel
                    anchors.centerIn: parent
                    text: rowRoot.value
                    color: rowRoot.editing ? Theme.bgBase : Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Theme.fontWeightMedium
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onPressed: function(mouse) {
                mouse.accepted = true
            }
            onReleased: function(mouse) {
                mouse.accepted = true
            }
            onClicked: function(mouse) {
                mouse.accepted = true
                rowRoot.activated()
            }
        }
    }
}
