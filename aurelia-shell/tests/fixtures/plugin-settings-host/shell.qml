import QtQuick
import Quickshell
import Quickshell.Io

// T13 fixture for the narrow live settings refresh boundary. The host
// reconfigures one resident object in place and calls its optional hook.
ShellRoot {
    id: root

    readonly property string hostSource: Quickshell.env("AURELIA_PLUGIN_SETTINGS_HOST_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_PLUGIN_SETTINGS_HOST_RESULT") || ""
    property var host: null
    property var target: null
    property bool evaluated: false

    QtObject {
        id: fakeShellConfig

        function settingsForEntry(id, selector) {
            return {mode: "refreshed", preserved: 11}
        }
    }

    QtObject {
        id: fakeRegistry

        property var shellConfig: fakeShellConfig
        property var pluginIds: []
        property var installedPlugins: ({
            "fixture.panel": {
                id: "fixture.panel",
                name: "Panel",
                version: "1.0.0",
                description: "Host fixture",
                kinds: ["panel"],
                entryPoints: {panel: "Panel.qml"}
            }
        })
        property int registryRevision: 1
        property int runtimeFailureRevision: 1
        signal pluginsChanged()
        signal pluginFailureRecorded(string pluginId, string kind, string phase,
                                     string sourcePath, string entryPoint, string detail)

        function isKnown(id) {
            return installedPlugins[id] !== undefined
        }

        function isEnabled(id) {
            return true
        }

        function primaryKind(id) {
            return "panel"
        }

        function hasActiveRuntimeFailure(id, kind) {
            return false
        }

        function entryPointUrl(id, kind) {
            return ""
        }
    }

    QtObject {
        id: residentTarget

        property var settings: ({mode: "old"})
        property int settingsRefreshes: 0

        function aureliaSettingsChanged() {
            settingsRefreshes++
        }
    }

    Loader {
        id: hostLoader
        source: root.hostSource
        onLoaded: {
            item.registry = fakeRegistry
            item.shellApi = null
            item.instances = ({"fixture.panel": residentTarget})
            root.target = residentTarget
            root.host = item
            item.refreshPluginSettings()
            Qt.callLater(root.writeResult)
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

    function writeResult() {
        if (root.evaluated || !root.host || !root.target || root.resultPath === "") return
        root.evaluated = true
        resultFile.setText(JSON.stringify({
            settings: root.target.settings,
            refreshes: root.target.settingsRefreshes,
            loadRevision: root.host.loadRevision
        }) + "\n")
    }

    Timer {
        interval: 3000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
