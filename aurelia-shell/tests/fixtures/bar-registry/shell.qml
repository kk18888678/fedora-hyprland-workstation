import QtQuick
import Quickshell
import Quickshell.Io

// T06 runtime composition fixture. It scans the real current Aurelia plugin
// tree, then builds the dedicated bar-widget projection without creating bar
// windows or executing any widget entry point.
ShellRoot {
    id: root

    readonly property string registrySource: Quickshell.env("AURELIA_BAR_REGISTRY_PLUGIN_SOURCE") || ""
    readonly property string barRegistrySource: Quickshell.env("AURELIA_BAR_REGISTRY_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_BAR_REGISTRY_RESULT") || ""
    property var runtimeRegistry: null
    property var barRegistry: null
    property bool evaluated: false

    Loader {
        id: registryLoader
        source: root.registrySource
        onLoaded: {
            root.runtimeRegistry = item
            root.tryEvaluate()
        }
    }

    Loader {
        id: barRegistryLoader
        source: root.barRegistrySource
        onLoaded: {
            root.barRegistry = item
            root.tryEvaluate()
        }
    }

    Connections {
        target: root.runtimeRegistry
        function onScanFinished() {
            Qt.callLater(root.tryEvaluate)
        }
    }

    IpcHandler {
        target: "aurelia-bar-registry-fixture"

        function ping(): bool {
            return root.runtimeRegistry !== null && root.barRegistry !== null
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
        if (root.evaluated || root.resultPath === "") return
        root.evaluated = true
        resultFile.setText(JSON.stringify(value) + "\n")
    }

    function tryEvaluate() {
        if (root.evaluated || !root.runtimeRegistry || !root.barRegistry) return
        if (root.runtimeRegistry.scanning || root.runtimeRegistry.scanState === "idle" ||
            root.runtimeRegistry.scanState === "running") return
        root.barRegistry.pluginRegistry = root.runtimeRegistry
        root.barRegistry.sync()
        var ids = root.barRegistry.widgetIds
        var summaries = root.barRegistry.summaries()
        root.writeResult({
            scanState: root.runtimeRegistry.scanState,
            pluginCount: Object.keys(root.runtimeRegistry.installedPlugins || {}).length,
            widgetIds: ids,
            summaries: summaries,
            clockEntryPoint: root.barRegistry.entryPointUrl("aurelia.clock"),
            bluetoothSection: root.barRegistry.metadataFor("aurelia.bluetooth")
                ? root.barRegistry.metadataFor("aurelia.bluetooth").defaultSection
                : "",
            hasNotifications: root.barRegistry.hasWidget("aurelia.notifications")
        })
    }

    Timer {
        interval: 10000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
