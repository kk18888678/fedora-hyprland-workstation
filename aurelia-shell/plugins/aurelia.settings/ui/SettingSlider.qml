import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "."

// Slider row with a live value label and a short debounce so dragging a
// slider does not spam the backend process per pixel.
RowLayout {
    id: root

    property var descriptor: ({})
    property string optionId: descriptor ? String(descriptor.id || "") : ""
    property real effective: descriptor && descriptor.effective !== "" ? Number(descriptor.effective || 0) : 0
    property real minValue: descriptor ? Number(descriptor.min || 0) : 0
    property real maxValue: descriptor ? Number(descriptor.max || 1) : 1
    property real stepValue: descriptor && descriptor.step ? Number(descriptor.step) : 1
    property bool appliedWhileDragging: false

    signal changed(var value)

    width: parent ? parent.width : 0
    Layout.fillWidth: true
    spacing: Theme.spacingLg

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                Layout.fillWidth: true
                text: descriptor.title || ""
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                text: String(Number(slider.value).toFixed(2))
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
        }

        Text {
            Layout.fillWidth: true
            text: descriptor.description || ""
            color: Theme.textMuted
            font.family: Theme.fontFamilyProse
            font.pixelSize: Theme.fontSizeXs
            wrapMode: Text.WordWrap
            visible: text !== ""
        }
    }

    SliderControl {
        id: slider
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        Layout.minimumWidth: 180
        from: root.minValue
        to: root.maxValue
        stepSize: root.stepValue
        value: root.effective

        onMoved: debounceTimer.restart()
    }

    Timer {
        id: debounceTimer
        interval: 350
        repeat: false
        onTriggered: root.changed(slider.value)
    }
}
