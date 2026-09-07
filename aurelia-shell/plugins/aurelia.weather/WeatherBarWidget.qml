import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../theme"

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
    property string temperatureText: ""
    property string conditionText: "…"
    property string iconName: "weather-clear"
    property string feelsText: ""
    property string humidityText: ""
    property string windText: ""
    property string resolvedLocation: ""
    property var forecast: []

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

    implicitWidth: weatherRow.implicitWidth + Theme.spacingSm * 2
    implicitHeight: bar ? bar.barSize : 40

    Loader {
        id: weatherPanelLoader
        active: true
        source: Qt.resolvedUrl("WeatherPanel.qml")
        onLoaded: root.configureWeatherPanel(item)
    }

    function configureWeatherPanel(target) {
        if (!target) return
        if ("weatherWidget" in target) target.weatherWidget = root
        if ("barSize" in target) target.barSize = root.bar ? root.bar.barSize : 32
    }

    function openWeatherPanel() {
        if (weatherPanelLoader.item && typeof weatherPanelLoader.item.open === "function") weatherPanelLoader.item.open()
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
        if (!root.configured || weatherProcess.running || !(root.bar && root.bar.visible)) return
        var command = [root.backendBin, "fetch", "--units", root.units]
        if (root.hasCoordinates) {
            command.push("--latitude", root.latitude, "--longitude", root.longitude)
        } else if (root.location === "auto") {
            command.push("--auto")
        } else {
            command.push("--location", root.location)
        }
        weatherProcess.command = command
        weatherProcess.running = true
    }

    function iconFor(code, isDay) {
        if (code === 0) return isDay ? "weather-clear" : "weather-clear-night"
        if (code === 1 || code === 2) return isDay ? "weather-few-clouds" : "weather-clouds-night"
        if (code === 3 || code === 45 || code === 48) return "weather-overcast"
        if (code >= 51 && code <= 67) return "weather-showers"
        if (code >= 71 && code <= 86) return "weather-snow"
        if (code >= 95) return "weather-storm"
        return "weather-clear"
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
                root.temperatureText = ""
                root.conditionText = root.configured ? "Weather unavailable" : root.locationLabel
                return
            }
            try {
                var payload = JSON.parse(weatherStdout.text.trim())
                var temperature = Number(payload.temperature)
                var weatherCode = Number(payload.weatherCode)
                var isDay = Number(payload.isDay) === 1
                if (!isFinite(temperature) || !isFinite(weatherCode)) throw new Error("invalid weather response")
                root.temperatureText = Math.round(temperature) + (root.units === "imperial" ? "°F" : "°C")
                root.feelsText = Math.round(Number(payload.apparentTemperature)) + (root.units === "imperial" ? "°F" : "°C")
                root.humidityText = Math.round(Number(payload.humidity)) + "%"
                root.windText = Math.round(Number(payload.windSpeed)) + (root.units === "imperial" ? " mph" : " km/h")
                root.resolvedLocation = String(payload.location || root.locationLabel)
                root.forecast = Array.isArray(payload.forecast) ? payload.forecast : []
                root.conditionText = payload.condition && payload.condition !== ""
                    ? String(payload.condition)
                    : root.descriptionFor(weatherCode)
                root.iconName = weatherCode >= 0
                    ? root.iconFor(weatherCode, isDay)
                    : root.iconForCondition(root.conditionText, isDay)
            } catch (error) {
                console.warn("[WEATHER] response_invalid error=" + error)
                root.temperatureText = ""
                root.feelsText = ""
                root.humidityText = ""
                root.windText = ""
                root.forecast = []
                root.conditionText = "Weather unavailable"
            }
        }
    }

    function iconForCondition(condition, isDay) {
        var text = String(condition || "").toLowerCase()
        if (text.indexOf("thunder") !== -1 || text.indexOf("storm") !== -1) return "weather-storm"
        if (text.indexOf("snow") !== -1 || text.indexOf("sleet") !== -1) return "weather-snow"
        if (text.indexOf("rain") !== -1 || text.indexOf("drizzle") !== -1 || text.indexOf("shower") !== -1) return "weather-showers"
        if (text.indexOf("cloud") !== -1 || text.indexOf("overcast") !== -1 || text.indexOf("mist") !== -1) return "weather-overcast"
        return isDay ? "weather-clear" : "weather-clear-night"
    }

    Timer {
        interval: 900000
        repeat: true
        running: !!(root.bar && root.bar.visible && root.configured)
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
    onAureliaPathChanged: root.configureWeatherPanel(weatherPanelLoader.item)
    onBarChanged: root.configureWeatherPanel(weatherPanelLoader.item)

    Row {
        id: weatherRow
        anchors.centerIn: parent
        spacing: Theme.spacingXs

        IconImage {
            anchors.verticalCenter: parent.verticalCenter
            width: 17
            height: 17
            source: Quickshell.iconPath(root.iconName, "weather-clear")
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.temperatureText !== "" ? root.temperatureText : "…"
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
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
