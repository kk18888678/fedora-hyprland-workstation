import QtQuick
import Quickshell
import Quickshell.Io

// T04 discovery fixture. It loads the real PluginRegistry and points it at
// test-owned roots; no plugin entry point is constructed or executed.
ShellRoot {
    id: root

    readonly property string registrySource: Quickshell.env("AURELIA_DISCOVERY_REGISTRY_SOURCE") || ""
    readonly property string firstPartyDir: Quickshell.env("AURELIA_DISCOVERY_FIRST_PARTY") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_DISCOVERY_RESULT") || ""
    readonly property bool malformedProbe: Quickshell.env("AURELIA_DISCOVERY_MALFORMED") === "1"
    property bool evaluated: false

    Loader {
        id: registryLoader
        source: root.registrySource
        onLoaded: {
            item.firstPartyDir = root.firstPartyDir
            root.runtimeRegistry = item
            if (root.malformedProbe) {
                item.parseScanOutput("unexpected output from a broken scanner\n")
                Qt.callLater(function() {
                    root.writeResult({
                        scanState: item.scanState,
                        scanFailureClass: item.scanFailureClass,
                        lastError: item.lastError,
                        rejectedCount: item.rejectedCount
                    })
                })
            } else if (!item.scan()) {
                root.writeResult({ error: "discovery scan could not start" })
            }
        }
    }

    property var runtimeRegistry: null

    Connections {
        target: root.runtimeRegistry
        function onScanFinished() {
            if (!root.malformedProbe) root.evaluate()
        }
    }

    IpcHandler {
        target: "aurelia-discovery-fixture"

        function ping(): bool {
            return root.runtimeRegistry !== null
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

    function evaluate() {
        if (root.evaluated || !root.runtimeRegistry) return
        var ids = Object.keys(root.runtimeRegistry.installedPlugins || {}).sort()
        var sources = {}
        for (var i = 0; i < ids.length; i++)
            sources[ids[i]] = String(root.runtimeRegistry.installedPlugins[ids[i]].__sourceDir || "")
        root.writeResult({
            scanState: root.runtimeRegistry.scanState,
            scanFailureClass: root.runtimeRegistry.scanFailureClass,
            lastError: root.runtimeRegistry.lastError,
            rejectedCount: root.runtimeRegistry.rejectedCount,
            ids: ids,
            sources: sources,
            catalog: root.runtimeRegistry.pluginCatalog()
        })
    }

    Timer {
        interval: 10000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
