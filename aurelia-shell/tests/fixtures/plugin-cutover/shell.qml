import QtQuick
import Quickshell
import Quickshell.Io

// T27 cutover probe. ShellConfig is real; all state and output paths belong to
// the temporary test sandbox.
ShellRoot {
    id: root

    readonly property string configSource: Quickshell.env("AURELIA_CUTOVER_CONFIG_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_CUTOVER_RESULT") || ""
    property var stateConfig: null
    property bool finished: false

    Loader {
        id: configLoader
        source: root.configSource
        onLoaded: {
            root.stateConfig = item
            probeTimer.start()
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

    function evaluate() {
        if (root.finished || !root.stateConfig || root.stateConfig.revision < 1) return
        root.finished = true
        var config = root.stateConfig
        var defaultThirdParty = config.isPluginEnabled("example.panel", false)
        var defaultFirstParty = config.isPluginEnabled("aurelia.clock", true)

        config.config = {
            version: 1,
            plugins: [{id: "example.panel"}],
            disabledPlugins: []
        }
        var explicitThirdParty = config.isPluginEnabled("example.panel", false)

        config.config.disabledPlugins = ["example.panel"]
        var explicitlyDisabledThirdParty = !config.isPluginEnabled("example.panel", false)

        var defaults = config.defaultBarConfig()
        var serializedDefaults = JSON.parse(config.serializeConfig(config.defaultConfig()))
        resultFile.setText(JSON.stringify({
            defaultThirdPartyDisabled: !defaultThirdParty,
            defaultFirstPartyEnabled: defaultFirstParty,
            explicitThirdPartyEnabled: explicitThirdParty,
            explicitlyDisabledThirdParty: explicitlyDisabledThirdParty,
            builtInBarDefault: defaults.id === "aurelia.bar" &&
                defaults.position === "top" &&
                defaults.centerAnchor === "aurelia.clock",
            serializedDefaultVersion: serializedDefaults.version,
            serializedDefaultBar: serializedDefaults.bar.id
        }) + "\n")
    }

    Timer {
        id: probeTimer
        interval: 250
        repeat: true
        onTriggered: root.evaluate()
    }

    Timer {
        interval: 8000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
