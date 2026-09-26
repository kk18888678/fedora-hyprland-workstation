import QtQuick
import Quickshell
import Quickshell.Io

// Regression fixture for the agents bar widget's backend-path race: the bar
// host assigns `aureliaPath` only after the widget is constructed, so the
// widget must not try the installed backend path first and must retry once the
// checkout path arrives.
ShellRoot {
    id: root

    readonly property string widgetSource: Quickshell.env("AGENTS_WIDGET_SOURCE") || ""
    readonly property string aureliaPath: Quickshell.env("AGENTS_AURELIA_PATH") || ""
    readonly property string resultPath: Quickshell.env("AGENTS_RACE_RESULT") || ""

    property var mockBar: QtObject {
        property bool barVisible: true
        property bool vertical: false
        property int barSize: 26
        property int barIconCanvas: 16
        property int barIconFont: 13
        property int barTextSize: 13
        property color barForeground: "#ffffff"
    }

    Loader {
        id: widgetLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = root.mockBar
            // The host assigns aureliaPath after construction.
            assignTimer.restart()
        }
    }

    Timer {
        id: assignTimer
        interval: 300
        repeat: false
        onTriggered: if (widgetLoader.item) widgetLoader.item.aureliaPath = root.aureliaPath
    }

    Timer {
        interval: 9000
        running: true
        onTriggered: {
            var widget = widgetLoader.item
            var payload = {
                loaded: widget ? widget.loaded === true : false,
                agents: widget && widget.agents ? widget.agents.length : -1,
                hasAgents: widget ? widget.hasAgents === true : false,
                lastError: widget ? String(widget.lastError || "") : "no-widget",
                stateKey: widget && widget.barState ? String(widget.barState.key) : "no-state",
                hasApi: widget && typeof widget.open === "function" &&
                    typeof widget.close === "function" &&
                    typeof widget.toggle === "function" &&
                    typeof widget.isVisible === "function",
                square: widget ? widget.implicitWidth === widget.implicitHeight : false
            }
            writer.command = ["/bin/sh", "-c",
                "printf '%s' " + JSON.stringify(JSON.stringify(payload)) + " > " + root.resultPath]
            writer.running = true
        }
    }

    Process { id: writer; running: false; onExited: Qt.quit() }
}
