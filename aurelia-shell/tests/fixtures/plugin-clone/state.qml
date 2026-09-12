import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    readonly property string configSource: Quickshell.env("AURELIA_CLONE_STATE_CONFIG_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_CLONE_STATE_RESULT") || ""
    property var stateConfig: null
    property bool evaluated: false

    QtObject {
        id: fakeBarRegistry

        signal widgetCatalogChanged()

        function allowMultipleFor(id) {
            return id === "aurelia.clock" || id === "aurelia.notifications" ? false : null
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
                layout: {
                    left: [{id: "aurelia.workspaces"}],
                    center: [{id: "aurelia.clock", format: "HH:mm"}],
                    right: []
                }
            }
        }

        var clockEnable = state.enablePlugin("tester.clock", false, true, false, "center", {}, false, false,
            "aurelia.clock")
        var clockEntry = state.config.bar.layout.center[0]
        var clockRecord = state.config.cloneSourceRestores && state.config.cloneSourceRestores[0]
        var clockDisable = state.setPluginEnabled("tester.clock", false, false, true, "aurelia.clock")
        var clockRestored = state.config.bar.layout.center[0]

        var notificationsEnable = state.enablePlugin("tester.notifications", false, true, true, "center", {}, false,
            false, "aurelia.notifications")
        var notificationsRecord = state.config.cloneSourceRestores && state.config.cloneSourceRestores[0]
        var notificationsSourceDisabled = state.config.disabledPlugins.indexOf("aurelia.notifications") !== -1
        var notificationsDisable = state.setPluginEnabled("tester.notifications", false, false, true,
            "aurelia.notifications")
        var notificationsRestored = state.config.bar.layout.center[0]

        var barEnable = state.enablePlugin("tester.bar", false, false, false, "center", {}, false, true,
            "aurelia.bar")
        var activeCloneBar = state.config.bar.id
        var barRecord = state.config.cloneSourceRestores && state.config.cloneSourceRestores[0]
        var barDisable = state.setPluginEnabled("tester.bar", false, false, false, "aurelia.bar")

        root.writeResult({
            clockEnable: clockEnable === "",
            clockCloneId: clockEntry.id,
            clockSettings: clockEntry.format,
            clockRecordSource: clockRecord ? clockRecord.sourceId : "",
            clockSourceBarPresent: clockRecord ? clockRecord.sourceBarPresent : false,
            clockDisable: clockDisable,
            clockRestoredId: clockRestored.id,
            clockRestoredSettings: clockRestored.format,
            clockRestoresCleared: !state.config.cloneSourceRestores,
            notificationsEnable: notificationsEnable === "",
            notificationsSourceDisabled: notificationsSourceDisabled,
            notificationsRecordSource: notificationsRecord ? notificationsRecord.sourceId : "",
            notificationsDisable: notificationsDisable,
            notificationsRestoredId: notificationsRestored.id,
            notificationsPluginRemoved: state.config.plugins.length === 0,
            notificationsRestoresCleared: !state.config.cloneSourceRestores,
            barEnable: barEnable === "",
            activeCloneBar: activeCloneBar,
            barRecordSource: barRecord ? barRecord.sourceId : "",
            barDisable: barDisable,
            activeRestoredBar: state.config.bar.id,
            userState: state.config.version
        })
    }

    Timer {
        interval: 9000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
