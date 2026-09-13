import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    readonly property string sourcePath: Quickshell.env("AURELIA_BAR_DEFAULT_SOURCE") || ""
    readonly property string configSource: Quickshell.env("AURELIA_BAR_STATE_CONFIG_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_BAR_DEFAULT_RESULT") || ""
    property var defaults: null
    property var stateConfig: null
    property bool evaluated: false

    Loader {
        id: stateConfigLoader
        active: root.configSource !== ""
        source: root.configSource
        onLoaded: root.stateConfig = item
    }

    Loader {
        id: defaultsLoader
        source: root.sourcePath
        onLoaded: {
            root.defaults = item
            evaluateTimer.start()
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

    Timer {
        id: evaluateTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (root.evaluated || !root.defaults || root.resultPath === "") return
            if (!root.stateConfig || !root.stateConfig.barDefaults.loaded) {
                evaluateTimer.restart()
                return
            }
            root.evaluated = true
            var value = root.defaults.copy()
            var stateBar = root.stateConfig.config && root.stateConfig.config.bar ? root.stateConfig.config.bar : ({})
            var stateLayout = stateBar.layout || ({})
            var explicit = {
                version: 1,
                plugins: [],
                disabledPlugins: [],
                bar: {
                    id: "aurelia.bar",
                    position: "top",
                    transparent: false,
                    centerAnchor: "aurelia.clock",
                    layout: {
                        left: [],
                        center: [],
                        right: [{id: "aurelia.user-widget"}]
                    }
                }
            }
            var explicitNormalized = root.stateConfig.normalize(explicit)
            root.stateConfig.configUsesDefaultBar = false
            root.stateConfig.config = explicitNormalized
            root.stateConfig.syncDefaultBar()
            var explicitAfterSync = root.stateConfig.config.bar.layout.right
            resultFile.setText(JSON.stringify({
                loaded: root.defaults.loaded,
                id: value.id,
                position: value.position,
                centerAnchor: value.centerAnchor,
                left: value.layout.left.map(function(entry) { return entry.id }),
                center: value.layout.center.map(function(entry) { return entry.id }),
                right: value.layout.right.map(function(entry) { return entry.id }),
                stateRight: (stateLayout.right || []).map(function(entry) { return entry.id }),
                explicitRight: explicitAfterSync.map(function(entry) { return entry.id })
            }) + "\n")
        }
    }

    Timer {
        interval: 9000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
