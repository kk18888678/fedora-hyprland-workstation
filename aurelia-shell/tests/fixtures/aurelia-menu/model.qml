import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    readonly property string modelSource: Quickshell.env("AURELIA_MENU_MODEL_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_MENU_MODEL_RESULT") || ""
    property var model: null
    property bool evaluated: false

    QtObject {
        id: fakeShell
        property string lastAction: ""
        function summon(id, payload) { lastAction = "summon:" + id; return "ok" }
        function rescanPlugins() { lastAction = "rescan"; return "ok" }
        function toggle(id, payload) { lastAction = "toggle:" + id; return "closed" }
    }

    QtObject {
        id: fakeRegistry
        signal pluginsChanged()
    }

    QtObject {
        id: fakeHost
        function activeBar() { return {barHidden: false} }
        function catalog() {
            return {plugins: [{id: "tester.weather", name: "Weather Clone", source: "user", kind: "panel", enabled: true}]}
        }
    }

    Loader {
        id: modelLoader
        source: root.modelSource
        onLoaded: {
            item.shell = fakeShell
            item.pluginRegistry = fakeRegistry
            item.pluginHost = fakeHost
            root.model = item
            item.open("{}")
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

    function findRow(action, id) {
        if (!root.model) return null
        for (var i = 0; i < root.model.rows.length; i++) {
            var row = root.model.rows[i]
            if (row.menuAction === action && row.pluginId === (id || "")) return row
        }
        return null
    }

    Timer {
        id: evaluateTimer
        interval: 350
        running: true
        repeat: false
        onTriggered: {
            if (root.evaluated || !root.model) {
                if (!root.evaluated) evaluateTimer.start()
                return
            }
            var rows = root.model.rows
            var toggleRow = root.findRow("toggle-bar", "")
            var providerRow = root.findRow("open-command-center", "tester.weather")
            var customFound = false
            var invalidFound = false
            for (var i = 0; i < rows.length; i++) {
                if (rows[i].menuId === "user.custom") customFound = true
                if (rows[i].menuId === "user.invalid") invalidFound = true
            }
            var toggleResult = toggleRow ? root.model.activate(toggleRow) : false
            root.evaluated = true
            resultFile.setText(JSON.stringify({
                commandCenter: !!root.findRow("open-command-center", ""),
                provider: !!providerRow,
                custom: customFound,
                invalidRejected: !invalidFound,
                checked: toggleRow ? toggleRow.checked === true : false,
                toggleResult: toggleResult,
                lastAction: fakeShell.lastAction
            }) + "\n")
        }
    }

    Timer {
        interval: 9000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
