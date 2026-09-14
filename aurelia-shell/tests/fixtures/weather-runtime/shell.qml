import QtQuick
import Quickshell
import Quickshell.Io

// T55/T58 weather failure fixture. The real bar widget receives a disposable
// backend that exits non-zero; the widget must expose unavailable state while
// the runtime log retains the exact diagnostic.
ShellRoot {
    id: root

    readonly property string widgetSource: Quickshell.env("AURELIA_WEATHER_WIDGET_SOURCE") || ""
    readonly property string backendRoot: Quickshell.env("AURELIA_WEATHER_BACKEND_ROOT") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_WEATHER_FAILURE_RESULT") || ""
    property var widget: null
    property bool finished: false

    QtObject {
        id: fakeBar
        property bool barVisible: true
        property bool vertical: false
        property int barSize: 26
        property int barIconCanvas: 16
        property int barIconFont: 13
        property int barTextSize: 12
        property color barForeground: "#ffffff"
    }

    Loader {
        id: widgetLoader
        source: root.widgetSource
        onLoaded: {
            root.widget = item
            item.bar = fakeBar
            item.aureliaPath = root.backendRoot
            item.settings = ({location: "auto"})
        }
    }

    FileView {
        id: resultFile
        path: root.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: true
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    function finish() {
        if (root.finished || !root.widget || root.widget.conditionText !== "Weather unavailable") return
        root.finished = true
        resultFile.setText(JSON.stringify({
            weatherReady: root.widget.weatherReady,
            conditionText: root.widget.conditionText,
            visible: root.widget.visible,
            temperatureText: root.widget.temperatureText,
            forecastCount: root.widget.forecast.length
        }) + "\n")
    }

    Timer {
        interval: 150
        repeat: true
        running: true
        onTriggered: root.finish()
    }

    Timer {
        interval: 5000
        repeat: false
        running: true
        onTriggered: Qt.quit()
    }
}
