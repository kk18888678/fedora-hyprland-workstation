import QtQuick
import Quickshell
import Quickshell.Io

// Regression fixture for the catalog/config signal boundary. The feedback
// connection models PluginRegistry emitting pluginsChanged after config
// changes; normalized equality must stop the signal cycle.
ShellRoot {
    id: root

    readonly property string barRegistrySource: Quickshell.env("AURELIA_BAR_CYCLE_REGISTRY_SOURCE") || ""
    readonly property string configSource: Quickshell.env("AURELIA_BAR_CYCLE_CONFIG_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_BAR_CYCLE_RESULT") || ""
    property var barRegistry: null
    property var stateConfig: null
    property int configChanges: 0
    property int feedbackSignals: 0
    property bool triggered: false

    QtObject {
        id: fakePluginRegistry

        property int revision: 1
        property var pluginIds: ["fixture.single"]
        property var installedPlugins: ({
            "fixture.single": {
                id: "fixture.single",
                name: "Single",
                version: "1.0.0",
                description: "Cycle fixture",
                kinds: ["bar-widget"],
                entryPoints: { barWidget: "Widget.qml" },
                barWidget: {
                    displayName: "Single",
                    description: "Cycle fixture",
                    category: "Testing",
                    allowMultiple: false
                }
            }
        })
        signal pluginsChanged()

        function entryPointUrl(id, kind) {
            return ""
        }

        function isEnabled(id) {
            return true
        }

        function hasActiveRuntimeFailure(id, kind) {
            return false
        }
    }

    Loader {
        id: barLoader
        source: root.barRegistrySource
        onLoaded: {
            item.pluginRegistry = fakePluginRegistry
            item.sync()
            root.barRegistry = item
            root.tryConfigure()
        }
    }

    Loader {
        id: configLoader
        source: root.configSource
        onLoaded: {
            item.barWidgetRegistry = root.barRegistry
            root.stateConfig = item
            root.tryConfigure()
        }
    }

    Connections {
        target: root.stateConfig
        function onConfigChanged() {
            root.configChanges++
            root.feedbackSignals++
            if (root.stateConfig && root.feedbackSignals < 4) fakePluginRegistry.pluginsChanged()
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
        if (root.triggered || root.resultPath === "") return
        root.triggered = true
        resultFile.setText(JSON.stringify(value) + "\n")
    }

    function tryConfigure() {
        if (root.triggered || !root.barRegistry || !root.stateConfig) return
        root.stateConfig.barWidgetRegistry = root.barRegistry
        root.stateConfig.config = {
            version: 1,
            plugins: [],
            disabledPlugins: [],
            bar: {
                id: "aurelia.bar",
                position: "top",
                transparent: false,
                centerAnchor: "",
                layout: {
                    left: [],
                    center: [
                        { id: "fixture.single", value: "first" },
                        { id: "fixture.single", value: "second" }
                    ],
                    right: []
                }
            }
        }
        fakePluginRegistry.pluginsChanged()
        Qt.callLater(function() {
            root.writeResult({
                configChanges: root.configChanges,
                feedbackSignals: root.feedbackSignals,
                centerCount: root.stateConfig.config.bar.layout.center.length,
                remainingValue: root.stateConfig.config.bar.layout.center[0].value,
                barRevision: root.barRegistry.revision
            })
        })
    }

    Timer {
        interval: 2000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
