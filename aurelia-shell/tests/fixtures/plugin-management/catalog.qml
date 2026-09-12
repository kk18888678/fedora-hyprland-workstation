import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    readonly property string registrySource: Quickshell.env("AURELIA_PLUGIN_CATALOG_REGISTRY_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_PLUGIN_CATALOG_RESULT") || ""
    property var registry: null
    property bool evaluated: false

    QtObject {
        id: fakeShellConfig
        property var config: ({
            version: 1,
            plugins: [{id: "tester.clock"}],
            disabledPlugins: [],
            bar: {id: "aurelia.bar", layout: {left: [], center: [{id: "tester.clock"}], right: []}}
        })

        function isPluginEnabled(id, firstParty) {
            return firstParty === true || id === "tester.clock"
        }

        function findBarLocation(configValue, id, section) {
            return id === "tester.clock" ? ({found: true, section: "center", index: 0}) : ({found: false})
        }
    }

    Loader {
        id: registryLoader
        source: root.registrySource
        onLoaded: {
            item.shellConfig = fakeShellConfig
            item.installedPlugins = ({
                "aurelia.bar": {
                    id: "aurelia.bar", name: "Aurelia Bar", version: "1.0.0", description: "Bar",
                    kinds: ["bar"], entryPoints: {bar: "Bar.qml"}, __sourceDir: "/tmp/aurelia.bar",
                    __manifestPath: "/tmp/aurelia.bar/manifest.json", __isFirstParty: true
                },
                "aurelia.clock": {
                    id: "aurelia.clock", name: "Clock", version: "1.0.0", description: "Clock",
                    kinds: ["bar-widget"], entryPoints: {barWidget: "Clock.qml"},
                    barWidget: {displayName: "Clock", description: "Clock", category: "Time",
                                 allowMultiple: false, defaultSection: "center"},
                    __sourceDir: "/tmp/aurelia.clock", __manifestPath: "/tmp/aurelia.clock/manifest.json",
                    __isFirstParty: true
                },
                "tester.clock": {
                    id: "tester.clock", name: "My Clock", version: "1.0.0", description: "Clone",
                    kinds: ["bar-widget"], entryPoints: {barWidget: "Clock.qml"},
                    barWidget: {displayName: "My Clock", description: "Clock", category: "Time",
                                 allowMultiple: false, defaultSection: "center"},
                    aurelia: {clonedFrom: "aurelia.clock"},
                    __sourceDir: "/tmp/tester.clock", __manifestPath: "/tmp/tester.clock/manifest.json",
                    __isFirstParty: false
                }
            })
            item.runtimeFailures = ({
                "tester.clock::bar-widget": {id: "tester.clock", kind: "bar-widget",
                    detail: "fixture failure", quarantined: true, generation: 0}
            })
            root.registry = item
            Qt.callLater(root.evaluate)
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

    function find(catalog, id) {
        for (var i = 0; i < catalog.plugins.length; i++)
            if (catalog.plugins[i].id === id) return catalog.plugins[i]
        return null
    }

    function evaluate() {
        if (root.evaluated || !root.registry || root.resultPath === "") return
        root.evaluated = true
        var catalog = root.registry.pluginCatalog()
        var bar = root.find(catalog, "aurelia.bar")
        var source = root.find(catalog, "aurelia.clock")
        var clone = root.find(catalog, "tester.clock")
        resultFile.setText(JSON.stringify({
            barActive: bar && bar.active === true,
            source: source ? {source: source.source, kind: source.kind, canDisable: source.canDisable} : null,
            clone: clone ? {
                source: clone.source,
                kind: clone.kind,
                enabled: clone.enabled,
                inBar: clone.inBar,
                clonedFrom: clone.clonedFrom,
                errorDetail: clone.errorState ? clone.errorState.detail : ""
            } : null,
            rejected: catalog.rejected.length
        }) + "\n")
    }

    Timer {
        interval: 9000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
