import QtQuick
import Quickshell
import Quickshell.Io

// T32 relocation fixture. The loader receives a URL only after the shared
// source contract has validated the caller-provided root and relative member.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_SOURCE_BOUNDARY_RESULT") || ""
    readonly property string sourceRoot: Quickshell.env("AURELIA_SOURCE_BOUNDARY_ROOT") || ""
    readonly property string resolverSource: Quickshell.env("AURELIA_SOURCE_BOUNDARY_RESOLVER") || ""
    readonly property var pluginSourceResolver: resolverLoader.item
    readonly property var sourceDescriptor: pluginSourceResolver
        ? pluginSourceResolver.descriptor("fixture.source", "panel", root.sourceRoot, "Healthy.qml", "")
        : ({valid: false, sourceRoot: "", relativeEntryPoint: "", sourcePath: "", url: ""})
    readonly property var invalidDescriptor: pluginSourceResolver
        ? pluginSourceResolver.descriptor("fixture.source", "panel", root.sourceRoot, "../outside.qml", "")
        : ({valid: false, sourceRoot: "", relativeEntryPoint: "", sourcePath: "", url: ""})
    readonly property string sourcePath: root.sourceDescriptor.sourcePath
    readonly property string sourceUrl: root.sourceDescriptor.url
    readonly property string invalidEntryUrl: root.invalidDescriptor.url
    readonly property string remotePath: pluginSourceResolver
        ? pluginSourceResolver.pathFromUrl("file://remote/outside.qml") : "unavailable"
    property bool healthyLoaded: false
    property string healthyMarker: ""
    property bool finished: false

    Loader {
        id: resolverLoader
        source: root.resolverSource
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

    Loader {
        id: healthyLoader
        active: root.sourceUrl !== ""
        source: root.sourceUrl
        onLoaded: {
            root.healthyLoaded = item !== null
            root.healthyMarker = item && item.marker ? String(item.marker) : ""
        }
    }

    function writeResult() {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        resultFile.setText(JSON.stringify({
            healthyLoaded: root.healthyLoaded,
            healthyMarker: root.healthyMarker,
            sourceRoot: root.sourceRoot,
            descriptorValid: root.sourceDescriptor.valid === true,
            descriptorSourceRoot: root.sourceDescriptor.sourceRoot,
            descriptorEntryPoint: root.sourceDescriptor.relativeEntryPoint,
            sourcePath: root.sourcePath,
            sourceUrl: root.sourceUrl,
            roundTripPath: root.pluginSourceResolver
                ? root.pluginSourceResolver.pathFromUrl(root.sourceUrl) : "",
            invalidEntryUrl: root.invalidEntryUrl,
            remotePath: root.remotePath
        }) + "\n")
    }

    Timer {
        interval: 1500
        running: true
        repeat: false
        onTriggered: root.writeResult()
    }
}
