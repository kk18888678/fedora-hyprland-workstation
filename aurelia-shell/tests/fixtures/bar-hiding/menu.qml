import QtQuick
import Quickshell
import Quickshell.Io

// T41 Menu Bar fixture. It uses an in-memory shell facade and a temporary
// user menu, so no live Aurelia IPC or user configuration is touched.
ShellRoot {
    id: root

    readonly property string modelSource: Quickshell.env("AURELIA_MENU_MODEL_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_MENU_MODEL_RESULT") || ""
    property var model: null
    property bool evaluated: false

    QtObject {
        id: fakeBar
        property bool barHidden: false
        property string position: "top"
        property bool transparent: false
    }

    QtObject {
        id: fakeShell
        property string lastAction: ""
        function summon(id, payload) { lastAction = "summon:" + id; return "ok" }
        function rescanPlugins() { lastAction = "rescan"; return "ok" }
        function toggle(id, payload) { lastAction = "toggle:" + id; return "pending" }
        function setBarPosition(value) { lastAction = "position:" + value; return "ok" }
        function setBarTransparent(value) { lastAction = "transparent:" + value; return "ok" }
        function restoreBarDefaults() { lastAction = "bar-defaults"; return "ok" }
    }

    QtObject {
        id: fakeRegistry
        signal pluginsChanged()
    }

    QtObject {
        id: fakeHost
        function activeBar() { return fakeBar }
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
        printErrors: true
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    function findAction(action) {
        if (!root.model) return null
        for (var i = 0; i < root.model.rows.length; i++)
            if (root.model.rows[i].menuAction === action) return root.model.rows[i]
        return null
    }

    Timer {
        interval: 350
        running: true
        repeat: false
        onTriggered: {
            if (root.evaluated || !root.model) {
                if (!root.evaluated) restart()
                return
            }
            var toggle = root.findAction("toggle-bar")
            var position = root.findAction("bar-position-bottom")
            var transparency = root.findAction("bar-transparent-toggle")
            var defaults = root.findAction("bar-defaults")
            var custom = false
            var invalid = false
            for (var i = 0; i < root.model.rows.length; i++) {
                if (root.model.rows[i].menuId === "user.custom") custom = true
                if (root.model.rows[i].menuId === "user.invalid") invalid = true
            }
            var toggleAccepted = toggle ? root.model.activate(toggle) : false
            var positionAccepted = position ? root.model.activate(position) : false
            var transparencyAccepted = transparency ? root.model.activate(transparency) : false
            var defaultsAccepted = defaults ? root.model.activate(defaults) : false
            root.evaluated = true
            resultFile.setText(JSON.stringify({
                menuBarToggle: !!toggle,
                toggleChecked: !!(toggle && toggle.checked === true),
                toggleAccepted: toggleAccepted,
                positionAccepted: positionAccepted,
                transparencyAccepted: transparencyAccepted,
                defaultsAccepted: defaultsAccepted,
                userExtension: custom,
                invalidRejected: !invalid,
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
