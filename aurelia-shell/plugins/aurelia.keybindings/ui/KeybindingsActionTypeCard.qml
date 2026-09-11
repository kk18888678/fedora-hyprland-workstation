import QtQuick
import QtQuick.Layouts
import "../../../theme"

// Large, explicit Add Action choice. Keeping this as a real component avoids
// delegate geometry depending on a Repeater's transient parent hierarchy.
Rectangle {
    id: cardRoot

    required property string kind
    required property string title
    required property string subtitle
    required property string glyph
    required property bool selected
    required property var modelController
    required property var windowController

    signal chosen()

    Layout.fillWidth: true
    Layout.preferredHeight: 80
    radius: Theme.radiusMd
    color: cardRoot.selected ? Theme.selection : Theme.bgBase
    border.width: cardRoot.selected ? Theme.borderWidthDefault : 0
    border.color: cardRoot.selected ? Theme.borderActive : Theme.border

    Behavior on color { ColorAnimation { duration: Theme.keybindingsDurationFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.keybindingsDurationFast } }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMd
        spacing: Theme.spacingMd

        Rectangle {
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            Layout.alignment: Qt.AlignTop
            radius: 17
            color: cardRoot.selected ? Theme.accent : Theme.surfaceElevated

            Text {
                anchors.centerIn: parent
                text: cardRoot.glyph
                color: cardRoot.selected ? Theme.bgBase : Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.weight: Theme.fontWeightBold
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacingXs

            Text {
                Layout.fillWidth: true
                text: cardRoot.title
                color: cardRoot.selected ? Theme.text : Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                font.weight: Theme.fontWeightBold
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: cardRoot.subtitle
                color: cardRoot.selected ? Theme.textSecondary : Theme.textSubtle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
            }
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: "›"
            color: cardRoot.selected ? Theme.accent : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 22
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: function(mouse) { mouse.accepted = true }
        onReleased: function(mouse) { mouse.accepted = true }
        onClicked: function(mouse) {
            mouse.accepted = true
            cardRoot.chosen()
        }
    }
}
