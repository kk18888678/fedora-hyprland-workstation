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

        Text {
            Layout.fillWidth: true
            text: descriptor.title || ""
            color: Theme.text
            font.family: Theme.fontFamilyResolved
            font.pixelSize: Theme.fontSizeMd
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            text: descriptor.description || ""
            color: Theme.textSecondary
            font.family: Theme.fontFamilyProse
            font.pixelSize: Theme.fontSizeXs
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            visible: text !== ""
        }
    }

    // Value + slider grouped on the same horizontal line, right-aligned.
    RowLayout {
        Layout.alignment: Qt.AlignVCenter
        spacing: Theme.spacingMd

        Text {
            text: {
                var raw = slider.value
                var unit = descriptor.unit || ""
                if (unit === "%") {
                    return Math.round(raw * 100) + "%"
                }
                if (unit === "pct") {
                    return Math.round(raw) + "%"
                }
                if (Math.round(raw) === raw) return String(Math.round(raw)) + (unit ? " " + unit : "")
                return String(Number(raw).toFixed(2)) + (unit ? " " + unit : "")
            }
            color: Theme.accent
            font.family: Theme.fontFamilyResolved
            font.pixelSize: Theme.fontSizeSm
            Layout.preferredWidth: 64
            horizontalAlignment: Text.AlignRight
        }

        SliderControl {
            id: slider
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 220
            Layout.maximumWidth: 280
            Layout.rightMargin: Theme.spacingXs
            from: root.minValue
            to: root.maxValue
            stepSize: root.stepValue
            value: root.effective

            onMoved: debounceTimer.restart()
        }
    }

    Timer {
        id: debounceTimer
        interval: 350
        repeat: false
        onTriggered: root.changed(slider.value)
    }
}
