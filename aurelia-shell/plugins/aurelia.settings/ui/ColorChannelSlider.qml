import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"

// One labeled channel slider for the color picker (R/G/B/A). The track shows
// the live gradient for that channel so the effect of each step is visible.
// Presentation-only: reports the new 0..255 value through `moved`.
RowLayout {
    id: root

    property string label: ""
    property int channelValue: 0
    property color fromColor: "#000000"
    property color toColor: "#ffffff"

    signal moved(int value)

    Layout.fillWidth: true
    spacing: Theme.spacingSm

    Text {
        text: root.label
        color: Theme.textSecondary
        font.family: Theme.fontFamilyResolved
        font.pixelSize: Theme.fontSizeSm
        Layout.preferredWidth: 16
    }

    Slider {
        id: slider
        Layout.fillWidth: true
        from: 0
        to: 255
        stepSize: 1
        onMoved: root.moved(Math.round(value))

        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            height: 10
            radius: Math.round(height / 2)
            border.width: 1
            border.color: Theme.controls.normalBorder

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.fromColor }
                GradientStop { position: 1.0; color: root.toColor }
            }
        }

        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            implicitWidth: 16
            implicitHeight: 16
            radius: Math.round(height / 2)
            color: Theme.text
            border.width: 1
            border.color: Theme.controls.normalBorder
        }
    }

    Text {
        text: String(root.channelValue)
        color: Theme.text
        font.family: Theme.fontFamilyResolved
        font.pixelSize: Theme.fontSizeXs
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: 28
    }

    // Keep the visual slider in sync with external changes (palette clicks)
    // without a two-way binding fighting the drag interaction.
    onChannelValueChanged: slider.value = channelValue
    Component.onCompleted: slider.value = channelValue
}
