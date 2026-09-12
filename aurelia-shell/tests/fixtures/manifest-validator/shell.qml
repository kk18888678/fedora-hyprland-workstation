import QtQuick
import Quickshell
import Quickshell.Io

// T03 runtime-side manifest contract probe. The registry is loaded as a real
// QML component, while the matrix and result paths stay in a test sandbox.
ShellRoot {
    id: root

    readonly property string registrySource: Quickshell.env("AURELIA_MANIFEST_REGISTRY_SOURCE") || ""
    readonly property string matrixPath: Quickshell.env("AURELIA_MANIFEST_MATRIX") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_MANIFEST_RESULT") || ""
    property var runtimeRegistry: null
    property var matrix: null
    property bool evaluated: false
    property bool scanDone: false

    Loader {
        id: registryLoader
        source: root.registrySource
        onLoaded: {
            root.runtimeRegistry = item
            root.tryEvaluate()
        }
    }

    Connections {
        target: root.runtimeRegistry
        function onScanFinished() {
            root.scanDone = true
            root.tryEvaluate()
        }
    }

    FileView {
        id: matrixFile
        path: root.matrixPath
        printErrors: false
        onLoaded: {
            try {
                root.matrix = JSON.parse(text())
                root.tryEvaluate()
            } catch (error) {
                root.writeResult({ error: "matrix JSON could not be parsed" })
            }
        }
        onLoadFailed: root.writeResult({ error: "manifest matrix could not be loaded" })
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
        if (root.evaluated || !root.runtimeRegistry || !Array.isArray(root.matrix) || !root.scanDone) return
        var results = []
        for (var i = 0; i < root.matrix.length; i++) {
            var testCase = root.matrix[i]
            var original = JSON.stringify(testCase.manifest)
            var input = JSON.parse(original)
            var outcome = root.runtimeRegistry.validateManifest(
                input, "/tmp/aurelia-manifest-validator-fixture/" + String(testCase.name),
                testCase.firstParty === true)
            results.push({
                name: testCase.name,
                expected: testCase.expected === true,
                accepted: outcome !== null,
                inputUnchanged: JSON.stringify(input) === original
            })
        }
        root.writeResult({
            results: results,
            discoveryScanFinished: root.scanDone,
            discoveredCount: Object.keys(root.runtimeRegistry.installedPlugins || {}).length,
            discoveryError: String(root.runtimeRegistry.lastError || ""),
            catalog: root.runtimeRegistry.pluginCatalog()
        })
    }

    Timer {
        interval: 8000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
