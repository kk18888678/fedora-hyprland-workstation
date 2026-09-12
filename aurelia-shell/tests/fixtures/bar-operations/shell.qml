import QtQuick
import Quickshell
import Quickshell.Io

// T12 fixture. It exercises ShellConfig's host-owned bar operations against
// an isolated in-memory metadata registry and temporary state file.
ShellRoot {
    id: root

    readonly property string configSource: Quickshell.env("AURELIA_BAR_OPERATIONS_CONFIG_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_BAR_OPERATIONS_RESULT") || ""
    property var stateConfig: null
    property bool evaluated: false

    QtObject {
        id: fakeBarRegistry

        signal widgetCatalogChanged()

        function allowMultipleFor(id) {
            return id === "fixture.multi" ? true : (id === "fixture.widget" || id === "fixture.put" ? false : null)
        }

        function instanceIdFor(id, entry) {
            var configured = entry && typeof entry === "object" ? entry.instanceId : ""
            return typeof configured === "string" && /^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(configured)
                ? configured : String(id || "")
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

    function ids(section) {
        var result = []
        var entries = root.stateConfig.config.bar.layout[section] || []
        for (var i = 0; i < entries.length; i++) result.push(entries[i].id || entries[i])
        return result
    }

    function instanceIds(section) {
        var result = []
        var entries = root.stateConfig.config.bar.layout[section] || []
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i]
            result.push(entry && typeof entry === "object" && entry.instanceId
                ? entry.instanceId : (entry.id || entry))
        }
        return result
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
            plugins: [],
            disabledPlugins: [],
            bar: {
                id: "aurelia.bar",
                position: "top",
                transparent: false,
                centerAnchor: "aurelia.clock",
                customBarValue: "preserve",
                layout: {
                    left: [{ id: "aurelia.workspaces" }],
                    center: [
                        { id: "aurelia.clock" },
                        { id: "aurelia.weather" },
                        { id: "fixture.multi", instanceId: "multi-a" },
                        { id: "fixture.multi", instanceId: "multi-b" }
                    ],
                    right: [{ id: "aurelia.tray" }]
                }
            },
            userOwnedState: {keep: true}
        }

        var enableResult = state.enablePlugin("fixture.widget", false, true, false, "right",
            {after: "aurelia.tray"}, false, false)
        var rightAfterEnable = root.ids("right")
        var setResult = state.setBarWidget("fixture.widget", "format", "custom",
            {section: "right", index: 1})
        var enableAgainResult = state.enablePlugin("fixture.widget", false, true, false, "right",
            {}, false, false)
        var preservedBeforeMove = state.config.bar.layout.right[1].format

        var putResult = state.enablePlugin("fixture.put", false, true, false, "center",
            {after: "missing.widget"}, true, false)
        var moveResult = state.moveBarWidget("fixture.widget", {section: "left", index: 0})
        var ambiguousResult = state.moveBarWidget("fixture.multi", {})
        var multiMoveResult = state.moveBarWidget("multi-a", {section: "right", index: 1})
        var moveBeforeResult = state.moveBarWidget("multi-a", {before: "aurelia.tray"})
        var multiSetResult = state.setBarWidget("fixture.multi", "mode", "fast",
            {fromSection: "center", fromIndex: 3})
        var invalidIndexResult = state.moveBarWidget("multi-b", {section: "right", index: -1})
        var invalidSectionResult = state.moveBarWidget("multi-b", {section: "middle"})

        var beforeInvalidMove = state.serializeConfig(state.config)
        var invalidMoveResult = state.moveBarWidget("multi-b", {after: "missing.widget"})
        var afterInvalidMove = state.serializeConfig(state.config)

        var disableResult = state.setPluginEnabled("fixture.widget", false, false, true)
        var enabledWhileDisabled = state.isPluginEnabled("fixture.widget", false)
        var reenableResult = state.setPluginEnabled("fixture.widget", false, true, true)
        var enabledAfterReenable = state.isPluginEnabled("fixture.widget", false)

        root.writeResult({
            enableResult: enableResult,
            rightAfterEnable: rightAfterEnable,
            setResult: setResult,
            enableAgainResult: enableAgainResult,
            preservedBeforeMove: preservedBeforeMove,
            putResult: putResult,
            moveResult: moveResult,
            ambiguousResult: ambiguousResult,
            multiMoveResult: multiMoveResult,
            moveBeforeResult: moveBeforeResult,
            multiSetResult: multiSetResult,
            invalidIndexResult: invalidIndexResult,
            invalidSectionResult: invalidSectionResult,
            invalidMoveResult: invalidMoveResult,
            invalidMoveStable: beforeInvalidMove === afterInvalidMove,
            disableResult: disableResult,
            enabledWhileDisabled: enabledWhileDisabled,
            reenableResult: reenableResult,
            enabledAfterReenable: enabledAfterReenable,
            leftIds: root.ids("left"),
            centerIds: root.ids("center"),
            rightIds: root.ids("right"),
            centerInstanceIds: root.instanceIds("center"),
            rightInstanceIds: root.instanceIds("right"),
            restoredFormat: state.config.bar.layout.left[0].format,
            multiMode: state.config.bar.layout.center[3].mode,
            customBarValue: state.config.bar.customBarValue,
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
