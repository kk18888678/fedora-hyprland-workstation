import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    readonly property string registrySource: Quickshell.env("AURELIA_CLONE_REGISTRY_API_SOURCE") || ""
    readonly property string shellSource: Quickshell.env("AURELIA_CLONE_SHELL_API_SOURCE") || ""
    readonly property string barSource: Quickshell.env("AURELIA_CLONE_BAR_API_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_CLONE_FACADES_RESULT") || ""
    property var registryApi: null
    property var shellApi: null
    property var barApi: null
    property int loadedCount: 0
    property bool evaluated: false

    Loader {
        id: registryLoader
        onLoaded: {
            item.manifest = ({id: "tester.clock"})
            item.enabled = true
            root.registryApi = item
            root.loadedCount++
            root.tryEvaluate()
        }
    }

    Loader {
        id: shellLoader
        onLoaded: {
            root.shellApi = item
            root.loadedCount++
            root.tryEvaluate()
        }
    }

    Loader {
        id: barLoader
        onLoaded: {
            root.barApi = item
            root.loadedCount++
            root.tryEvaluate()
        }
    }

    Component.onCompleted: {
        registryLoader.setSource(root.registrySource, {pluginId: "tester.clock", compatibilityId: "aurelia.clock"})
        shellLoader.setSource(root.shellSource, {pluginId: "tester.clock", compatibilityId: "aurelia.clock"})
        barLoader.setSource(root.barSource, {
            ownerPluginId: "tester.clock",
            instanceId: "aurelia.clock",
            compatibilityId: "aurelia.clock"
        })
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

    function tryEvaluate() {
        if (root.evaluated || root.loadedCount !== 3) return
        root.evaluated = true
        resultFile.setText(JSON.stringify({
            registrySourceKnown: root.registryApi.isKnown("aurelia.clock"),
            registrySourceEnabled: root.registryApi.isEnabled("aurelia.clock"),
            registryForeignRejected: !root.registryApi.isKnown("foreign.plugin"),
            shellSourceOwns: root.shellApi.owns("aurelia.clock"),
            shellForeignRejected: !root.shellApi.owns("foreign.plugin"),
            barSourceAccepted: root.barApi.accepts("aurelia.clock"),
            barForeignRejected: !root.barApi.accepts("foreign.plugin")
        }) + "\n")
    }

    Timer {
        interval: 9000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
