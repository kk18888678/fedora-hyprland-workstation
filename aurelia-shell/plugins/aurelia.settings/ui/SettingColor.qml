import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "."

// Color row: current color swatch, a text field (rgba(...) or #RRGGBB[AA]),
// and a few quick presets drawn from the active theme palette. Applies on
// Enter or preset click.
RowLayout {
    id: root

    property var descriptor: ({})
    property string optionId: descriptor ? String(descriptor.id || "") : ""
    property string effective: descriptor ? String(descriptor.effective || "") : ""

    signal changed(var value)

    width: parent ? parent.width : 0
    Layout.fillWidth: true
    spacing: Theme.spacingLg

    function hexChannel(value) {
        var hex = Math.round(value * 255).toString(16)
        return hex.length === 1 ? "0" + hex : hex
    }

    function previewColor(value) {
        var text = String(value || "").trim()
        if (/^#[0-9a-fA-F]{6}$/.test(text)) return text + "ff"
        if (/^#[0-9a-fA-F]{8}$/.test(text)) return text
        var match = /^rgba\(([0-9a-fA-F]{6})([0-9a-fA-F]{2})\)$/.exec(text)
        if (match) return "#" + match[2] + match[1]
        return "#00000000"
    }

    function normalizePreset(color) {
        return "rgba(" + hexChannel(color.r) + hexChannel(color.g) + hexChannel(color.b) + "ff)"
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 2

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
            Layout.fillWidth: true
            text: descriptor.description || ""
            color: Theme.textMuted
            font.family: Theme.fontFamilyProse
            font.pixelSize: Theme.fontSizeXs
            wrapMode: Text.WordWrap
            visible: text !== ""
        }
    }

    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        width: 22
        height: 22
        radius: Theme.radiusSm
        border.width: Theme.borderWidthDefault
        border.color: Theme.border
        color: root.previewColor(root.effective)
    }

    RowLayout {
        Layout.alignment: Qt.AlignVCenter
        spacing: 6

        Repeater {
            model: [Theme.accent, Theme.pine, Theme.gold, Theme.love, Theme.iris, Theme.text, Theme.surfaceElevated]
            Rectangle {
                required property color modelData
                width: 16
                height: 16
                radius: Theme.radiusSm
                border.width: Theme.borderWidthDefault
                border.color: Theme.border
                color: modelData
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.changed(root.normalizePreset(modelData))
                }
            }
        }
    }

    TextControl {
        id: colorField
        Layout.alignment: Qt.AlignVCenter
        Layout.minimumWidth: 150
        text: root.effective
        onAccepted: root.changed(text.trim())
    }
}
