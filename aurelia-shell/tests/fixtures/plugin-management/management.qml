import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    readonly property string modelSource: Quickshell.env("AURELIA_PLUGIN_MANAGEMENT_MODEL_SOURCE") || ""
    readonly property string cliPath: Quickshell.env("AURELIA_PLUGIN_MANAGEMENT_CLI") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_PLUGIN_MANAGEMENT_RESULT") || ""
    property var model: null
    property bool evaluated: false

    QtObject {
        id: fakeRegistry
        signal pluginsChanged()
    }

    QtObject {
        id: fakeHost

        function catalog() {
            return {
                plugins: [
                    {id: "aurelia.clock", name: "Clock", source: "first-party", kind: "bar-widget",
                     kinds: ["bar-widget"], firstParty: true, enabled: true, active: false,
                     loaded: true, visible: false, inBar: true, canDisable: true, clonedFrom: "", errorState: null},
                    {id: "tester.weather", name: "Weather Clone", source: "user", kind: "panel",
                     kinds: ["panel"], firstParty: false, enabled: false, active: false,
                     loaded: false, visible: false, inBar: false, canDisable: true,
                     clonedFrom: "aurelia.weather", errorState: null}
                ],
                rejected: [], scan: {state: "success"}
            }
        }
    }

    Loader {
        id: modelLoader
        source: root.modelSource
        onLoaded: {
            item.pluginRegistry = fakeRegistry
            item.pluginHost = fakeHost
            item.pluginCliBin = root.cliPath
            root.model = item
            item.open()
        }
    }

    Connections {
        target: root.model
        function onActionFinished(success, message) {
            if (root.evaluated || !root.model) return
            root.evaluated = true
            resultFile.setText(JSON.stringify({
                success: success,
                action: root.model.lastAction,
                pluginId: root.model.lastPluginId,
                hasEnable: root.hasAction("enable", "tester.weather"),
                hasUpdate: root.hasAction("update", "tester.weather"),
                hasRemove: root.hasAction("remove", "tester.weather"),
                hasValidate: root.hasAction("validate", "tester.weather"),
                hasClone: root.hasAction("clone", "aurelia.clock"),
                hasDisable: root.hasAction("disable", "aurelia.clock")
            }) + "\n")
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

    function hasAction(action, pluginId) {
        var rows = root.model ? root.model.pluginRows("") : []
        for (var i = 0; i < rows.length; i++)
            if (rows[i].pluginAction === action && rows[i].pluginId === pluginId) return true
        return false
    }

    Timer {
        interval: 120
        running: true
        repeat: false
        onTriggered: {
            if (!root.model || root.model.busy || root.evaluated) return
            var rows = root.model.pluginRows("")
            for (var i = 0; i < rows.length; i++) {
                if (rows[i].pluginAction === "remove" && rows[i].pluginId === "tester.weather") {
                    root.model.activate(rows[i])
                    return
                }
            }
            start()
        }
    }

    Timer {
        interval: 9000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
