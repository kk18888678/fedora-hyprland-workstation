import QtQuick
import Quickshell
import Quickshell.Io

// T40 isolated resident-config fixture. It exercises only in-memory config
// transitions and writes the result into a test-owned temporary path.
ShellRoot {
    id: root

    readonly property string configSource: Quickshell.env("AURELIA_BAR_CONTROL_CONFIG_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_BAR_CONTROL_RESULT") || ""
    property var stateConfig: null
    property bool finished: false

    Loader {
        id: configLoader
        source: root.configSource
        onLoaded: {
            root.stateConfig = item
            root.evaluate()
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

    function ids(section) {
        var entries = root.stateConfig.config.bar.layout[section] || []
        return entries.map(function(entry) { return entry.id || entry })
    }

    function evaluate() {
        if (root.finished || !root.stateConfig || root.resultPath === "") return
        var state = root.stateConfig
        state.config = {
            version: 1,
            plugins: [{id: "fixture.plugin", setting: "keep"}],
            disabledPlugins: ["fixture.disabled", "aurelia.bar"],
            userOwnedState: {keep: true},
            bar: {
                id: "aurelia.bar",
                position: "top",
                transparent: false,
                centerAnchor: "aurelia.clock",
                layout: {
                    left: [{id: "aurelia.workspaces"}],
                    center: [{id: "aurelia.notifications"}, {id: "aurelia.clock"}, {id: "aurelia.weather"}],
                    right: [{id: "aurelia.tray"}, {id: "aurelia.network"}, {id: "aurelia.audio"},
                        {id: "aurelia.bluetooth"}, {id: "aurelia.monitor"}, {id: "aurelia.screenshot"},
                        {id: "aurelia.power"}]
                }
            }
        }

        state.configUsesDefaultBar = false
        var useResult = state.barOperations.useBar("fixture.alt")
        var usedBarId = state.config.bar.id
        var resetResult = state.barOperations.resetBar()
        var resetBarId = state.config.bar.id
        var positionResult = state.barOperations.setBarPosition("bottom")
        var transparentToggleResult = state.barOperations.setBarTransparent("toggle")
        var transparentAfterToggle = state.config.bar.transparent
        var transparentFalseResult = state.barOperations.setBarTransparent("false")
        var transparentAfterFalse = state.config.bar.transparent
        var positionAfterControl = state.config.bar.position

        var defaultsResult = state.barOperations.restoreBarDefaults()
        var afterDefaults = state.serializeConfig(state.config)
        var defaultsAgainResult = state.barOperations.restoreBarDefaults()
        var defaultsByteStable = afterDefaults === state.serializeConfig(state.config)

        var beforeInvalidPosition = state.serializeConfig(state.config)
        var invalidPositionResult = state.barOperations.setBarPosition("diagonal")
        var invalidPositionStable = beforeInvalidPosition === state.serializeConfig(state.config)
        var beforeInvalidTransparent = state.serializeConfig(state.config)
        var invalidTransparentResult = state.barOperations.setBarTransparent("maybe")
        var invalidTransparentStable = beforeInvalidTransparent === state.serializeConfig(state.config)

        root.finished = true
        resultFile.setText(JSON.stringify({
            useResult: useResult,
            usedBarId: usedBarId,
            resetResult: resetResult,
            resetBarId: resetBarId,
            positionResult: positionResult,
            position: positionAfterControl,
            transparentToggleResult: transparentToggleResult,
            transparentAfterToggle: transparentAfterToggle,
            transparentFalseResult: transparentFalseResult,
            transparentAfterFalse: transparentAfterFalse,
            defaultsResult: defaultsResult,
            defaultsAgainResult: defaultsAgainResult,
            defaultsByteStable: defaultsByteStable,
            defaultRight: root.ids("right"),
            pluginPreserved: state.config.plugins[0].id === "fixture.plugin" &&
                state.config.plugins[0].setting === "keep" &&
                state.config.disabledPlugins[0] === "fixture.disabled",
            defaultBarEnabled: state.config.disabledPlugins.indexOf("aurelia.bar") === -1,
            unknownStatePreserved: state.config.userOwnedState.keep === true,
            invalidPositionResult: invalidPositionResult,
            invalidPositionStable: invalidPositionStable,
            invalidTransparentResult: invalidTransparentResult,
            invalidTransparentStable: invalidTransparentStable
        }) + "\n")
    }

    Timer {
        interval: 9000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
