import QtQuick
import Quickshell
import Quickshell.Io

// T13 fixture. Shared shell settings are updated and reset through the
// ShellConfig owner while a separate plugin-owned state file remains outside
// the mutation path.
ShellRoot {
    id: root

    readonly property string configSource: Quickshell.env("AURELIA_PLUGIN_SETTINGS_CONFIG_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_PLUGIN_SETTINGS_RESULT") || ""
    property var stateConfig: null
    property bool evaluated: false

    QtObject {
        id: fakeBarRegistry

        function allowMultipleFor(id) {
            return id === "fixture.multi" ? true : (id === "fixture.widget" ? false : null)
        }

        function instanceIdFor(id, entry) {
            var configured = entry && typeof entry === "object" ? entry.instanceId : ""
            return typeof configured === "string" && /^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(configured)
                ? configured : String(id || "")
        }

        function settingsFor(id, entry) {
            var result = id === "fixture.widget" ? {format: "default", shipped: true} : {}
            if (!entry || typeof entry !== "object" || Array.isArray(entry)) return result
            for (var key in entry) {
                if (key !== "id" && key !== "instanceId" && key !== "settings") result[key] = entry[key]
            }
            return result
        }
    }

    Loader {
        id: configLoader
        source: root.configSource
        onLoaded: {
            item.barWidgetRegistry = fakeBarRegistry
            root.stateConfig = item
            root.tryEvaluate()
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

    function tryEvaluate() {
        if (root.evaluated || !root.stateConfig) return
        var state = root.stateConfig
        state.config = {
            version: 1,
            plugins: [
                {id: "fixture.panel", mode: "wide", pluginUnknown: 7}
            ],
            disabledPlugins: [],
            bar: {
                id: "aurelia.bar",
                position: "top",
                transparent: false,
                centerAnchor: "",
                layout: {
                    left: [],
                    center: [
                        {id: "fixture.widget", format: "user", unknownKeep: 9},
                        {id: "fixture.multi", instanceId: "multi-a", mode: "a"},
                        {id: "fixture.multi", instanceId: "multi-b", mode: "b"}
                    ],
                    right: []
                }
            },
            userOwnedState: {keep: true}
        }

        var effectiveBefore = state.settingsForEntry("fixture.widget", {})
        var updateBar = state.updateEntryInline("fixture.widget",
            {format: "updated", newValue: "kept"}, {})
        var unchangedUpdate = state.updateEntryInline("fixture.widget",
            {format: "updated"}, {})
        var updatePanel = state.updateEntryInline("fixture.panel",
            {mode: "compact", panelUnknown: 8}, {})
        var rejectedFunction = state.updateEntryInline("fixture.widget",
            {bad: function() { return "not-json" }}, {})
        var rejectedLarge = state.updateEntryInline("fixture.widget",
            {tooLarge: new Array(5000).join("x")}, {})
        var ambiguousUpdate = state.updateEntryInline("fixture.multi",
            {mode: "all"}, {})
        var explicitUpdate = state.updateEntryInline("multi-b",
            {mode: "updated-b"}, {})
        var resetMulti = state.resetEntryInline("multi-b", {})
        var resetAgain = state.resetEntryInline("multi-b", {})
        var selectorRejected = state.updateEntryInline("fixture.widget",
            {format: "bad"}, {before: "fixture.panel"})

        root.writeResult({
            effectiveBefore: effectiveBefore,
            updateBar: updateBar,
            unchangedUpdate: unchangedUpdate,
            updatePanel: updatePanel,
            rejectedFunction: rejectedFunction,
            rejectedLarge: rejectedLarge,
            ambiguousUpdate: ambiguousUpdate,
            explicitUpdate: explicitUpdate,
            resetMulti: resetMulti,
            resetAgain: resetAgain,
            selectorRejected: selectorRejected,
            widget: state.config.bar.layout.center[0],
            multiB: state.config.bar.layout.center[2],
            panel: state.config.plugins[0],
            centerCount: state.config.bar.layout.center.length,
            userOwned: state.config.userOwnedState.keep
        })
    }

    Timer {
        interval: 9000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
