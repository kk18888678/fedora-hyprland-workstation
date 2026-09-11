import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../ui"
import "../../theme"

AureliaKeyboardPanel {
    id: panelRoot

    property var weatherWidget: null

    bar: weatherWidget ? weatherWidget.bar : null
    ownerId: "aurelia.weather"
    popupWidth: 480
    popupHeight: 286
    fitHeightToContent: true
    contentSizingItem: weatherColumn
    minPopupHeight: 220
    maxPopupHeight: 560
    shown: false

    function open() {
        if (weatherWidget && weatherWidget.weatherReady) shown = true
    }

    function close() {
        shown = false
    }

    function closeForPopoutSwitch() {
        close()
    }

    function dayLabel(date, index) {
        if (index === 0) return "Today"
        var parts = String(date || "").split("-")
        if (parts.length !== 3) return String(date || "")
        var dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var parsed = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
        return dayNames[parsed.getDay()]
    }

    function shortDate(date) {
        var parts = String(date || "").split("-")
        return parts.length === 3 ? parts[1] + "/" + parts[2] : String(date || "")
    }

    ColumnLayout {
        id: weatherColumn
        anchors.fill: parent
        spacing: Theme.spacingMd
        focus: panelRoot.shown

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 82

            RowLayout {
                anchors.fill: parent
                spacing: Theme.spacingLg

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingMd

                    Rectangle {
                        Layout.preferredWidth: 62
                        Layout.preferredHeight: 62
                        radius: Theme.radiusLg
                        color: Theme.surfaceElevated
                        border.color: Theme.borderActive
                        border.width: Theme.borderWidthDefault

                        IconImage {
                            anchors.centerIn: parent
                            width: 46
                            height: 46
                            source: weatherWidget
                                ? Quickshell.iconPath(weatherWidget.iconName, "weather-clear")
                                : Quickshell.iconPath("weather-clear")
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Text {
                            Layout.fillWidth: true
                            text: weatherWidget ? weatherWidget.temperatureText : ""
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 34
                            font.weight: Theme.fontWeightBold
                        }

                        Text {
                            Layout.fillWidth: true
                            text: weatherWidget ? weatherWidget.conditionText : ""
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            elide: Text.ElideRight
                        }
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.minimumWidth: 190
                    spacing: Theme.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Item { Layout.fillWidth: true }

                        IconImage {
                            Layout.preferredWidth: 15
                            Layout.preferredHeight: 15
                            source: Quickshell.iconPath("find-location", "mark-location")
                        }

                        Text {
                            Layout.maximumWidth: 175
                            text: weatherWidget && weatherWidget.resolvedLocation !== ""
                                ? weatherWidget.resolvedLocation
                                : "Weather"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeMd
                            font.weight: Theme.fontWeightMedium
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd

                        Repeater {
                            model: [
                                { label: "FEELS", value: weatherWidget ? weatherWidget.feelsText : "" },
                                { label: "HUMID", value: weatherWidget ? weatherWidget.humidityText : "" },
                                { label: "WIND", value: weatherWidget ? weatherWidget.windText : "" }
                            ]

                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    color: Theme.textSubtle
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                    font.letterSpacing: 0.8
                                    horizontalAlignment: Text.AlignRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.value
                                    color: Theme.textSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.border
            opacity: 0.55
        }

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "Next 3 days"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                font.weight: Theme.fontWeightMedium
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "FORECAST"
                color: Theme.textSubtle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                font.letterSpacing: 1
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Repeater {
                model: weatherWidget ? weatherWidget.forecast : []

                delegate: Item {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingSm
                        anchors.rightMargin: Theme.spacingSm
                        spacing: Theme.spacingSm

                        IconImage {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            source: weatherWidget
                                ? Quickshell.iconPath(
                                    weatherWidget.iconFor(Number(modelData.weatherCode), true),
                                    "weather-clear"
                                )
                                : Quickshell.iconPath("weather-clear")
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: panelRoot.dayLabel(modelData.date, index)
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                font.weight: Theme.fontWeightMedium
                            }

                            Text {
                                Layout.fillWidth: true
                                text: panelRoot.shortDate(modelData.date)
                                color: Theme.textSubtle
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                            }

                            RowLayout {
                                spacing: Theme.spacingXs

                                Text {
                                    text: Math.round(Number(modelData.max)) + "°"
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                }

                                Text {
                                    text: Math.round(Number(modelData.min)) + "°"
                                    color: Theme.textSubtle
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: Math.round(Number(modelData.windSpeed)) +
                                    (weatherWidget && weatherWidget.units === "imperial" ? " mph" : " km/h")
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                            }
                        }
                    }

                    Rectangle {
                        visible: index > 0
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: Theme.border
                        opacity: 0.55
                    }
                }
            }
        }
    }
}
