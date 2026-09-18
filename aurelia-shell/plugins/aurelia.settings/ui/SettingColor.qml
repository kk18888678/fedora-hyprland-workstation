import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "."
import "ColorUtils.js" as ColorUtils

// Color row: the current swatch opens the picker, a curated preset strip
// applies a color immediately, and a "Custom…" action opens the picker for an
// exact value. Presets share one size and vertical center so the strip reads
// as a single aligned group. Applying a value emits `changed`; the settings
// window owns the actual mutation through the bounded backend.
RowLayout {
    id: root

    property var descriptor: ({})
    property string optionId: descriptor ? String(descriptor.id || "") : ""
    property string effective: descriptor ? String(descriptor.effective || "") : ""
    property string title: descriptor ? String(descriptor.title || "Color") : "Color"
    readonly property var channels: ColorUtils.parseColor(root.effective)
    readonly property color currentColor: Qt.rgba(
        channels.r / 255, channels.g / 255, channels.b / 255, channels.a / 255)
    readonly property var presets: [
        Theme.accent, Theme.pine, Theme.gold, Theme.love,
        Theme.iris, Theme.text, Theme.surface
    ]

    signal changed(var value)
    signal pickRequested(string optionId, string value, string title)

    function presetValue(color) {
        return ColorUtils.toRgba(color.r * 255, color.g * 255, color.b * 255, 255)
    }

    function isPresetSelected(color) {
        return ColorUtils.sameRgb(channels.r, channels.g, channels.b,
            color.r * 255, color.g * 255, color.b * 255)
    }

    function openPicker() {
        root.pickRequested(root.optionId, root.effective, root.title)
    }

    width: parent ? parent.width : 0
    Layout.fillWidth: true
    spacing: Theme.spacingLg

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 2

        Text {
            Layout.fillWidth: true
            text: root.title
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMd
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            text: root.descriptor.description || ""
            color: Theme.textSecondary
            font.family: Theme.fontFamilyProse
            font.pixelSize: Theme.fontSizeXs
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            visible: text !== ""
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignVCenter
        spacing: Theme.spacingSm

        // Current color: the swatch itself is the picker affordance.
        Rectangle {
            id: currentSwatch
            Layout.alignment: Qt.AlignVCenter
            width: 30
            height: 30
            radius: Theme.radiusSm
            border.width: Theme.borderWidthDefault
            border.color: swatchHover.hovered ? Theme.controls.hoverBorder : Theme.border
            color: root.currentColor

            HoverHandler { id: swatchHover }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openPicker()
            }
        }

        // Curated presets, one consistent size, selection ring on the active
        // value.
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacingSm

            Repeater {
                model: root.presets

                Rectangle {
                    required property color modelData
                    Layout.alignment: Qt.AlignVCenter
                    width: 20
                    height: 20
                    radius: Theme.radiusSm
                    color: modelData
                    border.width: root.isPresetSelected(modelData) ? 2 : 1
                    border.color: root.isPresetSelected(modelData) ? Theme.accent : Theme.border

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.changed(root.presetValue(modelData))
                    }
                }
            }
        }

        SettingButton {
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: Theme.spacingSm
            label: "Custom…"
            onClicked: root.openPicker()
        }
    }
}
