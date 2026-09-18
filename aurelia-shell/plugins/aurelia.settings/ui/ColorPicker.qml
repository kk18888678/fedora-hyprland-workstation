import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "."
import "ColorUtils.js" as ColorUtils

// Modal color picker for the Hyprland color options.
//
// Presentation-only: it parses the current value into R/G/B/A channels, offers
// a curated palette, per-channel sliders, and a hex/rgba field, then emits the
// chosen color in the canonical rgba(RRGGBBAA) form. The settings window owns
// the actual mutation through the bounded backend. The panel is declared as a
// plain item (not a Popup) so the window can center it over the whole card.
Rectangle {
    id: root

    property string title: ""
    property int channelR: 0
    property int channelG: 0
    property int channelB: 0
    property int channelA: 255

    signal accepted(string value)
    signal cancelled()

    readonly property color previewColor: Qt.rgba(
        channelR / 255, channelG / 255, channelB / 255, channelA / 255)

    readonly property var palette: [
        Theme.accent, Theme.accentAlt, Theme.pine, Theme.foam, Theme.gold,
        Theme.rose, Theme.love, Theme.iris, Theme.success, Theme.warning,
        Theme.error, Theme.text, Theme.textSecondary, Theme.textMuted, Theme.textSubtle,
        Theme.border, Theme.surface, Theme.surfaceElevated, "#ffffff", "#000000"
    ]

    width: 440
    height: content.implicitHeight + Theme.spacingLg * 2
    radius: Theme.radiusLg
    color: Theme.popups.background
    border.width: Theme.borderWidthDefault
    border.color: Theme.popups.border
    focus: true

    function currentValue() {
        return ColorUtils.toRgba(channelR, channelG, channelB, channelA)
    }

    function paletteValue(color) {
        return ColorUtils.toRgba(color.r * 255, color.g * 255, color.b * 255, 255)
    }

    function isPaletteSelected(color) {
        return ColorUtils.sameRgb(channelR, channelG, channelB,
            color.r * 255, color.g * 255, color.b * 255)
    }

    // Load a value into the editable channel state. Malformed input falls
    // back to transparent black; the caller only passes backend-validated
    // values or values this panel produced.
    function openWith(value) {
        var c = ColorUtils.parseColor(value)
        channelR = c.r
        channelG = c.g
        channelB = c.b
        channelA = c.a
        syncText()
        forceActiveFocus()
    }

    function syncText() {
        if (valueField && !valueField.activeFocus)
            valueField.text = currentValue()
    }

    onChannelRChanged: syncText()
    onChannelGChanged: syncText()
    onChannelBChanged: syncText()
    onChannelAChanged: syncText()

    Keys.onEscapePressed: function(event) {
        root.cancelled()
        event.accepted = true
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            Text {
                Layout.fillWidth: true
                text: root.title
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            SettingButton {
                compact: true
                label: "\u2715"
                onClicked: root.cancelled()
            }
        }

        // Preview + exact value
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            Rectangle {
                width: 56
                height: 56
                radius: Theme.radiusMd
                border.width: Theme.borderWidthDefault
                border.color: Theme.border
                color: root.previewColor
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "Current color"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamilyProse
                    font.pixelSize: Theme.fontSizeXs
                }

                Text {
                    text: root.currentValue()
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            text: "Palette"
            color: Theme.textSecondary
            font.family: Theme.fontFamilyProse
            font.pixelSize: Theme.fontSizeXs
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 10
            rowSpacing: Theme.spacingSm
            columnSpacing: Theme.spacingSm

            Repeater {
                model: root.palette

                Rectangle {
                    required property color modelData
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: Theme.radiusSm
                    color: modelData
                    border.width: root.isPaletteSelected(modelData) ? 2 : 1
                    border.color: root.isPaletteSelected(modelData) ? Theme.text : Theme.border

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.channelR = Math.round(modelData.r * 255)
                            root.channelG = Math.round(modelData.g * 255)
                            root.channelB = Math.round(modelData.b * 255)
                            root.syncText()
                        }
                    }
                }
            }
        }

        ColorChannelSlider {
            label: "R"
            channelValue: root.channelR
            fromColor: Qt.rgba(0, root.channelG / 255, root.channelB / 255, 1)
            toColor: Qt.rgba(1, root.channelG / 255, root.channelB / 255, 1)
            onMoved: function(value) { root.channelR = value }
        }

        ColorChannelSlider {
            label: "G"
            channelValue: root.channelG
            fromColor: Qt.rgba(root.channelR / 255, 0, root.channelB / 255, 1)
            toColor: Qt.rgba(root.channelR / 255, 1, root.channelB / 255, 1)
            onMoved: function(value) { root.channelG = value }
        }

        ColorChannelSlider {
            label: "B"
            channelValue: root.channelB
            fromColor: Qt.rgba(root.channelR / 255, root.channelG / 255, 0, 1)
            toColor: Qt.rgba(root.channelR / 255, root.channelG / 255, 1, 1)
            onMoved: function(value) { root.channelB = value }
        }

        ColorChannelSlider {
            label: "A"
            channelValue: root.channelA
            fromColor: Qt.rgba(root.channelR / 255, root.channelG / 255, root.channelB / 255, 0)
            toColor: Qt.rgba(root.channelR / 255, root.channelG / 255, root.channelB / 255, 1)
            onMoved: function(value) { root.channelA = value }
        }

        TextControl {
            id: valueField
            Layout.fillWidth: true
            placeholderText: "#RRGGBB or rgba(RRGGBBAA)"
            onAccepted: {
                if (!ColorUtils.isValid(text)) {
                    root.syncText()
                    return
                }
                var c = ColorUtils.parseColor(text)
                root.channelR = c.r
                root.channelG = c.g
                root.channelB = c.b
                root.channelA = c.a
                root.syncText()
            }
            Keys.onEscapePressed: function(event) {
                root.cancelled()
                event.accepted = true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Item { Layout.fillWidth: true }

            SettingButton {
                label: "Cancel"
                onClicked: root.cancelled()
            }

            SettingButton {
                label: "Apply"
                primary: true
                onClicked: root.accepted(root.currentValue())
            }
        }
    }
}
