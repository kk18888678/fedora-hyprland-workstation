import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../ui"

// Weather follows Omarchy's default: automatic IP-based location through the
// backend. Users can pin a city or exact coordinates in the bar entry. GPS is
// not required; a future GeoClue adapter can be added without changing this
// widget contract.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string aureliaPath: ""
    property string moduleName: "aurelia.weather"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var barAnchorItem: null
    property string temperatureText: ""
    property string conditionText: "…"
    property string iconName: "weather-clear-wind"
    property string feelsText: ""
    property string humidityText: ""
    property string windText: ""
    property string resolvedLocation: ""
    property var forecast: []
    property bool weatherReady: false

    readonly property string backendBin: aureliaPath !== ""
        ? aureliaPath + "/bin/aurelia-weather"
        : "/usr/local/bin/aurelia-weather"
    readonly property string latitude: settingValue("latitude", Quickshell.env("AURELIA_WEATHER_LATITUDE") || "")
    readonly property string longitude: settingValue("longitude", Quickshell.env("AURELIA_WEATHER_LONGITUDE") || "")
    readonly property string location: settingValue("location", "auto")
    readonly property string units: settingValue("units", "metric") === "imperial" ? "imperial" : "metric"
    readonly property string locationLabel: settingValue("label", "Weather")
    readonly property bool hasCoordinates: validCoordinate(latitude, -90, 90) && validCoordinate(longitude, -180, 180)
    readonly property bool configured: hasCoordinates || (location !== "none" && location !== "")
    readonly property var processEnvironment: ({
        "PATH": "/usr/local/bin:/usr/bin:/bin" + (Quickshell.env("PATH") ? ":" + Quickshell.env("PATH") : ""),
        "HOME": Quickshell.env("HOME") || "",
        "XDG_RUNTIME_DIR": Quickshell.env("XDG_RUNTIME_DIR") || ""
    })

    visible: root.weatherReady
    implicitWidth: root.weatherReady ? weatherRow.implicitWidth + Theme.spacingSm * 2 : 0
    implicitHeight: bar ? bar.barSize : 26

    Loader {
        id: weatherPanelLoader
        active: true
        source: Qt.resolvedUrl("WeatherPanel.qml")
        onLoaded: root.configureWeatherPanel(item)
    }

    function configureWeatherPanel(target) {
        if (!target) return
        if ("weatherWidget" in target) target.weatherWidget = root
        if ("anchorItem" in target) target.anchorItem = root.barAnchorItem || root
    }

    function openWeatherPanel() {
        if (!root.weatherReady) return
        if (weatherPanelLoader.item && typeof weatherPanelLoader.item.open === "function") weatherPanelLoader.item.open()
    }

    function open(payloadJson) {
        if (!root.weatherReady) return "not-ready"
        openWeatherPanel()
        return "ok"
    }

    function close() {
        if (weatherPanelLoader.item && typeof weatherPanelLoader.item.close === "function") weatherPanelLoader.item.close()
        return "ok"
    }

    function toggle(payloadJson) {
        if (!root.weatherReady) return "not-ready"
        if (isVisible()) return close()
        return open(payloadJson || "{}")
    }

    function isVisible() {
        return weatherPanelLoader.item && weatherPanelLoader.item.visible === true
    }

    function settingValue(key, fallback) {
        if (settings && typeof settings[key] === "string" && settings[key] !== "") return settings[key]
        if (settings && settings[key] !== undefined && settings[key] !== null) return String(settings[key])
        return fallback
    }

    function validCoordinate(value, minimum, maximum) {
        var number = Number(value)
        return value !== "" && isFinite(number) && number >= minimum && number <= maximum
    }

    function refresh() {
        if (!root.configured || weatherProcess.running || !(root.bar && root.bar.barVisible)) return
        var command = [root.backendBin, "fetch", "--units", root.units]
        if (root.hasCoordinates) {
            command.push("--latitude", root.latitude, "--longitude", root.longitude)
        } else if (root.location === "auto") {
            command.push("--auto")
        } else {
            command.push("--location", root.location)
        }
        weatherProcess.command = command
        console.info("[WEATHER] fetch.begin mode=" + (root.hasCoordinates ? "coordinates" : root.location))
        weatherProcess.running = true
    }

    function scheduleRefresh() {
        refreshRequestTimer.restart()
    }

    Timer {
        id: refreshRequestTimer
        interval: 0
        repeat: false
        onTriggered: root.refresh()
    }

    function iconFor(code, isDay) {
        if (code === 0) return isDay ? "weather-clear-wind" : "weather-clear-wind-night"
        if (code === 1 || code === 2) return isDay ? "weather-few-clouds-wind" : "weather-few-clouds-wind-night"
        if (code === 3) return "weather-clouds"
        if (code === 45 || code === 48) return "weather-mist"
        if (code >= 51 && code <= 67) return isDay ? "weather-showers-day" : "weather-showers-night"
        if (code >= 71 && code <= 86) return isDay ? "weather-snow-day" : "weather-snow-night"
        if (code >= 95) return isDay ? "weather-storm-day" : "weather-storm-night"
        return isDay ? "weather-clear-wind" : "weather-clear-wind-night"
    }

    function descriptionFor(code) {
        if (code === 0) return "Clear"
        if (code === 1 || code === 2) return "Partly cloudy"
        if (code === 3 || code === 45 || code === 48) return "Cloudy"
        if (code >= 51 && code <= 67) return "Rain"
        if (code >= 71 && code <= 86) return "Snow"
        if (code >= 95) return "Storm"
        return "Weather"
    }

    Process {
        id: weatherProcess
        command: []
        environment: root.processEnvironment
        stdout: StdioCollector { id: weatherStdout }
        stderr: StdioCollector { id: weatherStderr }

        onExited: function(code) {
            if (code !== 0) {
                console.warn("[WEATHER] fetch_failed code=" + code + " error=" + weatherStderr.text.trim())
                if (!root.weatherReady) {
                    root.temperatureText = ""
                    root.feelsText = ""
                    root.humidityText = ""
                    root.windText = ""
                    root.resolvedLocation = ""
                    root.forecast = []
                    root.conditionText = root.configured ? "Weather unavailable" : root.locationLabel
                }
                return
            }
            try {
                var payload = JSON.parse(weatherStdout.text.trim())
                var temperature = Number(payload.temperature)
                var apparentTemperature = Number(payload.apparentTemperature)
                var humidity = Number(payload.humidity)
                var windSpeed = Number(payload.windSpeed)
                var weatherCode = Number(payload.weatherCode)
                var isDay = Number(payload.isDay) === 1
                var forecastData = payload.forecast
                if (!isFinite(temperature) || !isFinite(apparentTemperature) ||
                    !isFinite(humidity) || !isFinite(windSpeed) || !isFinite(weatherCode) ||
                    !Array.isArray(forecastData) || forecastData.length < 3) {
                    throw new Error("incomplete weather response")
                }
                for (var i = 0; i < 3; i++) {
                    var day = forecastData[i]
                    if (!day || String(day.date || "") === "" ||
                        !isFinite(Number(day.weatherCode)) || !isFinite(Number(day.max)) ||
                        !isFinite(Number(day.min)) || !isFinite(Number(day.windSpeed))) {
                        throw new Error("incomplete forecast response")
                    }
                }
                root.temperatureText = Math.round(temperature) + (root.units === "imperial" ? "°F" : "°C")
                root.feelsText = Math.round(apparentTemperature) + (root.units === "imperial" ? "°F" : "°C")
                root.humidityText = Math.round(humidity) + "%"
                root.windText = Math.round(windSpeed) + (root.units === "imperial" ? " mph" : " km/h")
                root.resolvedLocation = String(payload.location || root.locationLabel)
                root.forecast = forecastData.slice(0, 3)
                root.conditionText = payload.condition && payload.condition !== ""
                    ? String(payload.condition)
                    : root.descriptionFor(weatherCode)
                root.iconName = weatherCode >= 0
                    ? root.iconFor(weatherCode, isDay)
                    : root.iconForCondition(root.conditionText, isDay)
                root.weatherReady = true
            } catch (error) {
                console.warn("[WEATHER] response_invalid error=" + error)
                if (!root.weatherReady) {
                    root.temperatureText = ""
                    root.feelsText = ""
                    root.humidityText = ""
                    root.windText = ""
                    root.resolvedLocation = ""
                    root.forecast = []
                    root.conditionText = "Weather unavailable"
                }
            }
        }
    }

    function iconForCondition(condition, isDay) {
        var text = String(condition || "").toLowerCase()
        if (text.indexOf("thunder") !== -1 || text.indexOf("storm") !== -1) return isDay ? "weather-storm-day" : "weather-storm-night"
        if (text.indexOf("snow") !== -1 || text.indexOf("sleet") !== -1) return isDay ? "weather-snow-day" : "weather-snow-night"
        if (text.indexOf("rain") !== -1 || text.indexOf("drizzle") !== -1 || text.indexOf("shower") !== -1) return isDay ? "weather-showers-day" : "weather-showers-night"
        if (text.indexOf("cloud") !== -1 || text.indexOf("overcast") !== -1) return "weather-clouds"
        if (text.indexOf("mist") !== -1 || text.indexOf("fog") !== -1) return "weather-mist"
        return isDay ? "weather-clear-wind" : "weather-clear-wind-night"
    }

    Timer {
        interval: 900000
        repeat: true
        running: !!(root.bar && root.bar.barVisible && root.configured)
        onTriggered: root.refresh()
    }

    Connections {
        target: root.bar
        function onVisibleChanged() {
            if (root.bar && root.bar.barVisible) root.scheduleRefresh()
        }
    }

    Component.onCompleted: root.scheduleRefresh()
    onAureliaPathChanged: {
        root.configureWeatherPanel(weatherPanelLoader.item)
        root.scheduleRefresh()
    }
    onSettingsChanged: {
        root.weatherReady = false
        root.scheduleRefresh()
    }
    onWeatherReadyChanged: {
        if (!root.weatherReady && root.isVisible()) root.close()
    }
    onBarChanged: {
        root.configureWeatherPanel(weatherPanelLoader.item)
        root.scheduleRefresh()
    }
    onBarAnchorItemChanged: root.configureWeatherPanel(weatherPanelLoader.item)

    Row {
        id: weatherRow
        anchors.centerIn: parent
        spacing: Theme.spacingXs

        AureliaIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            height: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            iconSize: root.bar && root.bar.barIconFont ? root.bar.barIconFont : 13
            name: root.iconName
            fallbackName: "weather-clear"
            tint: Theme.accent
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.temperatureText
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: root.bar && root.bar.barTextSize ? root.bar.barTextSize : Theme.fontSizeSm
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            mouse.accepted = true
            root.openWeatherPanel()
        }
    }
}
