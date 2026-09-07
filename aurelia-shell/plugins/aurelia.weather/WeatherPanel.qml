import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "../../theme"

PanelWindow {
    id: panelRoot

    property var weatherWidget: null
    property int barSize: 26

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aurelia-weather"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    implicitWidth: 0
    implicitHeight: 0
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false

    readonly property bool barAtBottom: weatherWidget && weatherWidget.bar && weatherWidget.bar.position === "bottom"
    readonly property int barTopClearance: weatherWidget && weatherWidget.bar && weatherWidget.bar.surfaceTop !== undefined ? weatherWidget.bar.surfaceTop + panelRoot.barSize : panelRoot.barSize
    readonly property int barBottomClearance: weatherWidget && weatherWidget.bar && weatherWidget.bar.surfaceBottom !== undefined ? weatherWidget.bar.surfaceBottom + panelRoot.barSize : panelRoot.barSize

    function open() {
        if (weatherWidget && weatherWidget.bar && typeof weatherWidget.bar.refreshSurfaceGeometry === "function") weatherWidget.bar.refreshSurfaceGeometry()
        if (weatherWidget && weatherWidget.bar && typeof weatherWidget.bar.requestPopout === "function") weatherWidget.bar.requestPopout(panelRoot)
        visible = true
    }
    function close() {
        visible = false
        if (weatherWidget && weatherWidget.bar && typeof weatherWidget.bar.releasePopout === "function") weatherWidget.bar.releasePopout(panelRoot)
    }
    function closeForPopoutSwitch() { close() }

    MouseArea {
        anchors.fill: parent
        z: 0
        onClicked: function(mouse) { mouse.accepted = true; panelRoot.close() }
    }

    Rectangle {
        width: 420
        height: 360
        anchors.right: parent.right
        anchors.top: barAtBottom ? undefined : parent.top
        anchors.bottom: barAtBottom ? parent.bottom : undefined
        anchors.topMargin: barAtBottom ? 0 : panelRoot.barTopClearance + Theme.spacingLg
        anchors.bottomMargin: barAtBottom ? panelRoot.barBottomClearance + Theme.spacingLg : 0
        anchors.rightMargin: Theme.spacingLg
        z: 1
        radius: Theme.radiusLg
        color: Theme.bgBase
        border.color: Theme.border
        border.width: Theme.borderWidthDefault
        focus: panelRoot.visible

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) { mouse.accepted = true }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingXl
            spacing: Theme.spacingMd

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
                Text {
                    text: "ESC"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
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

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                panelRoot.close()
                event.accepted = true
            }
        }
    }
}
