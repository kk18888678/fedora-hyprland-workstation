import QtQuick
import Quickshell
import Quickshell.Io

// T32 registry fixture. It uses the real manifest registry and asks it for a
// source descriptor after scanning a disposable first-party tree.
ShellRoot {
    id: root

    readonly property string registrySource: Quickshell.env("AURELIA_SOURCE_REGISTRY_SOURCE") || ""
    readonly property string firstPartyRoot: Quickshell.env("AURELIA_SOURCE_REGISTRY_FIRST_PARTY") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_SOURCE_REGISTRY_RESULT") || ""
    property var registry: null
    property bool finished: false

    Loader {
        id: registryLoader
        source: root.registrySource
        onLoaded: {
            root.registry = item
            item.firstPartyDir = root.firstPartyRoot
            if (!item.scan()) root.writeResult({error: "registry scan could not start"})
        }
    }

    Connections {
        target: root.registry
        function onScanFinished() { root.evaluate() }
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

    function evaluate() {
        if (root.finished || !root.registry || root.registry.scanning) return
        var descriptor = root.registry.sourceDescriptor("aurelia.source-fixture", "panel")
        var invalid = root.registry.sourceDescriptor("aurelia.source-fixture", "overlay")
        root.writeResult({
            scanState: root.registry.scanState,
            descriptorValid: descriptor.valid === true,
            descriptorId: descriptor.id,
            descriptorKind: descriptor.kind,
            descriptorSourceRoot: descriptor.sourceRoot,
            descriptorEntryPoint: descriptor.relativeEntryPoint,
            descriptorSourcePath: descriptor.sourcePath,
            descriptorUrl: descriptor.url,
            descriptorError: descriptor.error,
            legacyUrl: root.registry.entryPointUrl("aurelia.source-fixture", "panel"),
            invalidUrl: invalid.url,
            invalidError: invalid.error
        })
    }

    Timer {
        interval: 6000
        running: true
        repeat: false
        onTriggered: root.writeResult({error: "registry descriptor fixture timed out"})
    }
}
