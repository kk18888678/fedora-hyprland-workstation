import QtQuick
import Quickshell
import Quickshell.Io

// T39 disposable fixture. It loads the real Power bar widget but injects a
// notifying fake panel so lifecycle and click routing are tested without
// running a power command or connecting to the live UPower service.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_POWER_FOUNDATION_RESULT") || ""
    readonly property string powerSource: Quickshell.env("AURELIA_POWER_FOUNDATION_SOURCE") || ""
    property bool finished: false
    property bool widgetLoaded: false

    QtObject {
        id: fakePanel
        property bool batteryPresent: true
        property bool shown: false
        property bool showPercentage: false
        property string statusText: "Charging"
        property bool actionFailureDidNotEscape: true

        function batteryIcon() { return "󰂈" }
        function open() { shown = true; return "ok" }
        function close() { shown = false; return "ok" }
        function toggle() { shown = !shown; return "ok" }
        function togglePercentage() { showPercentage = !showPercentage; return "ok" }
    }

    Loader {
        id: widgetLoader
        active: root.powerSource !== ""
        source: root.powerSource
        onLoaded: {
            root.widgetLoaded = item !== null
            if (!item) return
            item.panelOverride = fakePanel
            var initialVisible = item.visible === true
            item.handleClick(Qt.LeftButton)
            var shownAfterOpen = fakePanel.shown
            item.handleClick(Qt.RightButton)
            var percentageAfterRight = fakePanel.showPercentage
            item.handleClick(Qt.LeftButton)
            var shownAfterClose = fakePanel.shown
            fakePanel.batteryPresent = false
            var hiddenWithoutBattery = item.visible === false
            root.writeResult({
                widgetLoaded: root.widgetLoaded,
                initialVisible: initialVisible,
                shownAfterOpen: shownAfterOpen,
                percentageAfterRight: percentageAfterRight,
                shownAfterClose: shownAfterClose,
                hiddenWithoutBattery: hiddenWithoutBattery,
                actionFailureDidNotEscape: fakePanel.actionFailureDidNotEscape
            })
        }
    }

    FileView {
        id: resultFile
        path: root.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: false
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    function writeResult(value) {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        resultFile.setText(JSON.stringify(value) + "\n")
    }

    Timer {
        interval: 900
        running: true
        repeat: false
        onTriggered: {
            if (!root.finished) root.writeResult({widgetLoaded: root.widgetLoaded})
        }
    }
}
