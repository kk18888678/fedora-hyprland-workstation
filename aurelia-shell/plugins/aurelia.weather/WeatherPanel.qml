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
    popupWidth: 420
    popupHeight: 360
    shown: false

    function open() {
        shown = true
    }
    function close() {
        shown = false
    }
    function closeForPopoutSwitch() { close() }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingMd
        focus: panelRoot.shown

            RowLayout {
                Layout.fillWidth: true
                IconImage {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    source: weatherWidget ? Quickshell.iconPath(weatherWidget.iconName, "weather-clear") : Quickshell.iconPath("weather-clear")
                }
                Text {
                    Layout.fillWidth: true
                    text: weatherWidget && weatherWidget.resolvedLocation !== "" ? weatherWidget.resolvedLocation : "Weather"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLg
                    font.weight: Theme.fontWeightBold
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: weatherWidget ? weatherWidget.temperatureText : "…"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXl
                    font.weight: Theme.fontWeightBold
                }
                Text {
                    text: weatherWidget ? weatherWidget.conditionText : ""
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm
                Repeater {
                    model: [
                        { label: "Feels", value: weatherWidget ? weatherWidget.feelsText : "—" },
                        { label: "Humidity", value: weatherWidget ? weatherWidget.humidityText : "—" },
                        { label: "Wind", value: weatherWidget ? weatherWidget.windText : "—" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: Theme.radiusSm
                        color: Theme.surface
                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.value; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                        }
                    }
                }
            }

            Text {
                text: "Next 3 days"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: Theme.fontWeightMedium
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.spacingXs
                Repeater {
                    model: weatherWidget ? weatherWidget.forecast : []
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusSm
                        color: Theme.surface
                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.date || ""; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }
                            IconImage {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 18
                                height: 18
                                source: weatherWidget ? Quickshell.iconPath(weatherWidget.iconFor(Number(modelData.weatherCode), true), "weather-clear") : Quickshell.iconPath("weather-clear")
                            }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(Number(modelData.max)) + "° / " + Math.round(Number(modelData.min)) + "°"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(Number(modelData.windSpeed)) + (weatherWidget && weatherWidget.units === "imperial" ? " mph" : " km/h"); color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }
                        }
                    }
                }
            }
    }
}
